import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/services/catvod_log_service.dart';

class NodeJSService extends GetxService with WidgetsBindingObserver {
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
  String _currentConfigType = 'tvbox'; // 当前配置类型
  void updateConfigType(String type) {  // 供外部更新配置类型
    _currentConfigType = type;
  }
  String? get lastLoadedUrl => _lastLoadedUrl;
  bool _isRestarting = false;
  late CatVodLogService _logService;

  // ============ 桌面端专属字段（移动端不会访问） ============
  Process? _nodeProcess;
  HttpServer? _localNotifyServer;

  /// 可执行文件所在目录（仅桌面端有意义）
  String get _exeDir => File(Platform.resolvedExecutable).parent.path;
  String get _nodeExePath => '$_exeDir/nodejs/runtime/node.exe';

  /// 入口脚本路径，优先 main.js，兜底 index.js（与 iOS NodeJSManager.m 一致）
  String get _scriptPath {
    final mainJs = '$_exeDir/nodejs/project/dist/main.js';
    if (File(mainJs).existsSync()) return mainJs;
    return '$_exeDir/nodejs/project/dist/index.js';
  }

  /// 桌面端保活/关闭状态（移动端不会访问）
  bool _isShuttingDown = false;                    // 应用是否正在关闭（用户主动退出）
  int _restartCount = 0;                           // 本会话已重启次数（只加不减，上限 1）
  static const int _maxRestartPerSession = 1;      // 本会话最多重启 1 次，结构上杜绝循环
  // ============ 桌面端字段结束 ============

  String _spiderBaseUrl() => 'http://127.0.0.1:$_spiderPort';
  String _spiderPath() {
    if (_spiderApiBase.isNotEmpty) return _spiderApiBase;
    return '/$_currentSpiderKey/$_currentSpiderType';
  }

  void _setupEventListener() {
    try {
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
    } catch (e) {
      _log('EventChannel setup failed (platform may not support it): $e');
    }
  }

  void _log(String msg) {
    _logService.addLog(msg);
    debugPrint(msg);
  }

  @override
  Future<void> onInit() async {
    super.onInit();
    _logService = Get.find<CatVodLogService>();

    // 桌面端不支持猫影视，不需要监听 EventChannel
    if (!PlatformUtils.isDesktop) {
      _setupEventListener();
    }

    WidgetsBinding.instance.addObserver(this); // 注册生命周期监听
    // 不在启动时自动初始化，等需要时再初始化
  }

  // 自治保活：App 回到前台时检查
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 桌面端无需保活：Node 子进程退出由 exitCode 回调感知
    if (PlatformUtils.isDesktop) return;
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  void _onAppResumed() async {
    // 只有当前配置是猫影视，且曾经加载过源，才需要保活
    if (_lastLoadedUrl == null || _lastLoadedUrl!.isEmpty) return;
    // 使用内部变量判断，不再依赖 SourceManager
    if (_currentConfigType != 'catvod') return; // 非猫影视，不保活
    if (_isRestarting) return;

    // 延迟 1 秒再检查，等 UI 稳定
    await Future.delayed(const Duration(seconds: 1));
    if (_isRestarting) return;

    // 检查服务是否健康
    if (_spiderPort > 0) {
      final alive = await isServiceAlive();
      if (alive) return; // 活着，不用管
    }

    // 服务不可用，安全重启
    _log('App resumed, Node.js needs restart');
    await reinitialize();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    // 如果端口还在，说明 Node.js 还在运行（stop 只清了 Dart 状态）
    // 直接恢复 _isInitialized，不调用 startNodeJS，避免二次 node_start 闪退
    // 桌面端额外确认进程句柄未丢失
    if (_managementPort > 0 &&
        (!PlatformUtils.isDesktop || _nodeProcess != null)) {
      _isInitialized = true;
      if (!PlatformUtils.isDesktop) {
        _setupEventListener();
      }
      _log('initialize: restored from existing port $_managementPort');
      return;
    }

    // 桌面端分发：进程句柄丢失或首次启动 → 走桌面端流程
    if (PlatformUtils.isDesktop) {
      _managementPort = 0;
      _spiderPort = 0;
      return _initializeDesktop();
    }

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
      if (_managementPort == 0) {
        _log('Node.js initialization completed but managementPort is 0, resetting state');
        _isInitialized = false;
      }
    } catch (e) {
      _log('Node.js initialization error: $e');
      _isInitialized = false;
    }
  }

  Future<bool> loadSourceFromURL(String url) async {
    // 桌面端分发：下载逻辑改由 Dart 侧执行
    if (PlatformUtils.isDesktop) {
      return _loadSourceFromURLDesktop(url);
    }

    // 先保存旧 URL，加载成功后再更新
    final previousUrl = _lastLoadedUrl;
    _lastLoadedUrl = url;

    if (!_isInitialized) {
      await initialize();
    }
    if (_managementPort == 0) {
      _log('managementPort is 0, waiting...');
      _managementPortCompleter ??= Completer<void>();
      final timer = Timer(const Duration(seconds: 5), () {
        if (!_managementPortCompleter!.isCompleted) {
          _managementPortCompleter!.complete();
          _log('managementPort wait timeout');
        }
      });
      await _managementPortCompleter!.future;
      timer.cancel();
      if (_managementPort == 0) {
        _log('managementPort still 0, cannot load source');
        _lastLoadedUrl = previousUrl;  // 恢复旧 URL
        return false;
      }
    }
    try {
      _log('loadSourceFromURL: $url');
      final result = await _channel
          .invokeMethod('loadSourceFromURL', {'url': url})
          .timeout(const Duration(seconds: 30));
      _log('loadSourceFromURL result: $result');
      if (result is Map && result['success'] == true) {
        // 等待 Spider Server 真正就绪（轮询探活，最多 5s）
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_spiderPort > 0) {
            final alive = await isServiceAlive();
            if (alive) {
              _log('Spider Server ready after loadSource');
              return true;
            }
          }
        }
        _log('Spider Server not ready after 5s, loadSource failed');
        _lastLoadedUrl = previousUrl;
        return false;
      }
      _lastLoadedUrl = previousUrl;
      return false;
    } on TimeoutException {
      _log('loadSourceFromURL timeout 30s, url: $url');
      _lastLoadedUrl = previousUrl;
      return false;
    } on PlatformException catch (e) {
      _log('PlatformException: ${e.message}');
      _lastLoadedUrl = previousUrl;
      return false;
    } catch (e) {
      _log('loadSourceFromURL error: $e');
      _lastLoadedUrl = previousUrl;
      return false;
    }
  }

  /// 设置最后加载的 URL（用于状态标记）
  void setLastLoadedUrl(String? url) {
    _lastLoadedUrl = url;
    _log('lastLoadedUrl 设置为: $url');
  }

  /// 获取默认CatVod爬虫源目录
  Future<String> getDefaultSourcePath() async {
    // 桌面端使用 Application Support（%APPDATA%），可写且不污染用户文档
    if (PlatformUtils.isDesktop) {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}/nodejs-project/src/source';
    }
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/nodejs-project/src/source';
  }

  /// 强制重新加载本地目录中的爬虫源（不下载，不校验 MD5）
  /// 用于本地 ZIP 切换后的刷新
  Future<bool> reloadLocalSpider() async {
    if (_managementPort <= 0) {
      await initialize();
      if (_managementPort <= 0) {
        _log('❌ reloadLocalSpider: managementPort 不可用');
        return false;
      }
    }

    final sourcePath = await getDefaultSourcePath();
    _log('🔄 强制重载本地源，路径: $sourcePath');

    final url = 'http://127.0.0.1:$_managementPort/source/loadPath';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'path': sourcePath}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        _log('✅ 本地源重载成功');
        return true;
      } else {
        _log('❌ 重载失败，状态码: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _log('❌ reloadLocalSpider 异常: $e');
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
    _log('🔄 检查 Node.js 服务状态...');
    try {
      // 桌面端：直接杀进程重启，无需"重启 App"
      if (PlatformUtils.isDesktop) {
        _log('🔄 重启桌面端 Node 子进程');
        try {
          await _nodeProcess?.kill();
        } catch (_) {}
        _nodeProcess = null;
        _isInitialized = false;
        _isNodeReady = false;
        _managementPort = 0;
        _spiderPort = 0;
        await _initializeDesktop();
        if (_lastLoadedUrl != null && _lastLoadedUrl!.isNotEmpty) {
          await loadSourceFromURL(_lastLoadedUrl!);
        }
        return;
      }

      // 检查服务是否还活着
      if (_spiderPort > 0) {
        final alive = await isServiceAlive();
        if (alive) {
          _log('✅ 服务仍然存活，重新加载源...');
          // 只重新加载源，不重启线程
          if (_lastLoadedUrl != null && _lastLoadedUrl!.isNotEmpty) {
            final loaded = await loadSourceFromURL(_lastLoadedUrl!);
            if (loaded) {
              _log('✅ 源重载成功');
            } else {
              _log('❌ 源重载失败，需重启 App');
              _showFatalError();
            }
          }
          return;
        }
      }
      // 服务已死，无法在进程内重启
      _log('❌ Node.js 服务已停止，无法在进程内重启（需重启 App）');
      _showFatalError();
    } catch (e) {
      _log('❌ reinitialize 异常: $e');
      _showFatalError();
    } finally {
      _isRestarting = false;
    }
  }

  void _showFatalError() {
    _log('⚠️ Node.js 服务不可用，需重启 App 以恢复');
  }

  Future<bool> deleteSource() async {
    // 桌面端：直接删源目录
    if (PlatformUtils.isDesktop) {
      try {
        final sourceDir = await getDefaultSourcePath();
        final dir = Directory(sourceDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
        _spiderPort = 0;
        _spiderApiBase = '';
        _lastLoadedUrl = null;
        _log('桌面端源已删除');
        return true;
      } catch (e) {
        _log('deleteSource error: $e');
        return false;
      }
    }

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
        _log('getCatConfig attempt ${i + 1} failed: $e');
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
    _isInitialized = false;
    _isNodeReady = false;
    _spiderApiBase = '';
    // 保留 _managementPort、_spiderPort、_lastLoadedUrl
    // 切回猫影视时可用于探活和复用，避免重新加载源
    // 桌面端无 EventChannel；_nodeProcess 也保留（进程继续运行，便于快速复用）
    if (!PlatformUtils.isDesktop) {
      _eventSubscription?.cancel();
    }
    _log('Node.js service stopped (Dart layer only, ports kept)');
  }

  /// 应用关闭时调用：真正停止 Node 子进程（区别于 stop() 只清 Dart 状态）
  /// 先设置 _isShuttingDown 后，exitCode 回调不会触发重启
  /// 未启动过 Node 时也安全：所有字段均为 null-safe 访问
  Future<void> shutdown() async {
    if (!PlatformUtils.isDesktop) return;
    // 先设置标志，保证即使后续任何步骤失败，也不会触发重启
    _isShuttingDown = true;
    try {
      _log('应用关闭中，准备停止 Node 子进程');
    } catch (_) {}

    // 关闭本地通知服务器
    try {
      await _localNotifyServer?.close(force: true);
    } catch (_) {}
    _localNotifyServer = null;

    // 强杀 node 子进程，并等待其真正退出（避免 Dart VM 先退出导致 node 变孤儿）
    final proc = _nodeProcess;
    if (proc != null) {
      try {
        // 1) 先发 SIGTERM，给 node 一点时间优雅退出
        proc.kill();
      } catch (_) {}
      try {
        // 2) 最多等 2 秒
        await proc.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            // 3) 超时则强制 TerminateProcess
            try {
              proc.kill(ProcessSignal.sigkill);
            } catch (_) {}
            return -1;
          },
        );
      } catch (_) {
        // exitCode 可能因为各种原因抛异常，忽略
      }
    }
    // 不置空 _nodeProcess，让 exitCode 回调自己清理状态
  }

  // ==================================================================
  //                       桌面端专属实现
  // ==================================================================

  Future<void> _initializeDesktop() async {
    _log('🚀 桌面端初始化 Node.js...');

    // 启动前先清理上次残留的孤儿 Node 进程（避免端口冲突 / 文件占用）
    await _killOrphanNodeProcesses();

    // 1) 确保通知服务器已就绪（复用已有实例，避免重启时泄漏）
    final nativePort = await _ensureNotifyServer();
    if (nativePort == null) return;

    // 2) 校验二进制存在性
    if (!File(_nodeExePath).existsSync()) {
      _log('❌ 找不到 node.exe: $_nodeExePath');
      return;
    }
    final scriptPath = _scriptPath;
    if (!File(scriptPath).existsSync()) {
      _log('❌ 找不到入口脚本: $scriptPath');
      return;
    }

    // 3) 准备 Completer
    _readyCompleter = Completer<void>();
    _managementPortCompleter = Completer<void>();

    // 4) 启动子进程
    try {
      final sourceDir = await getDefaultSourcePath();
      await Directory(sourceDir).create(recursive: true);

      _nodeProcess = await Process.start(
        _nodeExePath,
        [scriptPath, '--native-port', '$nativePort'],
        workingDirectory: '$_exeDir/nodejs/project',
        environment: {
          ...Platform.environment,
          'NODE_PATH': sourceDir,
        },
      );
      _isInitialized = true;
      _log('Node 进程已启动, PID=${_nodeProcess!.pid}');
    } catch (e) {
      _log('❌ 启动 Node 进程失败: $e');
      _isInitialized = false;
      return;
    }

    // 5) 持续消费 stdout / stderr（Dart 强制要求，否则子进程会僵死）
    _nodeProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _log('[node] $line'));

    _nodeProcess!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _log('[node:err] $line'));

    // 6) 进程退出回调
    // 三层防护：
    //   a) _nodeProcess 比较（防止旧进程回调误触）
    //   b) _isShuttingDown（用户主动关闭，不重启）
    //   c) _restartCount 上限（本会话最多重启 1 次，结构上杜绝循环）
    final startedProcess = _nodeProcess!;
    startedProcess.exitCode.then((code) {
      if (_nodeProcess != startedProcess) return;
      _log('⚠️ Node 进程退出, code=$code');

      // 清理状态
      _isInitialized = false;
      _isNodeReady = false;
      _managementPort = 0;
      _spiderPort = 0;
      _nodeProcess = null;

      // 用户主动关闭 → 不重启
      if (_isShuttingDown) {
        _log('应用关闭中，不重启 Node');
        return;
      }

      // 已达本会话重启上限 → 不重启
      if (_restartCount >= _maxRestartPerSession) {
        _log('⚠️ 本会话已重启 $_restartCount 次，不再重启（如需恢复请重启应用）');
        return;
      }

      // 触发一次重启
      _restartCount++;
      _log('🔄 尝试第 $_restartCount 次重启');
      _handleProcessCrashOnce();
    });

    // 7) 等待 ready + management 端口（带超时，避免卡死）
    try {
      await _readyCompleter!.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => _log('⚠️ ready 信号超时'),
      );
      await _managementPortCompleter!.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => _log('⚠️ managementPort 超时'),
      );
      _log('✅ 桌面端 Node.js 初始化完成, '
          'mgmt=$_managementPort, spider=$_spiderPort');
    } catch (e) {
      _log('初始化等待异常: $e');
    }
  }

  /// 确保本地通知服务器已启动，返回其端口。
  /// 已存在则直接复用（重启场景），避免每次都创建新的 HttpServer。
  /// 启动失败返回 null。
  Future<int?> _ensureNotifyServer() async {
    // 已存在 → 复用
    if (_localNotifyServer != null) {
      _log('复用已有通知服务器端口: ${_localNotifyServer!.port}');
      return _localNotifyServer!.port;
    }

    // 首次启动（替代 iOS 的 GCDWebServer）
    try {
      _localNotifyServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } catch (e) {
      _log('❌ 本地通知服务器启动失败: $e');
      return null;
    }
    final port = _localNotifyServer!.port;
    _log('本地通知服务器监听端口: $port');

    _localNotifyServer!.listen((req) async {
      try {
        if (req.uri.path == '/onCatPawOpenPort') {
          final port = int.tryParse(req.uri.queryParameters['port'] ?? '');
          final type = req.uri.queryParameters['type'] ?? 'spider';
          if (port != null) {
            if (type == 'management') {
              _managementPort = port;
              if (_managementPortCompleter != null &&
                  !_managementPortCompleter!.isCompleted) {
                _managementPortCompleter!.complete();
              }
            } else {
              _spiderPort = port;
              if (_spiderPortCompleter != null &&
                  !_spiderPortCompleter!.isCompleted) {
                _spiderPortCompleter!.complete();
              }
            }
            _log('端口已接收: $port ($type)');
          }
        } else if (req.uri.path == '/onMessage') {
          final body = await utf8.decoder.bind(req).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          if (data['message'] == 'ready') {
            _isNodeReady = true;
            if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
              _readyCompleter!.complete();
            }
            _log('Node.js ready 信号已收到');
          }
        }
        req.response.statusCode = 200;
        req.response.write('OK');
        await req.response.close();
      } catch (e) {
        _log('通知服务器处理异常: $e');
        try {
          req.response.statusCode = 500;
          await req.response.close();
        } catch (_) {}
      }
    });

    return port;
  }

  /// 清理命令行包含 nodejs/project/dist 三段关键词的 node.exe 孤儿进程
  /// 只杀自己的，绝不误伤用户开发环境里的其他 node.exe
  Future<void> _killOrphanNodeProcesses() async {
    if (!Platform.isWindows) return;
    try {
      // 用 PowerShell 查询所有 node.exe 的命令行和 PID
      // 匹配模式：nodejs + project + dist 三段关键词同时出现
      // 注意：PowerShell -like 里 \ 不是特殊字符，不要转义；用 * 作为通配符
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '''
\$targets = Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { \$_.CommandLine -and \$_.CommandLine -like '*nodejs*project*dist*' } |
  Select-Object -ExpandProperty ProcessId;
if (\$targets) {
  \$targets | ForEach-Object { Stop-Process -Id \$_ -Force -ErrorAction SilentlyContinue };
  Write-Output (\$targets -join ',')
} else {
  Write-Output ''
}
''',
        ],
      ).timeout(const Duration(seconds: 5));

      final killed = result.stdout.toString().trim();
      if (killed.isNotEmpty) {
        _log('🧹 已清理孤儿 Node 进程 PID: $killed');
      }
    } catch (e) {
      // 清理失败不阻断主流程
      _log('孤儿进程清理失败（忽略）: $e');
    }
  }

  Future<bool> _loadSourceFromURLDesktop(String url) async {
    final previousUrl = _lastLoadedUrl;
    _lastLoadedUrl = url;

    if (!_isInitialized) await initialize();

    // 等待 managementPort 就绪
    if (_managementPort == 0) {
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_managementPort > 0) break;
      }
      if (_managementPort == 0) {
        _log('❌ managementPort 未就绪，无法加载源');
        _lastLoadedUrl = previousUrl;
        return false;
      }
    }

    // 归一化 URL（去掉 .md5 后缀）
    var normalizedUrl = url;
    if (normalizedUrl.endsWith('.js.md5')) {
      normalizedUrl =
          normalizedUrl.substring(0, normalizedUrl.length - 4);
    }

    final sourceDir = await getDefaultSourcePath();
    final indexJs = File('$sourceDir/index.js');
    final indexMd5 = File('$sourceDir/index.js.md5');

    // 1) MD5 缓存命中检查（对标 NodeJSManager.m）
    if (await indexJs.exists() && await indexMd5.exists()) {
      try {
        final remoteMd5Resp = await http
            .get(Uri.parse('$normalizedUrl.md5'))
            .timeout(const Duration(seconds: 10));
        if (remoteMd5Resp.statusCode == 200) {
          final remoteMd5 = remoteMd5Resp.body.trim();
          final localMd5 = (await indexMd5.readAsString()).trim();
          if (remoteMd5.isNotEmpty && remoteMd5 == localMd5) {
            _log('✅ MD5 命中，使用缓存源');
            final ok = await _postLoadPathToNode(sourceDir);
            if (!ok) _lastLoadedUrl = previousUrl;
            return ok;
          }
        } else if (remoteMd5Resp.statusCode == 404) {
          _log('远端 MD5 404，使用缓存源');
          final ok = await _postLoadPathToNode(sourceDir);
          if (!ok) _lastLoadedUrl = previousUrl;
          return ok;
        }
      } catch (e) {
        _log('MD5 检查失败: $e');
      }
    }

    // 2) 下载主源
    try {
      _log('下载主源: $normalizedUrl');
      final resp = await http
          .get(Uri.parse(normalizedUrl))
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) {
        _log('❌ 下载源失败: ${resp.statusCode}');
        _lastLoadedUrl = previousUrl;
        return false;
      }

      // 3) MD5 校验
      try {
        final md5Resp = await http
            .get(Uri.parse('$normalizedUrl.md5'))
            .timeout(const Duration(seconds: 10));
        if (md5Resp.statusCode == 200) {
          final expected = md5Resp.body.trim();
          final actual = crypto.md5.convert(resp.bodyBytes).toString();
          if (expected.isNotEmpty && expected != actual) {
            _log('❌ MD5 校验失败');
            _lastLoadedUrl = previousUrl;
            return false;
          }
          await Directory(sourceDir).create(recursive: true);
          await indexMd5.writeAsString(expected);
        }
      } catch (_) {}

      // 4) 写盘
      await Directory(sourceDir).create(recursive: true);
      await indexJs.writeAsBytes(resp.bodyBytes, flush: true);
      _log('✅ 源已保存到 $sourceDir');

      // 5) 通知 Node 加载
      final ok = await _postLoadPathToNode(sourceDir);
      if (!ok) _lastLoadedUrl = previousUrl;
      return ok;
    } catch (e) {
      _log('❌ 加载源异常: $e');
      _lastLoadedUrl = previousUrl;
      return false;
    }
  }

  Future<bool> _postLoadPathToNode(String path) async {
    if (_managementPort <= 0) {
      _log('❌ managementPort 为 0，无法通知 Node');
      return false;
    }
    try {
      final r = await http.post(
        Uri.parse('http://127.0.0.1:$_managementPort/source/loadPath'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'path': path}),
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        _log('✅ Node 已加载源');
        return true;
      }
      _log('❌ Node 加载源失败: ${r.statusCode}');
      return false;
    } catch (e) {
      _log('postLoadPath 异常: $e');
      return false;
    }
  }

  /// 崩溃后重启一次（受 _maxRestartPerSession 约束，结构上不可能循环）
  Future<void> _handleProcessCrashOnce() async {
    // 延迟 2 秒，给系统释放 Node 资源的时间
    await Future.delayed(const Duration(seconds: 2));

    // 延迟期间的多重保护
    if (_isShuttingDown) {
      _log('应用已关闭，取消重启');
      return;
    }
    if (_nodeProcess != null) {
      _log('延迟期间已有新进程启动，跳过本次重启');
      return;
    }
    if (_currentConfigType != 'catvod') {
      _log('已切离猫影视配置，取消重启');
      return;
    }

    _log('🔄 开始重启 Node 子进程');
    try {
      await _initializeDesktop();
    } catch (e) {
      _log('重启异常: $e');
      return;
    }

    if (_isInitialized && _managementPort > 0) {
      _log('✅ Node 重启成功');
      // 静默恢复源，不刷新 UI
      await _restoreSourceAfterRestart();
    } else {
      _log('❌ Node 重启失败，本会话不再重试');
    }
  }

  /// 重启成功后恢复上次加载的源（静默，不刷新 UI）
  Future<void> _restoreSourceAfterRestart() async {
    if (_lastLoadedUrl == null || _lastLoadedUrl!.isEmpty) return;

    _log('🔄 重启后恢复源: $_lastLoadedUrl');
    try {
      if (_lastLoadedUrl == 'local_zip') {
        await reloadLocalSpider();
      } else {
        await loadSourceFromURL(_lastLoadedUrl!);
      }
    } catch (e) {
      _log('恢复源失败: $e');
    }
  }

  /// 诊断蜘蛛源（调试专用）
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

    // 辅助日志
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
    WidgetsBinding.instance.removeObserver(this);
    stop();
    super.onClose();
  }
}