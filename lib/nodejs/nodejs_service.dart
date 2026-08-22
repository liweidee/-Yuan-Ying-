import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:yuanying/services/catvod_log_service.dart';

class NodeJSService extends GetxService {
  static const MethodChannel _channel = MethodChannel('com.tvbox/nodejs');
  static const EventChannel _eventChannel = EventChannel('com.tvbox/nodejs/events');

  static final NodeJSService _instance = NodeJSService._internal();
  factory NodeJSService() => _instance;
  NodeJSService._internal();

  static NodeJSService get instance => _instance;

  bool _isInitialized = false;
  bool _isNodeReady = false;
  int _managementPort = 0;
  int _spiderPort = 0;
  int _nativeServerPort = 0;
  String _currentSpiderKey = '';
  int _currentSpiderType = 3;
  String _spiderApiBase = '';
  String _websiteUrl = '';
  Completer<void>? _readyCompleter;
  Completer<void>? _managementPortCompleter;
  Completer<void>? _spiderPortCompleter;
  StreamSubscription? _eventSubscription;

  bool get isInitialized => _isInitialized;
  bool get isNodeReady => _isNodeReady;
  int get managementPort => _managementPort;
  int get spiderPort => _spiderPort;
  bool get hasSpiderServer => _spiderPort > 0;

  String? _lastLoadedUrl;        // 保存最近一次加载的源 URL
  bool _isRestarting = false;    // 防止并发重启

  late CatVodLogService _logService;

  String _spiderBaseUrl() => 'http://127.0.0.1:$_spiderPort';
  String _spiderPath() {
    if (_spiderApiBase.isNotEmpty) return _spiderApiBase;
    return '/$_currentSpiderKey/$_currentSpiderType';
  }

  void _setupEventListener() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is String) {
          try {
            final data = jsonDecode(event) as Map<String, dynamic>;
            if (data.containsKey('event')) {
              final eventType = data['event'] as String;
              if (eventType == 'ready') {
                _isNodeReady = true;
                _readyCompleter?.complete();
              } else if (eventType == 'message') {
                _log('Node.js message: ${data['message']}');
              }
            } else if (data.containsKey('port') && data.containsKey('type')) {
              final port = data['port'] as int;
              final type = data['type'] as String;
              if (type == 'management') {
                _managementPort = port;
                _log('Management port received: $port');
                _managementPortCompleter?.complete();
              } else if (type == 'spider') {
                _spiderPort = port;
                _log('Spider port received: $port');
                _spiderPortCompleter?.complete();
              }
            }
          } catch (e) {
            _log('Event parse error: $e');
          }
        }
      },
      onError: (error) {
        _log('Event channel error: $error');
      },
    );
  }

  // 内部日志方法
  void _log(String msg) {
    _logService.addLog(msg);
    debugPrint(msg); // 可选保留打印
  }

  @override
  Future<void> onInit() async {
    super.onInit();
    _logService = Get.find<CatVodLogService>();
    await initialize();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    _setupEventListener();

    try {
      _readyCompleter = Completer<void>();
      _managementPortCompleter = Completer<void>();

      final result = await _channel.invokeMethod('startNodeJS');
      _isInitialized = result == true;

      if (_isInitialized) {
        final readyTimeout = Timer(const Duration(seconds: 15), () {
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
            _log('Warning: Node.js ready signal timeout, proceeding anyway');
            _readyCompleter!.complete();
          }
        });

        await _readyCompleter!.future;
        readyTimeout.cancel();

        final mgmtTimeout = Timer(const Duration(seconds: 15), () {
          if (_managementPortCompleter != null && !_managementPortCompleter!.isCompleted) {
            _log('Warning: Management port timeout, proceeding anyway');
            _managementPortCompleter!.complete();
          }
        });

        await _managementPortCompleter!.future;
        mgmtTimeout.cancel();
      }
    } catch (e) {
      _log('Node.js initialization error: $e');
      _isInitialized = false;
    }
  }

  Future<bool> loadSourceFromURL(String url) async {
    _lastLoadedUrl = url;

    // 确保已初始化
    if (!_isInitialized) {
      await initialize();
    }

    // 如果 managementPort 为 0，主动等待
    if (_managementPort == 0) {
      _log('managementPort is 0, waiting...');
      _managementPortCompleter ??= Completer<void>();
      final timer = Timer(const Duration(seconds: 10), () {
        if (!_managementPortCompleter!.isCompleted) {
          _managementPortCompleter!.complete();
          _log('managementPort wait timeout');
        }
      });
      await _managementPortCompleter!.future;
      timer.cancel();
      if (_managementPort == 0) {
        _log('managementPort still 0, cannot load source');
        return false;
      }
    }

    try {
      _log('loadSourceFromURL: $url');
      final result = await _channel.invokeMethod('loadSourceFromURL', {'url': url});
      _log('loadSourceFromURL result: $result');
      if (result is Map && result['success'] == true) {
        await waitForSpiderPort();
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      _log('PlatformException: ${e.message}');
      return false;
    } catch (e) {
      _log('loadSourceFromURL error: $e');
      return false;
    }
  }

  Future<void> waitForSpiderPort({Duration timeout = const Duration(seconds: 30)}) async {
    if (_spiderPort > 0) return;

    _spiderPortCompleter = Completer<void>();
    final timer = Timer(timeout, () {
      if (_spiderPortCompleter != null && !_spiderPortCompleter!.isCompleted) {
        _log('Warning: Spider port timeout');
        _spiderPortCompleter!.complete();
      }
    });

    await _spiderPortCompleter!.future;
    timer.cancel();
  }

  Future<bool> isServiceAlive() async {
    if (_spiderPort <= 0) return false;
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$_spiderPort/config'),
      ).timeout(const Duration(milliseconds: 800));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> reinitialize() async {
    if (_isRestarting) return;
    _isRestarting = true;
    _log('🔄 无感重启 Node.js 服务...');
    try {
      // 停止旧服务
      await stop();
      // 等待原生资源释放（关键）
      await Future.delayed(const Duration(milliseconds: 300));

      // 重置状态（stop 已重置部分，但显式确保）
      _isInitialized = false;
      _isNodeReady = false;
      _managementPort = 0;
      _spiderPort = 0;
      _spiderApiBase = '';
      _eventSubscription?.cancel();

      // 重新初始化
      await initialize();

      // 重新加载源（带重试）
      if (_lastLoadedUrl != null && _lastLoadedUrl!.isNotEmpty) {
        bool loaded = false;
        for (int i = 0; i < 3; i++) {
          _log('📡 重新加载源尝试 ${i+1}/3: $_lastLoadedUrl');
          loaded = await loadSourceFromURL(_lastLoadedUrl!);
          if (loaded) break;
          if (i < 2) await Future.delayed(const Duration(milliseconds: 500));
        }
        if (loaded) {
          _log('✅ 源重载成功，spiderPort: $_spiderPort');
        } else {
          _log('❌ 源重载失败，可能需要手动刷新');
        }
      } else {
        _log('⚠️ 无保存的源 URL，跳过加载');
      }
    } catch (e) {
      _log('❌ reinitialize 异常: $e');
    } finally {
      _isRestarting = false;
    }
    _log('✅ 无感重启流程结束');
  }

  Future<bool> deleteSource() async {
    try {
      final result = await _channel.invokeMethod('deleteSource');
      _spiderPort = 0;
      _spiderApiBase = '';
      if (result == true) {
        _lastLoadedUrl = null;
      }
      return result == true;
    } catch (e) {
      print('deleteSource error: $e');
      return false;
    }
  }

  void setCurrentSpider(String key, int type, {String apiBase = ''}) {
    _currentSpiderKey = key;
    _currentSpiderType = type;
    _spiderApiBase = apiBase;
    _log('setCurrentSpider: key=$key, type=$type, apiBase=$apiBase');
  }

  String get currentSpiderKey => _currentSpiderKey;
  int get currentSpiderType => _currentSpiderType;

  void setWebsiteUrl(String url) {
    _websiteUrl = url;
  }

  String getWebsiteUrl() => _websiteUrl;

  Future<void> initSpider() async {
    if (_spiderPort <= 0 || (_spiderApiBase.isEmpty && _currentSpiderKey.isEmpty)) {
      return;
    }
    try {
      final url = '${_spiderBaseUrl()}${_spiderPath()}/init';
      _log('initSpider POST $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 10));
      _log('initSpider status=${response.statusCode}');
    } catch (e) {
      _log('initSpider error: $e');
    }
  }

  Future<Map<String, dynamic>> getCatConfig({int retries = 3}) async {
    if (_spiderPort <= 0) return {};
    for (int i = 0; i < retries; i++) {
      try {
        final url = '${_spiderBaseUrl()}/config';
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          // 解析并设置 _spiderApiBase
          final videoSites = data['video']?['sites'] as List<dynamic>? ?? [];
          if (videoSites.isNotEmpty) {
            final api = videoSites.first['api'] as String? ?? '';
            if (api.isNotEmpty) _spiderApiBase = api;
          }
          return data;
        }
      } catch (e) {
        _log('getCatConfig attempt ${i+1} failed: $e');
        if (i < retries - 1) await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
      }
    }
    return {};
  }

  Future<Map<String, dynamic>> getHomeContent() async {
    if (_spiderPort <= 0 || (_spiderApiBase.isEmpty && _currentSpiderKey.isEmpty)) {
      return {};
    }
    try {
      final url = '${_spiderBaseUrl()}${_spiderPath()}/home';
      _log('getHomeContent POST $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      _log('getHomeContent error: $e');
    }
    return {};
  }

  Future<Map<String, dynamic>> getCategoryContent({
    required String categoryId,
    int page = 1,
    Map<String, dynamic> filters = const {},
  }) async {
    if (_spiderPort <= 0 || (_spiderApiBase.isEmpty && _currentSpiderKey.isEmpty)) {
      return {};
    }
    for (int retry = 0; retry < 3; retry++) {
      try {
        final url = '${_spiderBaseUrl()}${_spiderPath()}/category';
        _log('getCategoryContent POST $url (retry $retry)');
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id': categoryId,
            'page': page,
            'filters': filters,
          }),
        ).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        break;
      } on TimeoutException catch (e) {
        _log('getCategoryContent timeout (retry ${retry + 1}/3): $e');
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 1 + retry));
          continue;
        }
      } catch (e) {
        _log('getCategoryContent error: $e');
        break;
      }
    }
    return {};
  }

  Future<Map<String, dynamic>> getVideoDetail({required String videoId}) async {
    if (_spiderPort <= 0 || (_spiderApiBase.isEmpty && _currentSpiderKey.isEmpty)) {
      return {};
    }
    try {
      final url = '${_spiderBaseUrl()}${_spiderPath()}/detail';
      _log('getVideoDetail POST $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': videoId}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      _log('getVideoDetail error: $e');
    }
    return {};
  }

  Future<Map<String, dynamic>> getPlayUrl({
    required String videoId,
    required String flag,
    required String playId,
  }) async {
    if (_spiderPort <= 0 || (_spiderApiBase.isEmpty && _currentSpiderKey.isEmpty)) {
      return {};
    }
    try {
      final url = '${_spiderBaseUrl()}${_spiderPath()}/play';
      _log('getPlayUrl POST $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'flag': flag,
          'id': playId,
        }),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      _log('getPlayUrl error: $e');
    }
    return {};
  }

  Future<String?> getPlayUrlSimple(String playId) async {
    final result = await getPlayUrl(
      videoId: '',
      flag: '',
      playId: playId,
    );
    return result['url'] as String?;
  }

  Future<Map<String, dynamic>> search({required String keyword, int page = 1}) async {
    if (_spiderPort <= 0 || (_spiderApiBase.isEmpty && _currentSpiderKey.isEmpty)) {
      return {};
    }
    for (int retry = 0; retry < 3; retry++) {
      try {
        final url = '${_spiderBaseUrl()}${_spiderPath()}/search';
        _log('search POST $url (retry $retry)');
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'wd': keyword,
            'page': page,
          }),
        ).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        break;
      } on TimeoutException catch (e) {
        _log('search timeout (retry ${retry + 1}/3): $e');
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 1 + retry));
          continue;
        }
      } catch (e) {
        _log('search error: $e');
        break;
      }
    }
    return {};
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopNodeJS');
    } catch (e) {
      _log('stopNodeJS error: $e');
    }
    _isInitialized = false;
    _isNodeReady = false;
    _managementPort = 0;
    _spiderPort = 0;
    _spiderApiBase = '';
    _eventSubscription?.cancel();
  }

  /// 诊断蜘蛛源 - 移植自 tvbox_flutter
  Future<Map<String, dynamic>> diagnoseSpider() async {
    final result = <String, dynamic>{};
    result['spiderPort'] = _spiderPort;
    result['spiderApiBase'] = _spiderApiBase;
    result['currentSpiderKey'] = _currentSpiderKey;
    result['currentSpiderType'] = _currentSpiderType;

    if (_spiderPort <= 0) {
      result['error'] = 'spiderPort is 0';
      return Map<String, dynamic>.from(result);
    }

    // 辅助日志（使用您已有的日志服务或 print）
    void _log(String msg) {
      // 如果有 CatVodLogService 则使用，否则 print
      try {
        final logService = Get.find<CatVodLogService>();
        logService.addLog('[诊断] $msg');
      } catch (_) {
        print('[诊断] $msg');
      }
    }

    final getPaths = <String>[];
    getPaths.add('/config');
    getPaths.add('/check');
    getPaths.add('/init');
    getPaths.add('/home');
    getPaths.add('/category');
    getPaths.add('/detail');
    getPaths.add('/search');
    getPaths.add('/play');
    getPaths.add('/live');
    getPaths.add('/website/config');
    getPaths.add('/website/home');
    getPaths.add('/website/category');
    if (_spiderApiBase.isNotEmpty) {
      getPaths.add('$_spiderApiBase/home');
      getPaths.add('$_spiderApiBase/category');
      getPaths.add('$_spiderApiBase/detail');
      getPaths.add('$_spiderApiBase/search');
      getPaths.add('$_spiderApiBase/init');
    }
    if (_currentSpiderKey.isNotEmpty) {
      getPaths.add('/$_currentSpiderKey/$_currentSpiderType/home');
      getPaths.add('/$_currentSpiderKey/$_currentSpiderType/category');
    }

    final queryParamPaths = <String>[
      '/?action=home',
      '/?action=config',
      '/?do=home',
      '/?m=home',
      '/api/home',
      '/api/config',
      '/api/v1/home',
      '/api/v1/config',
      '/spider/home',
      '/spider/config',
    ];

    result['=== GET Requests ==='] = null;
    for (final path in getPaths) {
      try {
        final url = 'http://127.0.0.1:$_spiderPort$path';
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        result['GET $path'] = <String, dynamic>{
          'status': response.statusCode,
          'body': response.body.length > 200 ? response.body.substring(0, 200) : response.body,
        };
      } catch (e) {
        result['GET $path'] = <String, dynamic>{'error': e.toString()};
      }
    }

    result['=== Query Parameter Paths ==='] = null;
    for (final path in queryParamPaths) {
      try {
        final url = 'http://127.0.0.1:$_spiderPort$path';
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        result['GET $path'] = <String, dynamic>{
          'status': response.statusCode,
          'body': response.body.length > 200 ? response.body.substring(0, 200) : response.body,
        };
      } catch (e) {
        result['GET $path'] = <String, dynamic>{'error': e.toString()};
      }
    }

    final postTests = <Map<String, dynamic>>[
      {'path': '/home', 'body': <String, dynamic>{}},
      {'path': '/init', 'body': <String, dynamic>{}},
      {'path': '/category', 'body': <String, dynamic>{'id': 'test', 'page': 1}},
      {'path': '/detail', 'body': <String, dynamic>{'id': 'test'}},
      {'path': '/search', 'body': <String, dynamic>{'wd': 'test', 'page': 1}},
      {'path': '/play', 'body': <String, dynamic>{'flag': 'test', 'id': 'test'}},
    ];

    result['=== POST Requests (root) ==='] = null;
    for (final test in postTests) {
      final path = test['path'] as String;
      final body = test['body'] as Map<String, dynamic>;
      try {
        final url = 'http://127.0.0.1:$_spiderPort$path';
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 5));
        result['POST $path'] = <String, dynamic>{
          'status': response.statusCode,
          'body': response.body.length > 200 ? response.body.substring(0, 200) : response.body,
        };
      } catch (e) {
        result['POST $path'] = <String, dynamic>{'error': e.toString()};
      }
    }

    if (_spiderApiBase.isNotEmpty) {
      result['=== POST Requests (with prefix) ==='] = null;
      for (final test in postTests) {
        final path = test['path'] as String;
        final body = test['body'] as Map<String, dynamic>;
        final fullPath = '$_spiderApiBase$path';
        try {
          final url = 'http://127.0.0.1:$_spiderPort$fullPath';
          final response = await http.post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          ).timeout(const Duration(seconds: 5));
          result['POST $fullPath'] = <String, dynamic>{
            'status': response.statusCode,
            'body': response.body.length > 200 ? response.body.substring(0, 200) : response.body,
          };
        } catch (e) {
          result['POST $fullPath'] = <String, dynamic>{'error': e.toString()};
        }
      }

      // 完整工作流测试
      result['=== Full Workflow Test ==='] = null;
      try {
        final fullBase = '$_spiderApiBase';

        // 1. 初始化
        final initUrl = 'http://127.0.0.1:$_spiderPort$fullBase/init';
        await http.post(
          Uri.parse(initUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        ).timeout(const Duration(seconds: 5));

        // 2. 搜索
        final searchUrl = 'http://127.0.0.1:$_spiderPort$fullBase/search';
        final searchResp = await http.post(
          Uri.parse(searchUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'wd': '电影', 'page': 1}),
        ).timeout(const Duration(seconds: 5));
        result['[Step1] Search'] = {
          'status': searchResp.statusCode,
          'body': searchResp.body.length > 300 ? searchResp.body.substring(0, 300) : searchResp.body,
        };

        if (searchResp.statusCode == 200) {
          final searchData = jsonDecode(searchResp.body);
          final list = searchData['list'] as List? ?? [];

          if (list.isNotEmpty) {
            final vodId = list[0]['vod_id']?.toString() ?? '';
            result['[Step1a] Got vod_id'] = vodId;

            // 3. 详情
            final detailUrl = 'http://127.0.0.1:$_spiderPort$fullBase/detail';
            final detailResp = await http.post(
              Uri.parse(detailUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'id': vodId}),
            ).timeout(const Duration(seconds: 5));
            result['[Step2] Detail'] = {
              'status': detailResp.statusCode,
              'body': detailResp.body.length > 500 ? detailResp.body.substring(0, 500) : detailResp.body,
            };

            if (detailResp.statusCode == 200) {
              final detailData = jsonDecode(detailResp.body);
              final detailList = detailData['list'] as List? ?? [];

              if (detailList.isNotEmpty) {
                final vod = detailList[0];
                final vodPlayFrom = vod['vod_play_from']?.toString() ?? '';
                final vodPlayUrl = vod['vod_play_url']?.toString() ?? '';

                result['[Step2a] vod_play_from'] = vodPlayFrom;
                result['[Step2b] vod_play_url'] = vodPlayUrl.length > 200 ? '${vodPlayUrl.substring(0, 200)}...' : vodPlayUrl;

                if (vodPlayFrom.isNotEmpty && vodPlayUrl.isNotEmpty) {
                  final froms = vodPlayFrom.split('\$\$\$');
                  final urls = vodPlayUrl.split('\$\$\$');

                  if (froms.isNotEmpty && urls.isNotEmpty) {
                    final flag = froms[0];
                    final firstSource = urls[0].split('#')[0];
                    final parts = firstSource.split('\$');

                    String? playId;
                    if (parts.length >= 2) {
                      playId = parts[1];
                    } else {
                      playId = firstSource;
                    }

                    result['[Step3] Play Input'] = {'flag': flag, 'id': playId};

                    final playUrl = 'http://127.0.0.1:$_spiderPort$fullBase/play';
                    final playResp = await http.post(
                      Uri.parse(playUrl),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'flag': flag, 'id': playId}),
                    ).timeout(const Duration(seconds: 5));
                    result['[Step3] Play Response'] = {
                      'status': playResp.statusCode,
                      'body': playResp.body.length > 200 ? playResp.body.substring(0, 200) : playResp.body,
                    };
                  }
                }
              }
            }
          }
        }
      } catch (e, stackTrace) {
        result['Workflow Test Error'] = {'error': e.toString(), 'stack': stackTrace.toString()};
      }
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  void onClose() {
    stop();
    super.onClose();
  }
}