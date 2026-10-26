// drpy3 专用 Service（qjs_ultra 版，worker isolate 架构）
//
// 设计要点：
// - 主 isolate（UI 线程）只负责 SendPort 通信，不碰引擎、不碰 Dio、不碰 HttpServer
// - worker isolate 内跑完整 drpy3 runtime：QuickJS 引擎、emscripten wasm3 解密、
//   HttpServer 代理、Dio 请求、分片缓存、inflight 去重
// - UI 线程永远不会因为 wasm3 同步解密而阻塞
//
// 已知环境要求：
// - qjs_ultra 引擎内置 console 对象，console.stdout 必须由宿主通过
//   setConsoleSink 注册，否则 emscripten 胶水调用 console 即抛
//   "When invoke console stuff,you should be set a stdout of platform to
//   console.stdout."
// - worker 里 HttpServer.bind 的端口是进程级共享的，主 isolate 播放器可直接访问

import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show File, gzip, HttpServer, HttpRequest, InternetAddress, Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:qjs_ultra/qjs_ultra.dart';

import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/utils/qjs_platform_helper.dart';

// ============================================================
// 主 isolate：只做通信
// ============================================================
class QjsDrpy3Service implements ISpiderService {
  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _responsePort;
  StreamSubscription? _responseSub;
  ReceivePort? _exitPort;
  StreamSubscription? _exitSub;

  final Map<int, Completer<dynamic>> _pending = {};
  int _nextId = 1;

  bool _workerReady = false;
  bool _initInFlight = false;
  Completer<bool>? _readyCompleter;
  final isReady = false.obs;

  String? _currentKey;
  String? _pendingExt;
  String? _pendingApiUrl;
  String? _pendingSiteKey;

  @override
  String? get currentKey => _currentKey;
  bool get isRunning => _workerReady;

  static const _bundleAsset = 'assets/js/lib/drpy3/drpy3-qjs.bundle.js';

  // ============================================================
  // worker 生命周期
  // ============================================================
  Future<bool> _ensureWorker() async {
    if (_workerReady) return true;
    if (_initInFlight) return _readyCompleter!.future;
    _initInFlight = true;
    _readyCompleter = Completer<bool>();

    try {
      if (!QjsPlatformHelper.isSupported) {
        debugPrint('[QjsDrpy3] 当前平台不支持 qjs_ultra');
        _readyCompleter!.complete(false);
        _readyCompleter = null;
        _initInFlight = false;
        return false;
      }
      final libPath = QjsPlatformHelper.libPath;
      final bundleCode = await rootBundle.loadString(_bundleAsset);

      _responsePort = ReceivePort();
      _responseSub = _responsePort!.listen(_onWorkerMessage);
      _exitPort = ReceivePort();
      _exitSub = _exitPort!.listen(_onWorkerExit);

      _isolate = await Isolate.spawn(
        _drpy3WorkerMain,
        <String, dynamic>{
          'mainPort': _responsePort!.sendPort,
          'libPath': libPath,
          'bundleCode': bundleCode,
        },
        debugName: 'drpy3-worker',
        errorsAreFatal: false,
        onExit: _exitPort!.sendPort,
        onError: _exitPort!.sendPort,
      );
    } catch (e, st) {
      debugPrint('[QjsDrpy3] worker 创建失败: $e\n$st');
      _readyCompleter!.complete(false);
      _readyCompleter = null;
      _initInFlight = false;
      return false;
    }
    return _readyCompleter!.future;
  }

  /// 兼容外部显式初始化调用（source_manager 等）。
  /// 语义：确保 worker isolate 已创建且 drpy3 bundle 装载完成。
  Future<bool> ensureInitialized() => _ensureWorker();

  void _onWorkerMessage(dynamic msg) {
    if (msg is! Map) return;
    final type = msg['type'];
    if (type == 'ready') {
      _workerSendPort = msg['port'] as SendPort;
      return;
    }
    if (type == 'initDone') {
      final ok = msg['ok'] == true;
      _initInFlight = false;
      if (ok) {
        _workerReady = true;
        isReady.value = true;
        _readyCompleter?.complete(true);
        _readyCompleter = null;
        unawaited(_applyPending());
      } else {
        _readyCompleter?.complete(false);
        _readyCompleter = null;
      }
      return;
    }
    final id = msg['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (msg.containsKey('error')) {
      completer.completeError(msg['error']);
    } else {
      completer.complete(msg['result']);
    }
  }

  void _onWorkerExit(dynamic msg) {
    debugPrint('[QjsDrpy3] worker 退出/异常: $msg');
    _workerReady = false;
    isReady.value = false;
    _workerSendPort = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError('worker exited: $msg');
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
    _isolate = null;
    _initInFlight = false;
    _readyCompleter?.complete(false);
    _readyCompleter = null;
  }

  Future<void> _applyPending() async {
    if (_pendingApiUrl == null || _pendingSiteKey == null) return;
    final apiUrl = _pendingApiUrl!;
    final siteKey = _pendingSiteKey!;
    final ext = _pendingExt;
    _pendingApiUrl = null;
    _pendingSiteKey = null;
    _pendingExt = null;
    try {
      await _call('loadSource', [apiUrl, siteKey, ext]);
    } catch (e) {
      debugPrint('[QjsDrpy3] 延迟 loadSource 失败: $e');
    }
  }

  Future<dynamic> _call(String method, List<dynamic> args,
      {Duration? timeout}) async {
    if (!await _ensureWorker()) {
      throw StateError('worker not ready');
    }
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _workerSendPort!.send({'id': id, 'method': method, 'args': args});
    return completer.future.timeout(
      timeout ?? const Duration(seconds: 180),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('worker $method timeout');
      },
    );
  }

  Map<String, dynamic> _asMap(dynamic r) {
    if (r == null) return {};
    if (r is Map) return r.cast<String, dynamic>();
    return {'success': false, 'error': 'unexpected: $r'};
  }

  // ============================================================
  // ISpiderService
  // ============================================================
  @override
  void setBaseUrl(String url) {}

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    _currentKey = siteKey;
    _pendingExt = ext is String ? ext : (ext?.toString() ?? '');
    if (!_workerReady) {
      _pendingApiUrl = apiUrl;
      _pendingSiteKey = siteKey;
      unawaited(_ensureWorker());
      return;
    }
    unawaited(_call('loadSource', [apiUrl, siteKey, _pendingExt]));
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    return _asMap(await _call('fetchHome', [filter]));
  }

  @override
  Future<Map<String, dynamic>> fetchCate(String cateId, int page,
      {String? ext}) async {
    return _asMap(await _call('fetchCate', [cateId, page, ext]));
  }

  @override
  Future<Map<String, dynamic>> search(String wd, int page,
      {int quick = 0}) async {
    return _asMap(await _call('search', [wd, page, quick]));
  }

  @override
  Future<VideoDetail?> getDetail(
      {required String vodId, required String pwd}) async {
    final map = _asMap(await _call('getDetail', [vodId, pwd]));
    final list = map['list'];
    if (list is! List || list.isEmpty) return null;
    final data = (list[0] as Map).cast<String, dynamic>();
    return VideoDetail(
      vodId: data['vod_id']?.toString() ?? vodId,
      vodName: data['vod_name']?.toString() ?? '未命名',
      vodPic: data['vod_pic']?.toString() ?? '',
      vodContent: data['vod_content']?.toString(),
      playSources: _parsePlaySources(data),
    );
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    return _asMap(await _call('fetchDetail', [ids]));
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    final map = _asMap(await _call('getPlayUrl', [playParams, flag, pwd]));
    if (map['data'] is Map) {
      return PlayUrl.fromJson((map['data'] as Map).cast<String, dynamic>());
    }
    if (map['parse'] != null || map['url'] != null || map['urls'] != null) {
      return PlayUrl.fromJson(map);
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play,
      {String? flag}) async {
    return _asMap(await _call('fetchPlayUrl', [play, flag]));
  }

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) =>
      search(wd, page, quick: quick);

  List<PlaySource> _parsePlaySources(Map<String, dynamic> map) {
    final from = map['vod_play_from']?.toString() ?? '';
    final url = map['vod_play_url']?.toString() ?? '';
    if (from.isEmpty || url.isEmpty) return [];
    final fromList = from.split(r'$$$');
    final urlList = url.split(r'$$$');
    final out = <PlaySource>[];
    for (var i = 0; i < fromList.length && i < urlList.length; i++) {
      final eps = <Episode>[];
      for (final part in urlList[i].split('#')) {
        if (part.trim().isEmpty) continue;
        final kv = part.split(r'$');
        if (kv.length == 2) eps.add(Episode(name: kv[0], url: kv[1]));
      }
      if (eps.isNotEmpty) out.add(PlaySource(name: fromList[i], episodes: eps));
    }
    return out;
  }

  void dispose() {
    try {
      _workerSendPort?.send({'id': -1, 'method': 'dispose', 'args': []});
    } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;
    _workerReady = false;
    isReady.value = false;
    _responseSub?.cancel();
    _exitSub?.cancel();
    _responsePort?.close();
    _exitPort?.close();
    _responseSub = null;
    _exitSub = null;
    _responsePort = null;
    _exitPort = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError('disposed');
    }
    _pending.clear();
    _currentKey = null;
    _initInFlight = false;
    _readyCompleter?.complete(false);
    _readyCompleter = null;
  }
}

// ============================================================
// worker isolate 入口
// ============================================================
void _drpy3WorkerMain(Map<String, dynamic> args) {
  final mainPort = args['mainPort'] as SendPort;
  final libPath = args['libPath'] as String;
  final bundleCode = args['bundleCode'] as String;

  final receivePort = ReceivePort();
  receivePort.listen((msg) async {
    if (msg is! Map) return;
    final method = msg['method'] as String?;
    final id = msg['id'] as int?;
    if (method == 'dispose') {
      try {
        await _workerImpl?.dispose();
      } catch (_) {}
      Isolate.exit();
      return;
    }
    if (id == null || method == null) return;
    final callArgs = (msg['args'] as List?) ?? const [];
    try {
      final result = await _workerImpl!.handle(method, callArgs);
      mainPort.send({'id': id, 'result': result});
    } catch (e, st) {
      mainPort.send({'id': id, 'error': '$e\n$st'});
    }
  });

  mainPort.send({'type': 'ready', 'port': receivePort.sendPort});

  _workerImpl = _Drpy3WorkerImpl(libPath: libPath, bundleCode: bundleCode);
  _workerImpl!.init().then((ok) {
    mainPort.send({'type': 'initDone', 'ok': ok});
  });
}

_Drpy3WorkerImpl? _workerImpl;

// ============================================================
// worker 内的 drpy3 runtime 实现
// ============================================================
class _Drpy3WorkerImpl {
  _Drpy3WorkerImpl({required this.libPath, required this.bundleCode});

  final String libPath;
  final String bundleCode;

  QuickjsEngine? _engine;
  HttpServer? _proxyServer;
  int _proxyPort = 0;

  String? _currentKey;
  String? _currentSourceBase;
  int _siteVersion = 0;
  Completer<void>? _siteReady;

  final Map<String, Uint8List> _assetCache = {};
  final Map<String, Uint8List> _segmentCache = {};
  final Map<String, Future<List<dynamic>>> _segmentInflight = {};
  static const int _maxSegmentCache = 50;

  final Completer<bool> _initDone = Completer<bool>();
  Future<void> _callChain = Future<void>.value();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    validateStatus: (_) => true,
    responseType: ResponseType.bytes,
  ));

  // ============================================================
  // init
  // ============================================================
  Future<bool> init() async {
    try {
      _engine = QuickjsEngine.createWith(
        const JsEngineConfig(
          stackSize: 1 * 1024 * 1024,
          memoryLimit: 256 * 1024 * 1024,
          timeoutMs: 120 * 1000,
        ),
        libPath: libPath,
      );
      // console.stdout 必须注册：emscripten 胶水顶层即调用 console，
      // 未注册时抛 "When invoke console stuff,..."。这里顺带过滤掉
      // 胶水内部的 [GTRACE] 调试轨迹，只保留 Woker_BTime 等关键标志。
      _engine!.setConsoleSink((m) {
        if (m.contains('[GTRACE]')) return;
        print('[drpy3-worker][console] $m');
      });

      await _startProxyServer();
      _engine!.installDrpy3Shim(_handleBridge);

      await _engine!.loadModuleToGlobals('drpy3-qjs.bundle.js', bundleCode);
      await _engine!.callAsync('__drpy3Setup', [
        jsonEncode({'engine': 'qjs_ultra', 'action': true}),
      ]);
      _initDone.complete(true);
      return true;
    } catch (e, st) {
      print('[drpy3-worker] init 失败: $e\n$st');
      _initDone.complete(false);
      return false;
    }
  }

  Future<dynamic> handle(String method, List args) {
    return _serial(() async {
      if (!await _initDone.future) {
        throw StateError('engine init failed');
      }
      return _dispatch(method, args);
    });
  }

  Future<T> _serial<T>(Future<T> Function() fn) {
    final prev = _callChain;
    final completer = Completer<T>();
    _callChain = () async {
      try {
        await prev;
      } catch (_) {}
      try {
        completer.complete(await fn());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }();
    return completer.future;
  }

  Future<dynamic> _dispatch(String method, List args) async {
    switch (method) {
      case 'loadSource':
        return await _loadSource(
          args[0] as String,
          args[1] as String,
          ext: args.length > 2 ? args[2] : null,
        );
      case 'fetchHome':
        return await _callSource('home', [args.isNotEmpty ? args[0] : 1]);
      case 'fetchCate':
        return await _callSource('category', [args[0], args[1], false, {}]);
      case 'search':
        return await _callSource('search', [args[0], args[2] == 1, args[1]]);
      case 'getDetail':
        return await _callSource('detail', [args[0]]);
      case 'fetchDetail':
        return await _callSource('detail', [args[0]]);
      case 'getPlayUrl':
        return await _callSource('play', [args[1], args[0], []]);
      case 'fetchPlayUrl':
        return await _callSource(
            'play', [args.length > 1 ? args[1] ?? '' : '', args[0], []]);
      default:
        throw ArgumentError('unknown method: $method');
    }
  }

  Future<void> dispose() async {
    try {
      _proxyServer?.close(force: true);
    } catch (_) {}
    _proxyServer = null;
    try {
      _engine?.dispose();
    } catch (_) {}
    _engine = null;
    _segmentCache.clear();
    _segmentInflight.clear();
    _assetCache.clear();
  }

  // ============================================================
  // proxy server
  // ============================================================
  Future<void> _startProxyServer() async {
    if (_proxyServer != null) return;
    _proxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _proxyPort = _proxyServer!.port;
    print('[drpy3-worker] proxy 监听 127.0.0.1:$_proxyPort');
    _proxyServer!.listen(_handleProxyRequest);
  }

  Future<void> _handleProxyRequest(HttpRequest req) async {
    try {
      if (req.uri.path != '/proxy') {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final params = req.uri.queryParameters;
      final target = params['url'] ?? '';
      final isTs = target.split('?').first.endsWith('.ts');
      final isM3u8 = target.split('?').first.endsWith('.m3u8');
      // TS 的成功日志统一在 _proxyWithCache 里输出，这里只记录非 TS
      if (!isTs) {
        print('[drpy3-worker][proxy] << ${isM3u8 ? 'm3u8' : 'other'} '
            '${_shortName(target)}');
      }
      final result = await _proxyWithCache(params);
      await _writeProxyResult(req, result);
    } catch (e, st) {
      print('[drpy3-worker][proxy] 异常: $e\n$st');
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<List<dynamic>> _proxyWithCache(Map<String, String> params) {
    final url = params['url'] ?? '';
    if (!url.split('?').first.endsWith('.ts')) {
      return _callJsProxy(params);
    }
    final name = _shortName(url);

    final cached = _segmentCache[url];
    if (cached != null) {
      print('[drpy3-worker][ts] $name 缓存命中 ${cached.length}B');
      return Future.value([200, 'video/MP2T', cached, <String, String>{}, 0]);
    }
    final inflight = _segmentInflight[url];
    if (inflight != null) {
      print('[drpy3-worker][ts] $name 复用 inflight');
      return inflight;
    }
    final future = _decryptSegment(url);
    _segmentInflight[url] = future;
    return future.whenComplete(() => _segmentInflight.remove(url));
  }

  Future<List<dynamic>> _decryptSegment(String url) async {
    final name = _shortName(url);
    final sw = Stopwatch()..start();
    final result = await _callJsProxy({'url': url});
    if (result.length >= 5 && result[2] is String && result[4] == 1) {
      try {
        final bytes = base64Decode(result[2] as String);
        while (_segmentCache.length >= _maxSegmentCache) {
          _segmentCache.remove(_segmentCache.keys.first);
        }
        _segmentCache[url] = bytes;
        sw.stop();
        print('[drpy3-worker][ts] $name 解密 ${bytes.length}B '
            '${sw.elapsedMilliseconds}ms');
        return [200, result[1], bytes, result[3] ?? <String, String>{}, 0];
      } catch (e) {
        print('[drpy3-worker][ts] $name base64 解码失败: $e\n  url=$url');
        return result;
      }
    }
    sw.stop();
    final body = result.length >= 3 ? result[2]?.toString() ?? '' : '';
    print('[drpy3-worker][ts] $name 未解密 '
        'status=${result.isNotEmpty ? result[0] : '?'} '
        'body=${body.length > 120 ? '${body.substring(0, 120)}...' : body}'
        '\n  url=$url');
    return result;
  }

  Future<List<dynamic>> _callJsProxy(Map<String, String> params) async {
    if (_engine == null || _currentKey == null) {
      return [500, 'text/plain', 'engine/key not ready'];
    }
    final sw = Stopwatch()..start();
    try {
      final argsJson = jsonEncode([params]);
      final resultJson = await _engine!.callAsync('__drpy3Call', [
        _currentKey!,
        'proxy',
        argsJson,
      ]);
      sw.stop();
      if (resultJson is String) {
        final parsed = jsonDecode(resultJson);
        if (parsed is List) {
          // 成功日志由调用方输出，这里静默
          return parsed;
        }
        if (parsed is Map && parsed.containsKey('__drpy3_error')) {
          final err = parsed['__drpy3_error'];
          final msg = err is Map ? err['error']?.toString() : err.toString();
          print('[drpy3-worker][proxy] 源错误 ${sw.elapsedMilliseconds}ms: $msg');
          return [500, 'text/plain', msg ?? 'unknown'];
        }
      }
      return [500, 'text/plain', 'invalid proxy result'];
    } catch (e) {
      sw.stop();
      print('[drpy3-worker][proxy] 异常 ${sw.elapsedMilliseconds}ms: $e');
      return [500, 'text/plain', 'proxy call failed: $e'];
    }
  }

  Future<void> _writeProxyResult(
      HttpRequest req, List<dynamic> result) async {
    if (result.length < 3) {
      req.response.statusCode = 500;
      req.response.add(utf8.encode('invalid proxy result'));
      await req.response.close();
      return;
    }
    final status = (result[0] as num?)?.toInt() ?? 404;
    final contentType = result[1]?.toString() ?? 'application/octet-stream';
    final content = result[2];
    final extraHeaders = result.length > 3 && result[3] is Map
        ? Map<String, String>.from((result[3] as Map).map((k, v) => MapEntry(
            k.toString(), v is List ? v.join(', ') : v?.toString() ?? '')))
        : <String, String>{};
    final toBytes = result.length > 4 ? result[4] : null;

    req.response.statusCode = status;
    req.response.headers.set('content-type', contentType);
    req.response.headers.set('access-control-allow-origin', '*');
    for (final e in extraHeaders.entries) {
      req.response.headers.set(e.key, e.value);
    }

    if ((toBytes == 1 || toBytes == true) && content is String) {
      try {
        req.response.add(base64Decode(content));
      } catch (_) {
        req.response.statusCode = 500;
      }
      await req.response.close();
      return;
    }
    if (toBytes == 2 && content is String) {
      req.response.statusCode = 302;
      req.response.headers.set('location', content);
      await req.response.close();
      return;
    }
    if (toBytes == 3 && content is String) {
      try {
        final reqHeaders = <String, String>{};
        final range = req.headers.value('range');
        if (range != null) reqHeaders['range'] = range;
        final resp = await _dio.get(content,
            options: Options(
                responseType: ResponseType.stream, headers: reqHeaders));
        req.response.statusCode = resp.statusCode ?? 200;
        await req.response.addStream((resp.data as ResponseBody).stream);
        await req.response.close();
      } catch (_) {
        req.response.statusCode = 500;
        await req.response.close();
      }
      return;
    }
    if (content is Uint8List) {
      req.response.add(content);
    } else if (content is List<int>) {
      req.response.add(content);
    } else {
      req.response.add(utf8.encode(content?.toString() ?? ''));
    }
    await req.response.close();
  }

  // ============================================================
  // bridge
  // ============================================================
  Future<Object?> _handleBridge(Object? message) async {
    final msg = (message as Map).cast<String, dynamic>();
    switch (msg['action']) {
      case 'req':
        return await _doDioRequest(msg['url'] as String,
            (msg['options'] as Map?)?.cast<String, dynamic>() ?? {});
      case 'loadAsset':
        return await _loadAsset(msg['path'] as String);
      case 'getProxy':
        return 'http://127.0.0.1:$_proxyPort/proxy?do=js';
      case 'evalModule':
        final code = msg['code'] as String;
        final path = (msg['path'] as String?) ?? '';
        final name = path.isNotEmpty
            ? path
            : '__eval_${DateTime.now().microsecondsSinceEpoch}';
        _engine!.registerModule(name, code);
        return name;
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> _doDioRequest(
      String url, Map<String, dynamic> opts) async {
    final method = (opts['method'] ?? 'GET').toString().toUpperCase();
    final headers = <String, String>{};
    (opts['headers'] as Map?)?.forEach((k, v) {
      if (v == null) return;
      final lk = k.toString().toLowerCase();
      if (lk == 'host' || lk == 'connection') return;
      headers[k.toString()] = v is List ? v.join(', ') : v.toString();
    });
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 11) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Mobile Safari/537.36';
    }
    dynamic body = opts['body'];
    if (opts['data'] != null) {
      body = jsonEncode(opts['data']);
      headers.putIfAbsent('Content-Type', () => 'application/json');
    }
    final bufferType = opts['buffer'];
    final resp = await _dio.request(url,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
        data: body);
    final bytes = (resp.data as List).cast<int>();
    final respHeaders = <String, String>{};
    resp.headers.forEach((k, v) {
      if (v.isNotEmpty) respHeaders[k] = v.first;
    });
    if (bufferType == 1) {
      return {
        'content': Uint8List.fromList(bytes),
        'headers': respHeaders,
        'buffer': 1
      };
    }
    if (bufferType == 2) {
      return {
        'content': base64Encode(bytes),
        'headers': respHeaders,
        'buffer': 2
      };
    }
    return {
      'content': utf8.decode(bytes, allowMalformed: true),
      'headers': respHeaders
    };
  }

  Future<Uint8List> _loadAsset(String rawPath) async {
    final cached = _assetCache[rawPath];
    if (cached != null) return cached;
    final base = _currentSourceBase;
    if (rawPath.startsWith('http://') || rawPath.startsWith('https://')) {
      return _loadAssetHttp(rawPath, rawPath);
    }
    if (base == null || base.isEmpty) {
      throw Exception('无 base URL: $rawPath');
    }
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      final rel = rawPath.startsWith('./') ? rawPath.substring(2) : rawPath;
      final sep =
          base.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator;
      final fullPath = '$base$sep$rel';
      final bytes = await File(fullPath).readAsBytes();
      _assetCache[rawPath] = bytes;
      return bytes;
    }
    return _loadAssetHttp(rawPath, Uri.parse(base).resolve(rawPath).toString());
  }

  Future<Uint8List> _loadAssetHttp(String cacheKey, String url) async {
    final resp = await _dio.get<List<int>>(url,
        options: Options(responseType: ResponseType.bytes));
    if (resp.statusCode != 200) {
      throw Exception('loadAsset HTTP ${resp.statusCode}: $url');
    }
    final bytes = Uint8List.fromList(resp.data ?? <int>[]);
    if (cacheKey.endsWith('.js') ||
        cacheKey.endsWith('.mjs') ||
        cacheKey.endsWith('.cjs') ||
        cacheKey.endsWith('.wasm') ||
        cacheKey.contains('wasm') ||
        cacheKey.contains('worker')) {
      _assetCache[cacheKey] = bytes;
    }
    return bytes;
  }

  // ============================================================
  // 源加载与六环节
  // ============================================================
  Future<void> _loadSource(String apiUrl, String siteKey,
      {dynamic ext}) async {
    _siteVersion++;
    _siteReady = Completer<void>();
    _currentKey = siteKey;
    final version = _siteVersion;
    try {
      _assetCache.clear();
      _segmentCache.clear();
      _segmentInflight.clear();
      final extStr = ext is String ? ext : (ext?.toString() ?? '');
      String? sourceUrl;
      String? localPath;
      String? inlineCode;
      if (extStr.isNotEmpty) {
        if (extStr.startsWith('http://') || extStr.startsWith('https://')) {
          sourceUrl = extStr;
        } else if (File(extStr).existsSync()) {
          localPath = extStr;
          inlineCode = await File(extStr).readAsString();
        } else if (extStr.contains('export default') ||
            extStr.contains('defineSource') ||
            extStr.startsWith('{')) {
          inlineCode = extStr;
        }
      }
      if (sourceUrl == null && inlineCode == null && apiUrl.isNotEmpty) {
        if (File(apiUrl).existsSync()) {
          localPath = apiUrl;
          inlineCode = await File(apiUrl).readAsString();
        } else {
          sourceUrl = apiUrl;
        }
      }
      if (sourceUrl == null && inlineCode == null) return;

      String code;
      if (inlineCode != null) {
        code = inlineCode;
        _currentSourceBase =
            localPath != null ? File(localPath).parent.path : null;
      } else {
        final resp = await _dio.get<List<int>>(sourceUrl!,
            options: Options(responseType: ResponseType.bytes));
        code = utf8.decode((resp.data ?? []), allowMalformed: true);
        final uri = Uri.parse(sourceUrl);
        final p = uri.path;
        _currentSourceBase = uri
            .replace(
                path: p.contains('/')
                    ? p.substring(0, p.lastIndexOf('/') + 1)
                    : '/')
            .toString();
      }
      if (code.trimLeft().startsWith('H4sI')) {
        try {
          code = utf8.decode(
              gzip.decode(base64Decode(code.replaceAll(RegExp(r'\s'), ''))),
              allowMalformed: true);
        } catch (_) {}
      }
      final r = await _engine!.callAsync('__drpy3Load', [
        code,
        siteKey,
        sourceUrl ?? '',
        extStr.isNotEmpty ? jsonEncode(extStr) : null,
        siteKey
      ]);
      final failed =
          r is String && r.contains('__drpy3_error');
      print('[drpy3-worker] 源加载${failed ? '失败' : '成功'}: $siteKey');
      if (failed) print('[drpy3-worker] 详情: $r');
    } catch (e) {
      print('[drpy3-worker] 源加载异常: $siteKey - $e');
    } finally {
      if (version == _siteVersion &&
          _siteReady != null &&
          !_siteReady!.isCompleted) {
        _siteReady!.complete();
      }
    }
  }

  Future<Map<String, dynamic>> _callSource(
      String fn, List<dynamic> args) async {
    final ready = _siteReady;
    if (ready != null && !ready.isCompleted) {
      try {
        await ready.future.timeout(const Duration(seconds: 90));
      } catch (_) {}
    }
    if (_engine == null) return {'success': false, 'error': 'engine null'};

    final argsJson = jsonEncode(args);
    try {
      final resultJson = await _engine!.callAsync('__drpy3Call', [
        _currentKey ?? '',
        fn,
        argsJson,
      ]);
      if (resultJson is String) {
        final parsed = jsonDecode(resultJson);
        if (parsed is Map) {
          if (parsed.containsKey('__drpy3_error')) {
            final err = parsed['__drpy3_error'];
            return {
              'success': false,
              'error': err is Map ? err['error']?.toString() : err.toString()
            };
          }
          return parsed.cast<String, dynamic>();
        }
      }
      return {'success': false, 'error': 'unexpected'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 用于日志：URL 只保留文件名（如 0.ts、2000.m3u8），长 URL 不刷屏。
  /// 失败时调用方自己输出完整 URL，保留排查能力。
  String _shortName(String url) {
    if (url.isEmpty) return '';
    final path = url.split('?').first;
    final segs = path.split('/');
    final last = segs.isNotEmpty ? segs.last : path;
    return last.isEmpty ? path : last;
  }
}