import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';

class DebugLogEntry {
  final DateTime timestamp;
  final String method;
  final String url;
  final Map<String, String>? headers;
  final String? requestBody;
  final int? statusCode;
  final String? responseBody;
  final int? responseSize;
  final int? durationMs;
  final String source;

  DebugLogEntry({
    required this.timestamp,
    required this.method,
    required this.url,
    this.headers,
    this.requestBody,
    this.statusCode,
    this.responseBody,
    this.responseSize,
    this.durationMs,
    required this.source,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'timestamp': timestamp.millisecondsSinceEpoch,
      'time': timestamp.toIso8601String(),
      'method': method,
      'url': url,
      'source': source,
    };
    if (headers != null && headers!.isNotEmpty) {
      final filtered = Map<String, String>.from(headers!);
      const sensitiveKeys = ['authorization', 'cookie', 'set-cookie'];
      for (final key in sensitiveKeys) {
        if (filtered.containsKey(key)) filtered[key] = '***';
      }
      map['headers'] = filtered;
    }
    // 请求体：限制长度（防止超大请求体）
    if (requestBody != null && requestBody!.isNotEmpty) {
      map['requestBody'] = _truncate(requestBody!, 10240); // 提高到 10KB
    }
    if (statusCode != null) map['statusCode'] = statusCode;
    // 响应体：不再截断，保留完整
    if (responseBody != null && responseBody!.isNotEmpty) {
      map['responseBody'] = responseBody;
    }
    if (responseSize != null) map['responseSize'] = responseSize;
    if (durationMs != null) map['durationMs'] = durationMs;
    return map;
  }

  static DebugLogEntry fromJson(Map<String, dynamic> json) {
    return DebugLogEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      method: json['method'] as String? ?? 'GET',
      url: json['url'] as String? ?? '',
      headers: (json['headers'] as Map?)?.cast<String, String>(),
      requestBody: json['requestBody'] as String?,
      statusCode: json['statusCode'] as int?,
      responseBody: json['responseBody'] as String?,
      responseSize: json['responseSize'] as int?,
      durationMs: json['durationMs'] as int?,
      source: json['source'] as String? ?? 'unknown',
    );
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}... (truncated, total ${text.length} chars)';
  }
}

class DebugLogService extends GetxService {
  static DebugLogService get instance => Get.find<DebugLogService>();

  final RxBool enabled = RxBool(false);
  final RxInt logCount = RxInt(0);
  final _logQueue = <DebugLogEntry>[];
  final _maxQueueSize = 50;
  Timer? _flushTimer;
  File? _logFile;
  IOSink? _sink;
  bool _isWriting = false;

  @override
  void onInit() {
    super.onInit();
    enabled.value = SettingPref.enableDebugLog;
    _initLogFile();
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) => _flush());
  }

  @override
  void onClose() {
    _flushTimer?.cancel();
    _flush();
    _sink?.close();
    super.onClose();
  }

  Future<void> _initLogFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/debug_logs');
      if (!await logDir.exists()) await logDir.create(recursive: true);
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      _logFile = File('${logDir.path}/debug_$dateStr.jsonl');
      _sink = _logFile!.openWrite(mode: FileMode.append);
      await _countLogs();
    } catch (e) {
      debugPrint('[DebugLog] init error: $e');
    }
  }

  Future<void> _countLogs() async {
    try {
      if (_logFile == null || !await _logFile!.exists()) {
        logCount.value = 0;
        return;
      }
      final lines = await _logFile!.readAsLines();
      logCount.value = lines.length;
    } catch (_) {
      logCount.value = 0;
    }
  }

  void setEnabled(bool value) {
    enabled.value = value;
    SettingPref.enableDebugLog = value;
    if (!value) _logQueue.clear();
  }

  void logRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? requestBody,
    required String source,
  }) {
    if (!enabled.value) return;
    _logQueue.add(DebugLogEntry(
      timestamp: DateTime.now(),
      method: method,
      url: url,
      headers: headers,
      requestBody: requestBody,
      source: source,
    ));
    if (_logQueue.length >= _maxQueueSize) _flush();
  }

  void logResponse({
    required String url,
    required String method,
    int? statusCode,
    String? responseBody,
    int? responseSize,
    int? durationMs,
    required String source,
  }) {
    if (!enabled.value) return;
    final now = DateTime.now();
    int? matchedIndex;
    for (int i = _logQueue.length - 1; i >= 0; i--) {
      final entry = _logQueue[i];
      if (entry.method == method &&
          entry.url == url &&
          entry.source == source &&
          entry.statusCode == null) {
        final diff = now.difference(entry.timestamp).inSeconds;
        if (diff < 10) {
          matchedIndex = i;
          break;
        }
      }
    }
    if (matchedIndex != null) {
      final entry = _logQueue[matchedIndex];
      _logQueue[matchedIndex] = DebugLogEntry(
        timestamp: entry.timestamp,
        method: entry.method,
        url: entry.url,
        headers: entry.headers,
        requestBody: entry.requestBody,
        statusCode: statusCode,
        responseBody: responseBody,
        responseSize: responseSize,
        durationMs: durationMs,
        source: entry.source,
      );
      if (_logQueue.length >= _maxQueueSize) _flush();
    } else {
      _logQueue.add(DebugLogEntry(
        timestamp: now,
        method: method,
        url: url,
        statusCode: statusCode,
        responseBody: responseBody,
        responseSize: responseSize,
        durationMs: durationMs,
        source: source,
      ));
      if (_logQueue.length >= _maxQueueSize) _flush();
    }
  }

  Future<void> _flush() async {
    if (_logQueue.isEmpty || _isWriting) return;
    _isWriting = true;
    try {
      final entries = List<DebugLogEntry>.from(_logQueue);
      _logQueue.clear();
      final sink = _sink;
      if (sink != null) {
        for (final entry in entries) {
          sink.writeln(jsonEncode(entry.toJson()));
        }
        await sink.flush();
      }
      logCount.value += entries.length;
    } catch (e) {
      debugPrint('[DebugLog] flush error: $e');
    } finally {
      _isWriting = false;
    }
  }

  Future<List<DebugLogEntry>> readLogs({int page = 0, int pageSize = 50}) async {
    try {
      if (_logFile == null || !await _logFile!.exists()) return [];
      final lines = await _logFile!.readAsLines();
      final reversed = lines.reversed.toList();
      final start = page * pageSize;
      final end = (start + pageSize).clamp(0, reversed.length);
      final result = <DebugLogEntry>[];
      for (int i = start; i < end; i++) {
        try {
          final json = jsonDecode(reversed[i]) as Map<String, dynamic>;
          result.add(DebugLogEntry.fromJson(json));
        } catch (_) {}
      }
      return result;
    } catch (e) {
      debugPrint('[DebugLog] read error: $e');
      return [];
    }
  }

  /// 修复：正确清除日志文件
  Future<void> clearLogs() async {
    _logQueue.clear();
    try {
      // 先关闭 sink
      await _sink?.close();
      _sink = null;
      
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.delete();
      }
      logCount.value = 0;
      // 重新初始化
      await _initLogFile();
    } catch (e) {
      debugPrint('[DebugLog] clear error: $e');
      // 尝试恢复
      await _initLogFile();
    }
  }

  Future<String> exportLogs() async {
    try {
      if (_logFile == null || !await _logFile!.exists()) return '[]';
      final lines = await _logFile!.readAsLines();
      final entries = <Map<String, dynamic>>[];
      for (final line in lines) {
        try {
          entries.add(jsonDecode(line) as Map<String, dynamic>);
        } catch (_) {}
      }
      return jsonEncode({
        'exportTime': DateTime.now().toIso8601String(),
        'totalCount': entries.length,
        'logs': entries,
      });
    } catch (e) {
      debugPrint('[DebugLog] export error: $e');
      return '[]';
    }
  }
}