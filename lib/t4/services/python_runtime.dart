import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

/// Python 运行时管理类
/// 负责解压嵌入式 Python 环境，并通过子进程调用 Python 脚本
/// 注意：仅支持桌面端（Windows / macOS / Linux），移动端不支持
class PythonRuntime {
  static bool _deployed = false;
  static Completer<void>? _deployLock;

  /// 判断当前平台是否支持 Python 子进程
  /// 桌面端支持，移动端不支持（无法运行外部可执行文件）
  static bool get isSupportedPlatform {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 获取端口（仅为满足接口要求，实际未使用）
  /// 桌面端返回一个固定端口，移动端抛出异常
  static Future<int> getPort() async {
    if (!isSupportedPlatform) {
      throw Exception('Python runtime is not supported on this platform.');
    }
    await _ensureDeployed();
    return 80;  // 固定值，仅供占位
  }

  /// 安全构建跨平台路径
  static String _safePath(List<String> segments) {
    return segments.join(Platform.pathSeparator);
  }

  /// 确保 Python 环境已解压到临时目录
  /// 仅桌面端执行，移动端调用会抛出异常
  static Future<void> _ensureDeployed() async {
    // 平台检查
    if (!isSupportedPlatform) {
      throw Exception('Python environment deployment is only supported on desktop platforms.');
    }

    if (_deployed) return;
    if (_deployLock != null) return _deployLock!.future;

    _deployLock = Completer<void>();

    try {
      final tempDir = await getTemporaryDirectory();
      final binDirPath = _safePath([tempDir.path, 'python_runtime_core']);
      final binDir = Directory(binDirPath);
      final pythonExePath = _safePath([binDirPath, 'python.exe']);
      final pythonExeFile = File(pythonExePath);

      // 如果 python.exe 不存在，则解压
      if (!await pythonExeFile.exists()) {
        print('[PythonRuntime] 正在解压 Python 环境...');
        if (await binDir.exists()) await binDir.delete(recursive: true);
        await binDir.create(recursive: true);

        // 从 assets 加载 python_env.zip
        final bytes = await rootBundle.load('assets/python/python_env.zip');
        final archive = ZipDecoder().decodeBytes(bytes.buffer.asUint8List());

        // 解压所有文件到目标目录
        for (final file in archive) {
          final filename = file.name;
          if (file.isFile) {
            final normalizedFileName = filename.replaceAll('/', Platform.pathSeparator);
            final outFile = File(_safePath([binDir.path, normalizedFileName]));
            await outFile.create(recursive: true);
            await outFile.writeAsBytes(file.content as List<int>);
          } else {
            final normalizedDirName = filename.replaceAll('/', Platform.pathSeparator);
            await Directory(_safePath([binDir.path, normalizedDirName])).create(recursive: true);
          }
        }

        print('[PythonRuntime] Python 环境解压完成');
      }

      _deployed = true;
      _deployLock!.complete();
    } catch (e) {
      // 如果解压失败，重置锁，允许后续重试
      final temp = _deployLock;
      _deployLock = null;
      if (temp != null && !temp.isCompleted) temp.completeError(e);
      rethrow;
    }
  }

  /// 核心入口：调用 Python 爬虫脚本
  /// 参数 inputParams 为 Map，将被序列化为 JSON 传递给 Python
  /// 返回 Python 脚本输出的纯净 JSON 字符串（已提取）
  static Future<String> runSpiderMethod(Map<String, dynamic> inputParams) async {
    // 平台检查：移动端直接抛出异常
    if (!isSupportedPlatform) {
      throw Exception('Python spider execution is only supported on desktop platforms.');
    }

    await _ensureDeployed();

    try {
      final tempDir = await getTemporaryDirectory();
      final binDirPath = _safePath([tempDir.path, 'python_runtime_core']);

      final pythonExePath = _safePath([binDirPath, 'python.exe']);
      final runnerPath = _safePath([binDirPath, 'scripts', 'spider_runner.py']);
      final workingDir = binDirPath;
      final pyDataDir = _safePath([tempDir.path, 'py_data']);

      final String rawJsonStr = json.encode(inputParams);

      // 启动子进程，强制使用 UTF-8 编码避免 Windows GBK 问题
      final ProcessResult result = await Process.run(
        pythonExePath,
        [runnerPath, rawJsonStr],
        workingDirectory: workingDir,
        environment: {
          'PYTHON_DATA_DIR': pyDataDir,
          'PYTHONIOENCODING': 'utf-8',   // 强制 Python 使用 UTF-8
          'PYTHONUTF8': '1',             // 启用 Python 的 UTF-8 模式
          ...Platform.environment,
        },
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      );

      final String stdoutText = result.stdout.toString().trim();
      final String stderrText = result.stderr.toString().trim();

      // 如果有 Python 异常堆栈，打印并抛出
      if (stderrText.isNotEmpty && stderrText.contains('Traceback')) {
        print('[PythonRuntime] Python 错误输出: $stderrText');
        throw Exception('Python internal crash: $stderrText');
      }

      if (stdoutText.isEmpty) {
        throw Exception('Python 进程未输出任何内容');
      }

      // 防御性提取 JSON：寻找最后出现的 {"success": ...} 模式
      final int jsonStartIndex = stdoutText.lastIndexOf('{"success":');
      final int jsonEndIndex = stdoutText.lastIndexOf('}');

      if (jsonStartIndex == -1 || jsonEndIndex == -1 || jsonEndIndex < jsonStartIndex) {
        // 如果找不到标准模式，尝试提取第一个 '{' 到最后一个 '}'
        final int fallbackStart = stdoutText.indexOf('{');
        if (fallbackStart != -1) {
          return stdoutText.substring(fallbackStart);
        }
        // 否则返回原始输出（可能不是 JSON，但由上层处理）
        return stdoutText;
      }

      // 提取纯净 JSON 并返回
      final String cleanPureJson = stdoutText.substring(jsonStartIndex, jsonEndIndex + 1);
      return cleanPureJson;
    } catch (e) {
      print('[PythonRuntime] 执行失败: $e');
      rethrow;
    }
  }

  /// 重置状态（空实现，保留接口）
  static void reset() {}

  /// 释放资源（空实现，保留接口）
  static void dispose() {}
}