import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

/// 通用系统日志服务
///
/// 用途：
///   - 记录广告过滤、代理、播放器、网络等模块的运行日志
///   - 与 [CatVodLogService] 独立，互不干扰
///
/// 注意：
///   - 只有 [SettingPref.enableDebugLog] 开启时才会写入
///   - 由调用方（如 AdBlockProxy）主动调用 [addLog]
class SystemLogService extends GetxService {
  static const int maxLines = 2000;

  final RxList<String> logs = <String>[].obs;
  final RxInt logCount = 0.obs;

  File? _logFile;
  bool _initialized = false;
  bool _enabled = false;

  Future<SystemLogService> init() async {
    if (_initialized) return this;
    await _initLogFile();
    await _loadLogs();
    _initialized = true;
    return this;
  }

  @override
  Future<void> onInit() async {
    super.onInit();
    await init();
  }

  /// 由外部（如 main.dart / 设置页）同步开关状态
  void setEnabled(bool value) {
    _enabled = value;
  }

  bool get isEnabled => _enabled;

  Future<void> _initLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/system_log');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    _logFile = File('${logDir.path}/system.log');
    if (!await _logFile!.exists()) {
      await _logFile!.create();
    }
  }

  Future<void> _loadLogs() async {
    if (_logFile == null) return;
    try {
      final content = await _logFile!.readAsString();
      final lines = content.split('\n').where((l) => l.isNotEmpty).toList();
      logs.assignAll(lines);
      logCount.value = lines.length;
    } catch (e) {
      logs.clear();
      logCount.value = 0;
    }
  }

  /// 添加日志（仅在开关开启时写入）
  Future<void> addLog(String message, {String tag = 'INFO'}) async {
    if (!_enabled) return;

    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp][$tag] $message';
    logs.add(line);
    logCount.value = logs.length;

    if (logs.length > maxLines) {
      logs.removeRange(0, logs.length - maxLines);
    }
    await _writeLogsToFile();
  }

  /// 便捷方法
  Future<void> info(String message) => addLog(message, tag: 'INFO');
  Future<void> warn(String message) => addLog(message, tag: 'WARN');
  Future<void> error(String message) => addLog(message, tag: 'ERROR');
  Future<void> debug(String message) => addLog(message, tag: 'DEBUG');

  Future<void> _writeLogsToFile() async {
    if (_logFile == null) return;
    try {
      await _logFile!.writeAsString(logs.join('\n') + '\n');
    } catch (e) {
      debugPrint('写入系统日志失败: $e');
    }
  }

  Future<void> clearLogs() async {
    logs.clear();
    logCount.value = 0;
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  }

  String getAllLogsText() {
    return logs.join('\n');
  }

  String? get logFilePath => _logFile?.path;
}