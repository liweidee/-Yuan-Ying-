import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;
import 'package:qjs_ultra/qjs_ultra.dart';

import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/t4/services/qjs_catvod_runtime_js.dart';
import 'package:yuanying/t4/services/site_switch_result.dart';
import 'package:yuanying/utils/business_exception.dart';
import 'package:yuanying/utils/qjs_platform_helper.dart';
import 'package:yuanying/utils/storage.dart';

/// 基于 QJS + CatLib 的 CatVod 运行时。
///
/// QJS 引擎和 CatVod 源都在 worker isolate 中运行；主 isolate 只负责 RPC
/// 和同步 HTTP 桥，避免 CatLib 的同步 `_http`/`req` 阻塞 Flutter UI。
class QjsCatVodService implements ISpiderService {
  QjsCatVodService({
    String? libraryPath,
    String? catLibRoot,
    Dio? dio,
  }) : _libraryPathOverride = libraryPath,
       _catLibRootOverride = catLibRoot,
       _dio = dio ?? _createCatVodDio();

  final String? _libraryPathOverride;
  final String? _catLibRootOverride;
  final Dio _dio;

  Isolate? _worker;
  SendPort? _commandPort;
  ReceivePort? _responsePort;
  StreamSubscription<dynamic>? _responseSub;
  ReceivePort? _exitPort;
  StreamSubscription<dynamic>? _exitSub;
  HttpServer? _syncBridge;

  final Map<int, Completer<dynamic>> _pending = {};
  int _nextId = 1;
  bool _workerReady = false;
  Future<void>? _initializing;
  String? _currentKey;
  Map<String, dynamic> _currentExt = {};
  // 源已成功执行 init，可安全发起业务调用。
  bool _sourceLoaded = false;
  final Map<String, Object?> _globalProperties = {};

  @override
  String? get currentKey => _currentKey;

  bool get isReady => _workerReady;
  bool get isSourceLoaded => _sourceLoaded;

  Future<void> initialize() {
    final active = _initializing;
    if (active != null) return active;

    final completer = Completer<void>();
    _initializing = completer.future;
    unawaited(() async {
      try {
        await _initializeWorker();
        completer.complete();
      } catch (error, stackTrace) {
        _initializing = null;
        completer.completeError(error, stackTrace);
      }
    }());
    return completer.future;
  }

  Future<void> _initializeWorker() async {
    if (!QjsPlatformHelper.isSupported) {
      throw UnsupportedError('QJS CatVod only supports Android and Windows');
    }
    _checkQjsPlugin();

    await _startSyncBridge();
    final libraryPath =
        _libraryPathOverride ?? await QjsPlatformHelper.requireLibraryPath();
    final catLibRoot = _catLibRootOverride ?? await _resolveCatLibRoot();

    _responsePort = ReceivePort();
    _responseSub = _responsePort!.listen(_onWorkerMessage);
    _exitPort = ReceivePort();
    _exitSub = _exitPort!.listen(_onWorkerExit);

    _worker = await Isolate.spawn(
      _catVodWorkerMain,
      <String, dynamic>{
        'port': _responsePort!.sendPort,
        'libraryPath': libraryPath,
        'catLibRoot': catLibRoot,
        'syncBridgePort': _syncBridge!.port,
      },
      debugName: 'qjs-catvod-worker',
      errorsAreFatal: false,
      onExit: _exitPort!.sendPort,
      onError: _exitPort!.sendPort,
    );

    try {
      await _waitForWorkerReady().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('QJS CatVod worker 启动超时'),
      );
    } catch (_) {
      _readyCompleter = null;
      _worker?.kill(priority: Isolate.immediate);
      _worker = null;
      rethrow;
    }
  }

  Completer<void>? _readyCompleter;

  Future<void> _waitForWorkerReady() {
    if (_workerReady) return Future<void>.value();
    _readyCompleter ??= Completer<void>();
    return _readyCompleter!.future;
  }

  void _onWorkerMessage(dynamic message) {
    if (message is! Map) return;
    final type = message['type']?.toString();
    if (type == 'ready') {
      _commandPort = message['port'] as SendPort?;
      _workerReady = _commandPort != null;
      if (_workerReady) {
        _readyCompleter?.complete();
      } else {
        _readyCompleter?.completeError(
          StateError('QJS CatVod worker did not provide a command port'),
        );
      }
      _readyCompleter = null;
      return;
    }
    if (type == 'initError') {
      final error = StateError(
        'QJS CatVod worker 初始化失败: ${message['error']}',
      );
      _readyCompleter?.completeError(error);
      _readyCompleter = null;
      return;
    }
    if (type == 'hostCall') {
      unawaited(_handleHostCall(message));
      return;
    }
    if (type == 'log') {
      return;
    }
    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (message['ok'] == true) {
      completer.complete(message['result']);
    } else {
      completer.completeError(
        StateError(message['error']?.toString() ?? 'QJS CatVod worker error'),
      );
    }
  }

  Future<void> _handleHostCall(Map<dynamic, dynamic> message) async {
    final id = message['id'];
    final commandPort = _commandPort;
    if (id is! int || commandPort == null) return;
    try {
      final args = (message['args'] as List?) ?? const [];
      final kind = message['kind']?.toString() ?? '';
      dynamic result;
      switch (kind) {
        case 'localGet':
          if (args.length >= 2) {
            result = GStorage.setting.get('cat_${args[0]}_${args[1]}');
          }
          break;
        case 'localSet':
          if (args.length >= 3) {
            await GStorage.setting.put(
              'cat_${args[0]}_${args[1]}',
              args[2],
            );
          }
          break;
        case 'localDelete':
          if (args.length >= 2) {
            await GStorage.setting.delete('cat_${args[0]}_${args[1]}');
          }
          break;
        default:
          throw StateError('Unknown QJS CatVod host call: $kind');
      }
      commandPort.send({
        'type': 'hostResult',
        'id': id,
        'ok': true,
        'result': result,
      });
    } catch (error) {
      commandPort.send({
        'type': 'hostResult',
        'id': id,
        'ok': false,
        'error': error.toString(),
      });
    }
  }

  void _onWorkerExit(dynamic message) {
    _workerReady = false;
    _sourceLoaded = false;
    _initializing = null;
    _worker = null;
    _commandPort = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('QJS CatVod worker exited: $message'),
        );
      }
    }
    _pending.clear();
    _responseSub?.cancel();
    _exitSub?.cancel();
    _responsePort?.close();
    _exitPort?.close();
    _responseSub = null;
    _exitSub = null;
    _responsePort = null;
    _exitPort = null;
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(
        StateError('QJS CatVod worker exited: $message'),
      );
    }
    _readyCompleter = null;
  }

  Future<void> _startSyncBridge() async {
    if (_syncBridge != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _syncBridge = server;
    server.listen(_handleSyncRequest);
  }

  Future<void> _handleSyncRequest(HttpRequest request) async {
    if (request.method != 'POST' || request.uri.path != '/sync-fetch') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    Map<String, Object?> result;
    try {
      final raw = await utf8.decoder.bind(request).join();
      final payload = (jsonDecode(raw) as Map).cast<String, dynamic>();
      result = await _performFetch(_dio, payload);
    } catch (error) {
      result = _errorFetchResponse(error);
    }

    final bytes = utf8.encode(jsonEncode(result));
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.contentLength = bytes.length
      ..headers.set(HttpHeaders.connectionHeader, 'close')
      ..add(bytes);
    await request.response.close();
  }

  void _checkQjsPlugin() {
    if (_libraryPathOverride == null) {
      final error = QjsPlatformHelper.checkPluginUsable();
      if (error != null) throw BusinessException(error);
    }
    if (_catLibRootOverride != null) return;
    final catLib = InstallManager.instance.findInstalled('catlib');
    if (catLib == null) {
      throw const BusinessException(
        '未安装 CatLib 引擎库，请前往「插件中心 → 市场」安装 catLib 后重试',
      );
    }
    if (!catLib.enabled) {
      throw const BusinessException('CatLib 引擎库已关闭，请在插件中心开启后重试');
    }
  }

  String? checkPluginUsable() {
    try {
      _checkQjsPlugin();
      return null;
    } on BusinessException catch (error) {
      return error.message;
    } catch (error) {
      return error.toString();
    }
  }

  Future<dynamic> _send(
    String method, [
    List<Object?> args = const [],
    Duration timeout = const Duration(seconds: 90),
  ]) async {
    _checkQjsPlugin();
    if (!_workerReady) await initialize();
    _checkQjsPlugin();
    final port = _commandPort;
    if (port == null) throw StateError('QJS CatVod worker 未就绪');

    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    port.send({
      'type': 'command',
      'id': id,
      'method': method,
      'args': args,
    });
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('QJS CatVod $method 超时');
      },
    );
  }

  Future<void> setGlobalProperty(String name, Object? value) async {
    _globalProperties[name] = value;
    await _send('setGlobal', [name, value], const Duration(seconds: 20));
  }

  Future<Map<String, String>> loadSourceFile(String path) async {
    final result = await _send('loadSource', [
      path,
      'qjs_catvod_probe',
      null,
    ]);
    return _asStringMap(result);
  }

  Future<String> _resolveCatLibRoot() async {
    final dataRoot = await PluginPaths.dataRoot();
    final plugin = InstallManager.instance.findInstalled('catlib');
    if (plugin == null) {
      throw const BusinessException(
        '未安装 CatLib 引擎库，请前往「插件中心 → 市场」安装 catLib 后重试',
      );
    }
    if (!plugin.enabled) {
      throw const BusinessException('CatLib 引擎库已关闭，请在插件中心开启后重试');
    }
    final candidates = <String>[
      p.join(dataRoot.path, 'catLib'),
      p.join(dataRoot.path, 'sources', 'catLib'),
      p.join(dataRoot.path, 'payload', 'catLib'),
      p.join(plugin.installPath, 'catLib'),
      p.join(plugin.installPath, 'payload', 'catLib'),
    ];
    for (final candidate in candidates) {
      if (File(p.join(candidate, 'cat.js')).existsSync()) return candidate;
    }
    throw const BusinessException(
      'CatLib 引擎库文件不完整：未找到 cat.js，请重新安装 catLib 后重试',
    );
  }

  @override
  void setBaseUrl(String url) {}

  @override
  Future<void> switchSite(String apiUrl, String siteKey, {dynamic ext}) async {
    final nextExt = _decodeExt(ext);
    _sourceLoaded = false;
    await _send('loadSource', [apiUrl, siteKey, ext]);
    _currentKey = siteKey;
    _currentExt = nextExt;
    _sourceLoaded = true;
  }

  Future<SiteSwitchResult> switchSiteSafe(
    String apiUrl,
    String siteKey, {
    dynamic ext,
  }) async {
    try {
      await switchSite(apiUrl, siteKey, ext: ext);
      return SiteSwitchResult.success(siteKey: siteKey);
    } catch (error) {
      return SiteSwitchResult.failure(error.toString(), siteKey: siteKey);
    }
  }

  Future<Map<String, dynamic>> call(
    String method, [
    List<Object?> args = const [],
  ]) async {
    final value = await _send('call', [method, args]);
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return {'error': 'Unexpected CatVod result: $value'};
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) {
    return call('home', [filter]);
  }

  @override
  Future<Map<String, dynamic>> fetchCate(
    String cateId,
    int page, {
    String? ext,
  }) {
    final extend = Map<String, dynamic>.from(_currentExt);
    if (ext != null && ext.isNotEmpty) {
      try {
        var decoded = ext;
        try {
          decoded = utf8.decode(base64Decode(ext));
        } catch (_) {}
        final parsed = jsonDecode(decoded);
        if (parsed is Map) extend.addAll(parsed.cast<String, dynamic>());
      } catch (_) {}
    }
    return call('category', [cateId, page, null, extend]);
  }

  @override
  Future<Map<String, dynamic>> search(
    String wd,
    int page, {
    int quick = 0,
  }) {
    return call('search', [wd, quick, page]);
  }

  @override
  Future<VideoDetail?> getDetail({
    required String vodId,
    required String pwd,
  }) async {
    final map = await call('detail', [vodId]);
    final list = map['list'];
    if (list is! List || list.isEmpty || list.first is! Map) return null;
    final data = (list.first as Map).cast<String, dynamic>();
    try {
      return VideoDetail.fromJson(data);
    } catch (_) {
      return VideoDetail(
        vodId: data['vod_id']?.toString() ?? vodId,
        vodName: data['vod_name']?.toString() ?? '未命名',
        vodPic: data['vod_pic']?.toString() ?? '',
        vodContent: data['vod_content']?.toString(),
        playSources: _parsePlaySources(data),
      );
    }
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) {
    return call('detail', [ids]);
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    final map = await call('play', [flag, playParams, []]);
    // CatVod 的 play 结果可能直接返回对象，也可能包在 data 中。
    final data = _normalizePlayData(_extractPlayData(map));
    if (data.containsKey('error') ||
        (!data.containsKey('parse') &&
            !data.containsKey('url') &&
            !data.containsKey('urls'))) {
      return null;
    }
    try {
      final playUrl = PlayUrl.fromJson(data);
      final url = playUrl.defaultUrl?.trim() ?? '';
      return url.isEmpty ? null : playUrl;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) async {
    final map = await call('play', [flag ?? '', play, []]);
    return _normalizePlayData(_extractPlayData(map));
  }

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) {
    return search(wd, page, quick: quick);
  }

  List<PlaySource> _parsePlaySources(Map<String, dynamic> map) {
    final from = map['vod_play_from']?.toString() ?? '';
    final urls = map['vod_play_url']?.toString() ?? '';
    if (from.isEmpty || urls.isEmpty) return const [];
    final fromList = from.split(r'$$$');
    final urlList = urls.split(r'$$$');
    final sources = <PlaySource>[];
    for (var i = 0; i < fromList.length && i < urlList.length; i++) {
      final episodes = <Episode>[];
      for (final part in urlList[i].split('#')) {
        final fields = part.split(r'$');
        if (fields.length >= 2 && fields[1].trim().isNotEmpty) {
          episodes.add(Episode(name: fields[0], url: fields[1]));
        }
      }
      if (episodes.isNotEmpty) {
        sources.add(PlaySource(name: fromList[i], episodes: episodes));
      }
    }
    return sources;
  }

  Map<String, dynamic> _decodeExt(dynamic ext) {
    if (ext is Map) return ext.cast<String, dynamic>();
    if (ext is String && ext.trim().isNotEmpty) {
      try {
        var text = ext;
        try {
          text = utf8.decode(base64Decode(ext));
        } catch (_) {}
        final decoded = jsonDecode(text);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return {};
  }

  Map<String, String> _asStringMap(dynamic value) {
    if (value is! Map) return const {};
    return value.map((key, value) => MapEntry('$key', '$value'));
  }

  Map<String, dynamic> _extractPlayData(Map<String, dynamic> result) {
    dynamic data = result['data'];
    if (data is String && data.trim().isNotEmpty) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }
    if (data is Map) return data.cast<String, dynamic>();
    return result;
  }

  Map<String, dynamic> _normalizePlayData(Map<String, dynamic> data) {
    // 不同 CatVod 源可能把 parse/jx 返回为 bool、数字或字符串。
    final normalized = Map<String, dynamic>.from(data);
    for (final key in const ['parse', 'jx', 'isDash', 'is_dash', 'dash']) {
      final value = normalized[key];
      if (value is bool) {
        normalized[key] = value ? 1 : 0;
      } else if (value is num) {
        normalized[key] = value.toInt();
      } else if (value is String) {
        final text = value.trim().toLowerCase();
        if (text == 'true') {
          normalized[key] = 1;
        } else if (text == 'false') {
          normalized[key] = 0;
        } else {
          normalized[key] = int.tryParse(text);
        }
      }
    }
    final header = normalized['header'] ?? normalized['headers'];
    if (header is Map) {
      normalized['header'] = header.map(
        (key, value) => MapEntry(
          key.toString(),
          value is List ? value.join(', ') : '$value',
        ),
      );
    }
    return normalized;
  }

  Future<void> close() async {
    final worker = _worker;
    final commandPort = _commandPort;
    if (commandPort != null) {
      try {
        commandPort.send({
          'type': 'command',
          'id': -1,
          'method': 'dispose',
          'args': const [],
        });
        await Future<void>.delayed(const Duration(milliseconds: 80));
      } catch (_) {}
    }
    worker?.kill(priority: Isolate.immediate);
    await _syncBridge?.close(force: true);
    _syncBridge = null;
    _onWorkerExit('closed');
    _initializing = null;
    _currentKey = null;
    _currentExt = {};
    _sourceLoaded = false;
  }

  void dispose() {
    unawaited(close());
  }
}

class _CatVodModuleLoader implements JsModuleLoader {
  _CatVodModuleLoader(this.catLibRoot);

  final String catLibRoot;
  final Map<String, String> remoteModules = {};
  final Map<String, String> localModules = {};
  final Map<String, String> inlineModules = {};

  @override
  Uint8List? getModuleBytecode(String moduleName) => null;

  @override
  String? getModuleSource(String moduleName) {
    final name = normalizeName('', moduleName);
    if (name.startsWith('assets://js/lib/')) {
      final relative = name.substring('assets://js/lib/'.length);
      final file = File(
        p.join(catLibRoot, relative.replaceAll('/', p.separator)),
      );
      return file.existsSync() ? file.readAsStringSync() : null;
    }
    final cached =
        remoteModules[name] ?? localModules[name] ?? inlineModules[name];
    if (cached != null) return cached;
    final uri = Uri.tryParse(name);
    if (uri != null && uri.scheme == 'file') {
      final file = File.fromUri(uri);
      return file.existsSync() ? file.readAsStringSync() : null;
    }
    final file = File(name);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  String normalizeName(String moduleBaseName, String moduleName) {
    final name = moduleName.trim();
    if (name.startsWith('assets://') ||
        name.startsWith('file://') ||
        name.startsWith('http://') ||
        name.startsWith('https://') ||
        name.startsWith('inline://') ||
        name.startsWith('data:')) {
      return name;
    }
    if (moduleBaseName.startsWith('assets://') ||
        moduleBaseName.startsWith('file://') ||
        moduleBaseName.startsWith('http://') ||
        moduleBaseName.startsWith('https://') ||
        moduleBaseName.startsWith('inline://')) {
      return Uri.parse(moduleBaseName).resolve(name).toString();
    }
    if (moduleBaseName.isNotEmpty) {
      return p.normalize(p.join(File(moduleBaseName).parent.path, name));
    }
    return name;
  }
}

Future<void> _catVodWorkerMain(Map<String, dynamic> init) async {
  final parentPort = init['port'] as SendPort;
  final commandPort = ReceivePort();
  final worker = _QjsCatVodWorker(
    parentPort: parentPort,
    libraryPath: init['libraryPath'] as String,
    catLibRoot: init['catLibRoot'] as String,
    syncBridgePort: init['syncBridgePort'] as int,
  );
  commandPort.listen(worker.handleMessage);
  try {
    await worker.initialize();
    parentPort.send({
      'type': 'ready',
      'port': commandPort.sendPort,
    });
  } catch (error, stackTrace) {
    parentPort.send({
      'type': 'initError',
      'error': error.toString(),
      'stack': stackTrace.toString(),
    });
    commandPort.close();
  }
}

class _QjsCatVodWorker {
  _QjsCatVodWorker({
    required this.parentPort,
    required this.libraryPath,
    required this.catLibRoot,
    required this.syncBridgePort,
  });

  final SendPort parentPort;
  final String libraryPath;
  final String catLibRoot;
  final int syncBridgePort;

  QuickjsEngine? _engine;
  _CatVodModuleLoader? _loader;
  Dio? _dio;
  // CatVod 源通过 getProxy() 返回的播放地址会落到此 worker 本地代理。
  HttpServer? _proxyServer;
  int _proxyPort = 0;
  final Map<String, Object?> _globalProperties = {};
  final Map<int, Completer<dynamic>> _hostPending = {};

  String? _currentKey;
  dynamic _currentInitExt = '';
  Map<String, String> _methodMap = const {};
  bool _broken = false;
  int _nextHostId = 1;
  Future<void> _operationChain = Future<void>.value();

  void handleMessage(dynamic message) {
    if (message is! Map) return;
    final type = message['type']?.toString();
    if (type == 'hostResult') {
      final id = message['id'];
      if (id is! int) return;
      final completer = _hostPending.remove(id);
      if (completer == null || completer.isCompleted) return;
      if (message['ok'] == true) {
        completer.complete(message['result']);
      } else {
        completer.completeError(
          StateError(message['error']?.toString() ?? 'Host call failed'),
        );
      }
      return;
    }
    if (type != 'command') return;
    unawaited(_handleCommand(message));
  }

  Future<void> initialize() async {
    _dio = _createCatVodDio();
    // 代理端口先就绪，再创建引擎并注入 getProxyUrl。
    await _startProxyServer();
    await _createEngine();
  }

  Future<void> _handleCommand(Map<dynamic, dynamic> message) async {
    final id = message['id'];
    final method = message['method']?.toString() ?? '';
    if (id is! int) return;
    if (method == 'dispose') {
      _disposeEngine();
      await _disposeProxyServer();
      parentPort.send({'id': id, 'ok': true, 'result': null});
      return;
    }

    dynamic result;
    Object? error;
    try {
      await _serial(() async {
        final args = (message['args'] as List?) ?? const [];
        switch (method) {
          case 'loadSource':
            result = await _loadSource(
              args.isNotEmpty ? args[0]?.toString() ?? '' : '',
              args.length > 1 ? args[1]?.toString() ?? '' : '',
              args.length > 2 ? args[2] : null,
            );
          case 'call':
            result = await _call(
              args.isNotEmpty ? args[0]?.toString() ?? '' : '',
              args.length > 1 && args[1] is List
                  ? List<Object?>.from(args[1] as List)
                  : const [],
            );
          case 'setGlobal':
            final name = args.isNotEmpty ? args[0]?.toString() ?? '' : '';
            if (name.isEmpty) throw StateError('Global name is empty');
            final value = args.length > 1 ? args[1] : null;
            _globalProperties[name] = value;
            _engine!.setGlobalProperty(name, value);
            result = null;
          default:
            throw StateError('Unknown QJS CatVod command: $method');
        }
      });
    } catch (caught) {
      error = caught;
    }

    if (error == null) {
      parentPort.send({'id': id, 'ok': true, 'result': result});
    } else {
      parentPort.send({'id': id, 'ok': false, 'error': error.toString()});
    }
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _operationChain;
    final completer = Completer<T>();
    _operationChain = () async {
      try {
        await previous;
      } catch (_) {}
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  Future<void> _createEngine() async {
    final engine = QuickjsEngine.createWith(
      const JsEngineConfig(
        stackSize: 1024 * 1024,
        memoryLimit: 256 * 1024 * 1024,
        timeoutMs: 60 * 1000,
      ),
      libPath: libraryPath,
    );
    final loader = _CatVodModuleLoader(catLibRoot);
    engine.setConsoleSink((message) {
      parentPort.send({'type': 'log', 'message': message});
    });
    engine.setModuleLoader(loader);
    engine.installTimers();
    engine.setGlobalProperty(
      '__qjsCatProxyUrl',
      'http://127.0.0.1:$_proxyPort/proxy?do=js',
    );
    engine.registerFunction('__qjsCatHttpSync', (args) {
      return _syncFetch(
        syncBridgePort,
        args.isNotEmpty ? args.first : null,
      );
    });
    engine.registerAsyncFunction('__qjsCatHttp', (args) {
      return _asyncFetch(args.isNotEmpty ? args.first : null);
    });
    engine.registerAsyncFunction('__qjsCatLocalGet', (args) {
      return _hostCall('localGet', args);
    });
    engine.registerAsyncFunction('__qjsCatLocalSet', (args) {
      return _hostCall('localSet', args);
    });
    engine.registerAsyncFunction('__qjsCatLocalDelete', (args) {
      return _hostCall('localDelete', args);
    });
    await engine.evaluateAsync(r'''
      globalThis.window = globalThis;
      globalThis.print = function() {
        console.log.apply(console, arguments);
      };
      globalThis.log = globalThis.print;
      globalThis.getProxyUrl = async function() {
        return globalThis.__qjsCatProxyUrl;
      };
      globalThis.getProxy = globalThis.getProxyUrl;
      globalThis.js2Proxy = async function() {
        return globalThis.__qjsCatProxyUrl;
      };
      globalThis.__qjsCatNormalizeResponse = function(value) {
        if (value && value.buffer === 1 && typeof value.content === 'string') {
          const binary = atob(value.content);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
          }
          value.content = bytes;
        }
        return value;
      };
      globalThis._http = function(url, options) {
        const opts = options || {};
        const payload = JSON.stringify({
          url: String(url),
          options: {
            method: opts.method || 'GET',
            headers: opts.headers || {},
            body: opts.body ?? null,
            data: opts.data ?? null,
            buffer: opts.buffer ?? null,
          },
        });
        if (opts.async === false) {
          const value = __qjsCatNormalizeResponse(__qjsCatHttpSync(payload));
          if (typeof opts.complete === 'function') opts.complete(value);
          return value;
        }
        const result = Promise.resolve(__qjsCatHttp(payload)).then(
          globalThis.__qjsCatNormalizeResponse,
        );
        if (typeof opts.complete === 'function') {
          result.then(value => opts.complete(value));
        }
        return result;
      };
      globalThis.http = globalThis._http;
      globalThis.req = function(url, options) {
        return globalThis._http(
          url,
          Object.assign({ async: false }, options || {}),
        );
      };
      globalThis.local = {
        get: async function(scope, key) {
          return await __qjsCatLocalGet(String(scope), String(key));
        },
        set: async function(scope, key, value) {
          return await __qjsCatLocalSet(String(scope), String(key), value);
        },
        delete: async function(scope, key) {
          return await __qjsCatLocalDelete(String(scope), String(key));
        },
      };
      globalThis.BaseSpider = class BaseSpider {
        constructor() {}
        async fetch(url, options = {}, headers = {}) {
          const reqOptions = {
            method: options.method || 'GET',
            headers: headers || {},
            body: options.body || null,
            timeout: options.timeout || 15000,
          };
          if (
            reqOptions.method === 'POST' &&
            reqOptions.body &&
            typeof reqOptions.body === 'object'
          ) {
            reqOptions.body = JSON.stringify(reqOptions.body);
            reqOptions.headers['Content-Type'] = 'application/json';
          }
          const response = await globalThis.req(url, reqOptions);
          let data;
          try {
            data = JSON.parse(response.content);
          } catch (_) {
            data = { content: response.content };
          }
          return { data };
        }
        formatCount(num) {
          if (num > 1e8) return (num / 1e8).toFixed(2) + '亿';
          if (num > 1e4) return (num / 1e4).toFixed(2) + '万';
          return String(num);
        }
        getSafe(obj, path, defaultValue = '') {
          if (!obj || typeof obj !== 'object') return defaultValue;
          try {
            return path.split('.').reduce((value, key) => {
              if (value == null) return defaultValue;
              return value[key];
            }, obj) ?? defaultValue;
          } catch (_) {
            return defaultValue;
          }
        }
      };
    ''');
    await engine.evaluateAsync(qjsCatVodHtmlParserJs);
    for (final entry in _globalProperties.entries) {
      engine.setGlobalProperty(entry.key, entry.value);
    }
    _engine = engine;
    _loader = loader;
    _broken = false;
  }

  Future<void> _resetEngine() async {
    _disposeEngine();
    await _createEngine();
  }

  void _disposeEngine() {
    try {
      _engine?.dispose();
    } catch (_) {}
    _engine = null;
    _loader = null;
    _methodMap = const {};
  }

  Future<void> _startProxyServer() async {
    if (_proxyServer != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _proxyServer = server;
    _proxyPort = server.port;
    server.listen(_handleProxyRequest);
  }

  Future<void> _handleProxyRequest(HttpRequest request) async {
    if (request.uri.path != '/proxy') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final params = Map<String, String>.from(request.uri.queryParameters);
      final result = await _serial(() => _callProxy(params));
      await _writeProxyResult(request, result);
    } catch (error) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('CatVod proxy failed: $error');
      } finally {
        await request.response.close();
      }
    }
  }

  Future<List<dynamic>> _callProxy(Map<String, String> params) async {
    if (_engine == null ||
        _currentKey == null ||
        !_methodMap.containsKey('proxy')) {
      return [HttpStatus.notFound, 'text/plain', 'proxy method unavailable'];
    }
    try {
      // 标准 CatVod proxy 返回 [status, contentType, body, headers, flag]。
      dynamic result = await _invokeRaw('proxy', [params]);
      if (result is String) result = jsonDecode(result);
      if (result is Map && result['error'] != null) {
        return [
          HttpStatus.internalServerError,
          'text/plain',
          result['error'].toString(),
        ];
      }
      if (result is List) {
        return List<dynamic>.from(result);
      }
      return [
        HttpStatus.internalServerError,
        'text/plain',
        'invalid proxy result',
      ];
    } catch (error) {
      return [
        HttpStatus.internalServerError,
        'text/plain',
        'proxy call failed: $error',
      ];
    }
  }

  Future<void> _writeProxyResult(
    HttpRequest request,
    List<dynamic> result,
  ) async {
    if (result.length < 3) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('invalid proxy result');
      await request.response.close();
      return;
    }
    final status = (result[0] as num?)?.toInt() ?? HttpStatus.notFound;
    final contentType = result[1]?.toString() ?? 'application/octet-stream';
    final content = result[2];
    final extraHeaders = result.length > 3 && result[3] is Map
        ? Map<String, String>.from(
            (result[3] as Map).map(
              (key, value) => MapEntry(
                key.toString(),
                value is List ? value.join(', ') : '$value',
              ),
            ),
          )
        : <String, String>{};
    final toBytes = result.length > 4 ? result[4] : null;

    request.response.statusCode = status;
    try {
      request.response.headers.contentType = ContentType.parse(contentType);
    } catch (_) {
      request.response.headers.contentType = ContentType.binary;
    }
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    for (final entry in extraHeaders.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'content-length' ||
          key == 'transfer-encoding' ||
          key == 'connection') {
        continue;
      }
      request.response.headers.set(entry.key, entry.value);
    }

    if ((toBytes == 1 || toBytes == true) && content is String) {
      // flag=1：body 是 base64，通常用于 TS 解密后的二进制数据。
      try {
        request.response.add(base64Decode(content));
      } catch (_) {
        request.response.statusCode = HttpStatus.internalServerError;
      }
      await request.response.close();
      return;
    }
    if (toBytes == 2 && content is String) {
      // flag=2：body 是重定向地址。
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader, content);
      await request.response.close();
      return;
    }
    if (toBytes == 3 && content is String) {
      // flag=3：body 是上游直链，保留 Range 以支持拖动播放。
      try {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        final response = await _dio!.get<ResponseBody>(
          content,
          options: Options(
            responseType: ResponseType.stream,
            headers: {if (range != null) HttpHeaders.rangeHeader: range},
          ),
        );
        request.response.statusCode = response.statusCode ?? HttpStatus.ok;
        final upstreamType = response.headers.value(
          HttpHeaders.contentTypeHeader,
        );
        if (upstreamType != null && upstreamType.isNotEmpty) {
          try {
            request.response.headers.contentType = ContentType.parse(
              upstreamType,
            );
          } catch (_) {}
        }
        await request.response.addStream(
          (response.data as ResponseBody).stream,
        );
      } catch (_) {
        request.response.statusCode = HttpStatus.badGateway;
      }
      await request.response.close();
      return;
    }

    if (content is Uint8List) {
      request.response.add(content);
    } else if (content is List<int>) {
      request.response.add(content);
    } else {
      request.response.write(content?.toString() ?? '');
    }
    await request.response.close();
  }

  Future<void> _disposeProxyServer() async {
    try {
      await _proxyServer?.close(force: true);
    } catch (_) {}
    _proxyServer = null;
    _proxyPort = 0;
  }

  Future<Map<String, String>> _loadSource(
    String apiUrl,
    String siteKey,
    dynamic ext,
  ) async {
    if (_currentKey != null || _methodMap.isNotEmpty) {
      await _resetEngine();
    }
    _currentKey = siteKey;
    _currentInitExt = ext ?? '';
    _broken = false;
    try {
      final moduleName = await _prepareSource(apiUrl);
      _methodMap = await _loadCatVodApi(moduleName);
      if (_methodMap.containsKey('init')) {
        // 与 drpy-node/catvod.js 对齐：init 后才可调用 getProxy 和业务接口。
        await _invokeRaw('init', [
          <String, Object?>{
            'stype': 4,
            'skey': siteKey,
            'sourceKey': siteKey,
            'ext': _currentInitExt,
          },
        ]);
      }
      return Map.unmodifiable(_methodMap);
    } catch (_) {
      _broken = true;
      rethrow;
    }
  }

  Future<String> _prepareSource(String apiUrl) async {
    if (apiUrl.startsWith('http://') || apiUrl.startsWith('https://')) {
      final source = await _downloadText(apiUrl);
      await _preloadRemoteImports(source, apiUrl);
      _loader!.remoteModules[apiUrl] = source;
      return apiUrl;
    }
    if (apiUrl.startsWith('file://')) {
      final uri = Uri.parse(apiUrl);
      final file = File.fromUri(uri);
      if (!file.existsSync()) {
        throw FileSystemException('CatVod 规则文件不存在', file.path);
      }
      _loader!.localModules[apiUrl] = await file.readAsString();
      return apiUrl;
    }
    final file = File(p.normalize(p.absolute(apiUrl)));
    if (file.existsSync()) {
      final source = await file.readAsString();
      final moduleName = Uri.file(file.path).toString();
      _loader!.localModules[moduleName] = source;
      return moduleName;
    }
    if (apiUrl.contains('\n') || apiUrl.contains('export ')) {
      final moduleName =
          'inline://catvod/${DateTime.now().microsecondsSinceEpoch}.js';
      _loader!.inlineModules[moduleName] = apiUrl;
      return moduleName;
    }
    throw FileSystemException('CatVod 规则文件不存在', apiUrl);
  }

  Future<String> _downloadText(String url) async {
    final response = await _dio!.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    if ((response.statusCode ?? 0) < 200 || (response.statusCode ?? 0) >= 300) {
      throw HttpException(
        '规则下载失败: HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    var text = utf8.decode(response.data ?? const [], allowMalformed: true);
    if (text.startsWith('H4sI')) {
      try {
        text = utf8.decode(
          gzip.decode(base64Decode(text.replaceAll(RegExp(r'\s'), ''))),
          allowMalformed: true,
        );
      } catch (_) {}
    }
    return text;
  }

  Future<void> _preloadRemoteImports(String code, String baseUrl) async {
    final imports = RegExp(
      r'''(?:import\s*(?:[^'"]*?\sfrom\s*)?|export\s*[^'"]*?\sfrom\s*)['"]([^'"]+)['"]''',
      multiLine: true,
    );
    for (final match in imports.allMatches(code)) {
      final specifier = match.group(1);
      if (specifier == null ||
          specifier.startsWith('assets://') ||
          specifier.startsWith('data:')) {
        continue;
      }
      final resolved = Uri.parse(baseUrl).resolve(specifier).toString();
      if (_loader!.remoteModules.containsKey(resolved)) continue;
      final imported = await _downloadText(resolved);
      _loader!.remoteModules[resolved] = imported;
      await _preloadRemoteImports(imported, resolved);
    }
  }

  Future<Map<String, String>> _loadCatVodApi(String moduleName) async {
    final result = await _engine!.evaluateAsync('''
      (async function() {
        const module = await import(${jsonEncode(moduleName)});
        let api = module.default;
        if (typeof api === 'function') {
          try {
            api = api();
          } catch (_) {
            api = new api();
          }
        }
        if (!api && typeof module.__jsEvalReturn === 'function') {
          api = module.__jsEvalReturn();
        }
        if (!api && typeof globalThis.__jsEvalReturn === 'function') {
          api = globalThis.__jsEvalReturn();
        }
        if (!api && typeof globalThis.Spider === 'function') {
          api = new globalThis.Spider();
        }
        if (!api) {
          const candidates = [
            'init', 'home', 'homeContent', 'category', 'categoryContent',
            'detail', 'detailContent', 'play', 'playerContent',
            'search', 'searchContent', 'proxy',
          ];
          if (candidates.some(name => typeof module[name] === 'function')) {
            api = module;
          }
        }
        if (!api || typeof api !== 'object') {
          throw new Error('CatVod source did not export an API object');
        }
        globalThis.__qjsCatApi = api;
        const aliases = {
          init: ['init'],
          home: ['home', 'homeContent'],
          homeVod: ['homeVod', 'homeVodContent'],
          category: ['category', 'categoryContent'],
          detail: ['detail', 'detailContent'],
          play: ['play', 'playerContent'],
          search: ['search', 'searchContent'],
          proxy: ['proxy'],
        };
        const methods = {};
        for (const standard of Object.keys(aliases)) {
          for (const name of aliases[standard]) {
            if (typeof api[name] === 'function') {
              methods[standard] = name;
              break;
            }
          }
        }
        return JSON.stringify(methods);
      })()
    ''');
    if (result is! String) {
      throw StateError('CatVod source method discovery failed');
    }
    final decoded = jsonDecode(result);
    if (decoded is! Map) {
      throw StateError('CatVod source method map is invalid');
    }
    return decoded.map((key, value) => MapEntry('$key', '$value'));
  }

  Future<dynamic> _call(String method, List<Object?> args) async {
    if (_broken) return {'error': 'CatVod rule is not loaded'};
    try {
      final value = await _invokeRaw(method, args);
      if (value == null) return <String, dynamic>{};
      if (value is Map) return value.cast<String, dynamic>();
      if (value is String) {
        final decoded = jsonDecode(value);
        if (decoded is Map) return decoded.cast<String, dynamic>();
        if (decoded is String) {
          final nested = jsonDecode(decoded);
          if (nested is Map) return nested.cast<String, dynamic>();
        }
      }
      return {'error': 'Unexpected CatVod result: $value'};
    } catch (error) {
      return {'error': error.toString()};
    }
  }

  Future<Object?> _invokeRaw(String method, List<Object?> args) async {
    final actual = _methodMap[method];
    if (actual == null) throw StateError('CatVod method unavailable: $method');
    return _engine!.evaluateAsync('''
      (async function() {
        const api = globalThis.__qjsCatApi;
        const fn = api[${jsonEncode(actual)}];
        if (typeof fn !== 'function') {
          throw new Error('method not found: ${actual}');
        }
        const value = await fn.apply(api, ${jsonEncode(args)});
        return value === undefined ? null : value;
      })()
    ''');
  }

  Future<Object?> _hostCall(String kind, List<Object?> args) {
    final id = _nextHostId++;
    final completer = Completer<dynamic>();
    _hostPending[id] = completer;
    parentPort.send({
      'type': 'hostCall',
      'id': id,
      'kind': kind,
      'args': args,
    });
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _hostPending.remove(id);
        throw TimeoutException('QJS CatVod host call timeout: $kind');
      },
    );
  }

  Future<Map<String, Object?>> _asyncFetch(Object? raw) async {
    try {
      final payload = _decodeFetchPayload(raw);
      return await _performFetch(_dio!, payload);
    } catch (error) {
      return _errorFetchResponse(error);
    }
  }
}

Dio _createCatVodDio() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (_) => true,
      responseType: ResponseType.bytes,
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      return HttpClient()
        ..idleTimeout = const Duration(seconds: 15)
        ..autoUncompress = true
        ..badCertificateCallback = (_, __, ___) => true;
    },
  );
  return dio;
}

Map<String, dynamic> _decodeFetchPayload(Object? raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is String && raw.trim().isNotEmpty) {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, dynamic>();
  }
  return {};
}

Future<Map<String, Object?>> _performFetch(
  Dio dio,
  Map<String, dynamic> payload,
) async {
  final url = payload['url']?.toString() ?? '';
  if (url.isEmpty) throw StateError('HTTP URL is empty');
  final options =
      (payload['options'] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};
  final headers = <String, String>{};
  ((options['headers'] as Map?) ?? const {}).forEach((key, value) {
    final headerName = key.toString();
    final lower = headerName.toLowerCase();
    if (lower == 'host' || lower == 'content-length' || lower == 'connection') {
      return;
    }
    headers[headerName] = value is List ? value.join(', ') : value.toString();
  });
  dynamic body = options['body'] ?? options['data'];
  if (body is Map || body is List) {
    if (!headers.keys.any((key) => key.toLowerCase() == 'content-type')) {
      headers['Content-Type'] = 'application/json';
    }
    body = jsonEncode(body);
  }
  final response = await dio.request<List<int>>(
    url,
    data: body,
    options: Options(
      method: (options['method']?.toString() ?? 'GET').toUpperCase(),
      headers: headers,
      responseType: ResponseType.bytes,
      validateStatus: (_) => true,
    ),
  );
  final bytes = response.data ?? const <int>[];
  final bufferType = options['buffer'];
  final content = bufferType == 1 || bufferType == 2
      ? base64Encode(bytes)
      : utf8.decode(bytes, allowMalformed: true);
  return <String, Object?>{
    'content': content,
    'headers': response.headers.map.map(
      (key, value) => MapEntry(key, value.join(',')),
    ),
    'status': response.statusCode ?? 0,
    'statusCode': response.statusCode ?? 0,
    'url': response.realUri.toString(),
    'ok':
        (response.statusCode ?? 500) >= 200 &&
        (response.statusCode ?? 500) < 300,
    if (bufferType != null) 'buffer': bufferType,
  };
}

Map<String, Object?> _errorFetchResponse(Object error) {
  return <String, Object?>{
    'content': '',
    'headers': <String, String>{'error': error.toString()},
    'status': 500,
    'statusCode': 500,
    'ok': false,
  };
}

Object? _syncFetch(int port, Object? raw) {
  final payload = raw is String ? raw : jsonEncode(raw);
  RawSynchronousSocket? socket;
  try {
    socket = RawSynchronousSocket.connectSync(
      InternetAddress.loopbackIPv4,
      port,
    );
    final bytes = utf8.encode(payload);
    socket.writeFromSync(
      utf8.encode(
        'POST /sync-fetch HTTP/1.1\r\n'
        'Host: 127.0.0.1\r\n'
        'Content-Type: application/json; charset=utf-8\r\n'
        'Content-Length: ${bytes.length}\r\n'
        'Connection: close\r\n\r\n',
      ),
    );
    socket.writeFromSync(bytes);
    final response = <int>[];
    final chunk = Uint8List(16384);
    while (true) {
      final count = socket.readIntoSync(chunk);
      if (count <= 0) break;
      response.addAll(chunk.sublist(0, count));
    }
    final text = utf8.decode(response, allowMalformed: true);
    final separator = text.indexOf('\r\n\r\n');
    if (separator < 0) throw StateError('Invalid sync bridge response');
    return jsonDecode(text.substring(separator + 4));
  } catch (error) {
    return _errorFetchResponse(error);
  } finally {
    try {
      socket?.closeSync();
    } catch (_) {}
  }
}
