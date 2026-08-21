import 'dart:io';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class CatVodLogService extends GetxService {
  static const int maxLines = 2000;
  final RxList<String> logs = <String>[].obs;
  final RxInt logCount = 0.obs;
  File? _logFile;
  bool _initialized = false;

  Future<CatVodLogService> init() async {
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

  Future<void> _initLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/catvod_log');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    _logFile = File('${logDir.path}/catvod.log');
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

  Future<void> addLog(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $message';
    logs.add(line);
    logCount.value = logs.length;
    if (logs.length > maxLines) {
      logs.removeRange(0, logs.length - maxLines);
    }
    await _writeLogsToFile();
  }

  Future<void> _writeLogsToFile() async {
    if (_logFile == null) return;
    try {
      await _logFile!.writeAsString(logs.join('\n') + '\n');
    } catch (e) {
      debugPrint('写入猫影视日志失败: $e');
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