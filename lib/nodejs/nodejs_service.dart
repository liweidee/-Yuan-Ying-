import 'dart:async';
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

  String? _lastLoadedUrl;
  bool _isRestarting = false;

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

  void _log(String msg) {
    _logService.addLog(msg);
    debugPrint(msg);
  }

  @override
  Future<void> onInit() async {
    super.onInit();
    _logService = Get.find<CatVodLogService>();
    await initialize();
  }

  // ========== 公共初始化 ==========
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

  // ========== 核心健康检查和恢复 ==========
  /// 确保服务可用（外部调用入口）
  Future<bool> ensureServiceAlive() async {
    if (_isRestarting) return false;
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return false;
    }
    if (_managementPort <= 0 || _spiderPort <= 0) {
      _log('端口无效，触发恢复');
      await _recoverService();
      return _isInitialized && _spiderPort > 0;
    }
    final alive = await isServiceAlive();
    if (!alive) {
      _log('服务不可用，触发恢复');
      await _recoverService();
      return _isInitialized && _spiderPort > 0;
    }
    return true;
  }

  /// 内部恢复：停止→重新初始化→加载源（不触发首页刷新）
  Future<void> _recoverService() async {
    if (_isRestarting) return;
    _isRestarting = true;
    _log('开始恢复 Node.js 服务...');
    try {
      await stop();
      await Future.delayed(const Duration(milliseconds: 300));
      await initialize();
      if (_isInitialized && _lastLoadedUrl != null && _lastLoadedUrl!.isNotEmpty) {
        _log('重新加载源: $_lastLoadedUrl');
        final ok = await _loadSourceDirectly(_lastLoadedUrl!);
        if (ok) {
          _log('源重载成功，spiderPort: $_spiderPort');
        } else {
          _log('源重载失败，可能需要手动刷新');
        }
      }
    } finally {
      _isRestarting = false;
    }
  }

  // ========== 加载源的公共入口 ==========
  Future<bool> loadSourceFromURL(String url) async {
    _lastLoadedUrl = url;
    if (!await ensureServiceAlive()) {
      _log('服务不可用，无法加载源');
      return false;
    }
    return await _loadSourceDirectly(url);
  }

  // ========== 内部直接加载（无健康检查，避免递归） ==========
  Future<bool> _loadSourceDirectly(String url) async {
    // 确保管理端口有效（如果还未收到，等待最多10秒）
    if (_managementPort == 0) {
      _log('_loadSourceDirectly: waiting for managementPort...');
      _managementPortCompleter = Completer<void>();
      final timer = Timer(const Duration(seconds: 10), () {
        if (!_managementPortCompleter!.isCompleted) {
          _managementPortCompleter!.complete();
          _log('_loadSourceDirectly: managementPort wait timeout');
        }
      });
      await _managementPortCompleter!.future;
      timer.cancel();
      if (_managementPort == 0) {
        _log('_loadSourceDirectly: managementPort still 0, cannot load');
        return false;
      }
    }

    try {
      _log('_loadSourceDirectly: calling native load for $url');
      final result = await _channel.invokeMethod('loadSourceFromURL', {'url': url});
      _log('_loadSourceDirectly result: $result');
      if (result is Map && result['success'] == true) {
        await waitForSpiderPort();
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      _log('_loadSourceDirectly PlatformException: ${e.message}');
      return false;
    } catch (e) {
      _log('_loadSourceDirectly error: $e');
      return false;
    }
  }

  // ========== 其他公开方法 ==========
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
    await _recoverService();
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
    final result = await getPlayUrl(videoId: '', flag: '', playId: playId);
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

  Future<Map<String, dynamic>> diagnoseSpider() async {
    // 保留原有诊断代码（太长，省略，您可保留原实现）
    return {};
  }

  @override
  void onClose() {
    stop();
    super.onClose();
  }
}