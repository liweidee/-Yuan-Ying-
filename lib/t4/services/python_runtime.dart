// lib/t4/services/python_runtime.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show MethodChannel, Uint8List;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/utils/business_exception.dart';

/// Python 运行时管理
/// - Android：走 DsPlayer-Python-plugin APK（AIDL）
/// - 桌面端：走插件中心 python-win 插件（常驻 HTTP worker）
class PythonRuntime {
  static const _channel = MethodChannel('com.example.yuanying/pyplugin');

  static const _configChannel =
      MethodChannel('com.example.yuanying/pyplugin/config');

  // ============================================================
  // Android: AIDL 通道
  // ============================================================

  static Future<bool> androidPing() async {
    try {
      final r = await _channel.invokeMethod<String>('ping');
      final j = jsonDecode(r ?? '{}') as Map;
      return j['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 设置 py 插件保活开关（仅 Android 生效）
  /// - true：bindService 带 BIND_IMPORTANT，进程优先级提升到前台级
  /// - false：普通 BIND_AUTO_CREATE
  /// 切换后原生侧会主动 unbind，下次调用自动重连（约 100-300ms）
  static Future<void> androidSetKeepAlive(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _configChannel.invokeMethod('setKeepAlive', {'enabled': enabled});
      debugPrint('[PY-KEEPALIVE] setKeepAlive = $enabled');
    } catch (e) {
      debugPrint('[PY-KEEPALIVE] setKeepAlive 失败: $e');
    }
  }

  static Future<String?> androidLoadSource(List<int> bytes, String name) async {
    try {
      final r = await _channel.invokeMethod<String>('loadSource', {
        'bytes': Uint8List.fromList(bytes),
        'name': name,
      }).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('AIDL loadSource 超时（30s）'),
      );
      final j = jsonDecode(r ?? '{}') as Map;
      if (j['success'] == true) return j['key'] as String?;
    } on TimeoutException catch (e) {
      print('[PythonRuntime] androidLoadSource timeout: ${e.message}');
    } catch (e) {
      print('[PythonRuntime] androidLoadSource failed: $e');
    }
    return null;
  }

  static Future<String> androidCall({
    required String key,
    required String method,
    String? proxyUrl,
    List<dynamic> args = const [],
  }) async {
    final env = jsonEncode({'proxyUrl': proxyUrl ?? '', 'ext': ''});
    try {
      final r = await _channel.invokeMethod<String>('call', {
        'key': key,
        'method': method,
        'env': env,
        'args': jsonEncode(args),
      }).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('AIDL call 超时（30s）'),
      );
      return r ?? '{"success":false,"error":"empty response"}';
    } on TimeoutException catch (e) {
      return '{"success":false,"error":"${e.message}"}';
    }
  }

  static Future<void> androidUnload(String key) async {
    try {
      await _channel.invokeMethod('unloadSource', {'key': key});
    } catch (_) {}
  }

  // ============================================================
  // 桌面端：python-win 常驻 HTTP worker
  // ============================================================

  static bool get isDesktopPlatform =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static bool get isAndroid => Platform.isAndroid;

  static final Map<String, _WorkerState> _workers = {};

  static bool isDesktopRuntimeAvailable() {
    if (!isDesktopPlatform) return false;
    final reg = InstallManager.instance.findInstalled('python-win');
    if (reg == null) return false;
    final root = reg.installPath;
    final exe = File(p.join(root, 'bin', 'python.exe'));
    final script = File(p.join(root, 'bin', 'py_worker_server.py'));
    return exe.existsSync() && script.existsSync();
  }

  static Future<int> _ensureWorker() async {
    if (!isDesktopPlatform) {
      throw const BusinessException('Python worker is only supported on desktop platforms.');
    }

    final reg = InstallManager.instance.findInstalled('python-win');
    if (reg == null) {
      throw const BusinessException(
        '未安装 Python 运行时（python-win）。请前往「插件中心 → 市场」安装 python-win 插件后再使用 py 源。',
      );
    }

    final root = reg.installPath;
    final exePath = p.join(root, 'bin', 'python.exe');
    final scriptPath = p.join(root, 'bin', 'py_worker_server.py');
    if (!File(exePath).existsSync() || !File(scriptPath).existsSync()) {
      throw const BusinessException(
        'python-win 插件缺少 bin/python.exe 或 bin/py_worker_server.py，请重新安装 python-win 插件。',
      );
    }

    final existing = _workers['python-win'];
    if (existing != null) {
      final ok = await _pingWorker(existing.port);
      if (ok) return existing.port;
      _workers.remove('python-win');
      try {
        existing.process?.kill();
      } catch (_) {}
    }

    final port = await _findFreePort();
    final workingDir = p.join(root, 'bin');
    final process = await Process.start(
      exePath,
      [scriptPath, '--port', '$port'],
      workingDirectory: workingDir,
      environment: {
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
        ...Platform.environment,
      },
    );
    print('[PythonRuntime] worker started pid=${process.pid} port=$port');

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      print('[py_worker/out] $line');
    });
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      print('[py_worker/out] $line');
    });

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (await _pingWorker(port)) {
        _workers['python-win'] = _WorkerState(port: port, process: process);
        return port;
      }
    }
    try {
      process.kill();
    } catch (_) {}
    throw const BusinessException('python-win worker 启动超时（10 秒），请重试');
  }

  static Future<bool> _pingWorker(int port) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 800);
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/ping'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      if (resp.statusCode != 200) return false;
      final j = jsonDecode(body) as Map;
      return j['success'] == true && j['role'] == 'dsplayer-py-worker';
    } catch (_) {
      return false;
    }
  }

  static Future<int> _findFreePort() async {
    for (var port = 57591; port < 57611; port++) {
      try {
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await socket.close();
        return port;
      } catch (_) {}
    }
    throw const BusinessException('无可用端口（57591~57610 全部被占用）');
  }

  /// POST JSON 到 worker，返回 body 字符串
  static Future<String> _postJson(int port, String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
      req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      final bytes = utf8.encode(jsonEncode(body));
      req.contentLength = bytes.length;
      req.add(bytes);
      final resp = await req.close().timeout(const Duration(seconds: 90));
      final text = await resp.transform(utf8.decoder).join();
      return text;
    } finally {
      client.close(force: true);
    }
  }

  /// 把 apiUrl 归一化为本地文件路径
  /// - 本地绝对路径：直接返回
  /// - http(s) URL：下载到临时目录，返回临时文件路径
  static Future<String> _resolveSourcePath(String apiUrl) async {
    if (!apiUrl.startsWith('http://') && !apiUrl.startsWith('https://')) {
      // 本地路径
      if (!File(apiUrl).existsSync()) {
        throw BusinessException('py 源文件不存在: $apiUrl');
      }
      return apiUrl;
    }

    // HTTP URL：下载到临时目录
    final tempDir = await getTemporaryDirectory();
    final pyCacheDir = Directory(p.join(tempDir.path, 'py_source_cache'));
    if (!pyCacheDir.existsSync()) await pyCacheDir.create(recursive: true);

    // 用 URL 的 sha1 作为缓存文件名（去重 + 避开非法字符）
    final hash = _hashUrl(apiUrl);
    final ext = _guessExtFromUrl(apiUrl);
    final localPath = p.join(pyCacheDir.path, '$hash$ext');

    // 缓存命中：直接用
    if (File(localPath).existsSync()) {
      return localPath;
    }

    // 下载
    final dio = Dio();
    try {
      final resp = await dio.get<List<int>>(
        apiUrl,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final data = resp.data ?? <int>[];
      if (data.isEmpty) {
        throw BusinessException('下载 py 源为空: $apiUrl');
      }
      await File(localPath).writeAsBytes(data, flush: true);
      return localPath;
    } catch (e) {
      throw BusinessException('下载 py 源失败: $apiUrl → $e');
    } finally {
      dio.close();
    }
  }

  /// 公开包装：把 apiUrl 归一化为本地文件路径
  /// - 本地绝对路径：原样返回
  /// - http(s) URL：下载到临时目录，返回临时文件路径（带 sha1 缓存）
  /// 供 Py3SpiderService（Android）复用桌面端已实现的远程下载逻辑。
  static Future<String> resolveSourcePath(String apiUrl) =>
      _resolveSourcePath(apiUrl);

  static String _hashUrl(String url) {
    // 简单 hash：用 hashCode 不够稳定，用 url 的 md5 更稳
    // 避免引入 crypto 依赖，用 base64Url.encode 去重
    final bytes = utf8.encode(url);
    var hash = 0;
    for (final b in bytes) {
      hash = (hash * 31 + b) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _guessExtFromUrl(String url) {
    final path = Uri.parse(url).path.toLowerCase();
    if (path.endsWith('.py')) return '.py';
    if (path.endsWith('.pyc')) return '.pyc';
    if (path.endsWith('.so')) return '.so';
    return '.py';
  }

  /// 桌面端：调用 Python 爬虫
  /// 流程：确保 worker → 下载源（如需要）→ load_source → call
  static Future<String> desktopRunSpiderMethod(Map<String, dynamic> inputParams) async {
    if (!isDesktopPlatform) {
      throw const BusinessException('Python spider execution is only supported on desktop platforms.');
    }

    final method = inputParams['method']?.toString() ?? '';
    final apiUrl = inputParams['apiUrl']?.toString() ?? '';
    final extend = inputParams['extend']?.toString() ?? '';
    final args = inputParams['args'];
    final argsJson = jsonEncode(args ?? []);

    final port = await _ensureWorker();

    // 归一化为本地文件路径（URL 先下载）
    final localPath = await _resolveSourcePath(apiUrl);

    // 1. load_source
    final loadRaw = await _postJson(port, '/load_source', {'path': localPath});
    final loadJson = jsonDecode(loadRaw) as Map;
    if (loadJson['success'] != true) {
      throw BusinessException('py 源加载失败: ${loadJson['error'] ?? loadJson}');
    }
    final key = loadJson['key']?.toString() ?? '';
    if (key.isEmpty) {
      throw const BusinessException('py 源加载失败: 未返回 key');
    }

    // 2. call
    final env = jsonEncode({'proxyUrl': extend, 'ext': ''});
    final callRaw = await _postJson(port, '/call', {
      'key': key,
      'method': method,
      'env': env,
      'args': argsJson,
    });
    if (callRaw.isEmpty) {
      throw const BusinessException('Python 返回空结果');
    }
    return callRaw;
  }

  /// 卸载源
  static Future<void> desktopUnloadSource(String apiUrl) async {
    if (!isDesktopPlatform) return;
    final state = _workers['python-win'];
    if (state == null) return;
    try {
      final localPath = await _resolveSourcePath(apiUrl);
      final loadRaw = await _postJson(state.port, '/load_source', {'path': localPath});
      final loadJson = jsonDecode(loadRaw) as Map;
      final key = loadJson['key']?.toString() ?? '';
      if (key.isEmpty) return;
      await _postJson(state.port, '/unload_source', {'key': key});
    } catch (_) {}
  }

  /// 关闭 worker（App 退出时 / 卸载 python-win 插件时调）
  static Future<void> shutdown() async {
    // 1. 杀已知 worker
    for (final state in _workers.values) {
      try {
        state.process?.kill();
      } catch (_) {}
    }
    _workers.clear();

    // 2. Windows：扫描并杀掉所有 py_worker_server.py 进程
    //    （兜底 App 重启后 _workers 为空、旧 worker 变孤儿的情况）
    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | "
                "Where-Object { \$_.CommandLine -like '*py_worker_server.py*' } | "
                "Select-Object -ExpandProperty ProcessId",
          ],
          stdoutEncoding: const SystemEncoding(),
          stderrEncoding: const SystemEncoding(),
        ).timeout(const Duration(seconds: 5));
        final out = result.stdout.toString().trim();
        if (out.isNotEmpty) {
          final pids = out
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty && int.tryParse(s) != null);
          for (final pid in pids) {
            try {
              await Process.run(
                'taskkill',
                ['/F', '/PID', pid],
                stdoutEncoding: const SystemEncoding(),
                stderrEncoding: const SystemEncoding(),
              );
              print('[PythonRuntime] killed orphan worker pid=$pid');
            } catch (_) {}
          }
        }
      } catch (e) {
        print('[PythonRuntime] scan orphan workers failed: $e');
      }
    }
  }

  static void reset() {}
  static void dispose() {
    shutdown();
  }
}

class _WorkerState {
  final int port;
  final Process? process;

  _WorkerState({required this.port, this.process});
}