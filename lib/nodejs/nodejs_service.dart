import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';

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
                print('Node.js message: ${data['message']}');
              }
            } else if (data.containsKey('port') && data.containsKey('type')) {
              final port = data['port'] as int;
              final type = data['type'] as String;
              if (type == 'management') {
                _managementPort = port;
                print('Management port received: $port');
                _managementPortCompleter?.complete();
              } else if (type == 'spider') {
                _spiderPort = port;
                print('Spider port received: $port');
                _spiderPortCompleter?.complete();
              }
            }
          } catch (e) {
            print('Event parse error: $e');
          }
        }
      },
      onError: (error) {
        print('Event channel error: $error');
      },
    );
  }

  @override
  Future<void> onInit() async {
    super.onInit();
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
            print('Warning: Node.js ready signal timeout, proceeding anyway');
            _readyCompleter!.complete();
          }
        });

        await _readyCompleter!.future;
        readyTimeout.cancel();

        final mgmtTimeout = Timer(const Duration(seconds: 15), () {
          if (_managementPortCompleter != null && !_managementPortCompleter!.isCompleted) {
            print('Warning: Management port timeout, proceeding anyway');
            _managementPortCompleter!.complete();
          }
        });

        await _managementPortCompleter!.future;
        mgmtTimeout.cancel();
      }
    } catch (e) {
      print('Node.js initialization error: $e');
      _isInitialized = false;
    }
  }

  Future<bool> loadSourceFromURL(String url) async {
    // 确保已初始化
    if (!_isInitialized) {
      await initialize();
    }

    // 如果 managementPort 为 0，主动等待
    if (_managementPort == 0) {
      print('managementPort is 0, waiting...');
      _managementPortCompleter ??= Completer<void>();
      final timer = Timer(const Duration(seconds: 10), () {
        if (!_managementPortCompleter!.isCompleted) {
          _managementPortCompleter!.complete();
          print('managementPort wait timeout');
        }
      });
      await _managementPortCompleter!.future;
      timer.cancel();
      if (_managementPort == 0) {
        print('managementPort still 0, cannot load source');
        return false;
      }
    }

    try {
      print('loadSourceFromURL: $url');
      final result = await _channel.invokeMethod('loadSourceFromURL', {'url': url});
      print('loadSourceFromURL result: $result');
      if (result is Map && result['success'] == true) {
        await waitForSpiderPort();
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      print('PlatformException: ${e.message}');
      return false;
    } catch (e) {
      print('loadSourceFromURL error: $e');
      return false;
    }
  }

  Future<void> waitForSpiderPort({Duration timeout = const Duration(seconds: 30)}) async {
    if (_spiderPort > 0) return;

    _spiderPortCompleter = Completer<void>();
    final timer = Timer(timeout, () {
      if (_spiderPortCompleter != null && !_spiderPortCompleter!.isCompleted) {
        print('Warning: Spider port timeout');
        _spiderPortCompleter!.complete();
      }
    });

    await _spiderPortCompleter!.future;
    timer.cancel();
  }

  Future<bool> deleteSource() async {
    try {
      final result = await _channel.invokeMethod('deleteSource');
      _spiderPort = 0;
      _spiderApiBase = '';
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
    print('setCurrentSpider: key=$key, type=$type, apiBase=$apiBase');
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
      print('initSpider POST $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 10));
      print('initSpider status=${response.statusCode}');
    } catch (e) {
      print('initSpider error: $e');
    }
  }

  Future<Map<String, dynamic>> getCatConfig() async {
    if (_spiderPort <= 0) return {};
    try {
      final url = '${_spiderBaseUrl()}/config';
      print('getCatConfig GET $url');
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final videoSites = data['video']?['sites'] as List<dynamic>? ?? [];
        if (videoSites.isNotEmpty) {
          final firstSite = videoSites.first as Map<String, dynamic>;
          final api = firstSite['api'] as String? ?? '';
          if (api.isNotEmpty) {
            _spiderApiBase = api;
          }
        }
        return data;
      }
    } catch (e) {
      print('getCatConfig error: $e');
    }
    return {};
  }

  Future<Map<String, dynamic>> getHomeContent() async {
    if (_spiderPort <= 0 || (_spiderApiBase.isEmpty && _currentSpiderKey.isEmpty)) {
      return {};
    }
    try {
      final url = '${_spiderBaseUrl()}${_spiderPath()}/home';
      print('getHomeContent POST $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('getHomeContent error: $e');
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
        print('getCategoryContent POST $url (retry $retry)');
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
        print('getCategoryContent timeout (retry ${retry + 1}/3): $e');
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 1 + retry));
          continue;
        }
      } catch (e) {
        print('getCategoryContent error: $e');
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
      print('getVideoDetail POST $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': videoId}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('getVideoDetail error: $e');
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
      print('getPlayUrl POST $url');
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
      print('getPlayUrl error: $e');
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
        print('search POST $url (retry $retry)');
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
        print('search timeout (retry ${retry + 1}/3): $e');
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 1 + retry));
          continue;
        }
      } catch (e) {
        print('search error: $e');
        break;
      }
    }
    return {};
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopNodeJS');
    } catch (e) {
      print('stopNodeJS error: $e');
    }
    _isInitialized = false;
    _isNodeReady = false;
    _managementPort = 0;
    _spiderPort = 0;
    _spiderApiBase = '';
    _eventSubscription?.cancel();
  }

  @override
  void onClose() {
    stop();
    super.onClose();
  }
}