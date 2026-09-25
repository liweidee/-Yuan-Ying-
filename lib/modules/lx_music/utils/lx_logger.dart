import 'package:flutter/foundation.dart';

/// 洛雪音乐调试日志类型
enum LxDebugLogType { info, warn, error }

/// 单条日志
class LxDebugLog {
  final DateTime time;
  final LxDebugLogType type;
  final String message;

  LxDebugLog({
    required this.time,
    required this.type,
    required this.message,
  });

  @override
  String toString() {
    final prefix = switch (type) {
      LxDebugLogType.info => 'INFO',
      LxDebugLogType.warn => 'WARN',
      LxDebugLogType.error => 'ERR ',
    };
    final t = time;
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return '[$timeStr][$prefix] $message';
  }
}

/// 洛雪音乐日志收集器
///
/// - 内存保留最近 500 条，供调试弹窗读取
/// - 通过 [globalSink] 可挂接全局日志服务（如 SystemLogService）
class LxLogger {
  LxLogger._();

  static const int _maxLogs = 500;

  static final List<LxDebugLog> _logs = [];

  /// 全局日志出口（可选注入，避免强依赖）
  static void Function(String tag, String message)? globalSink;

  static List<LxDebugLog> get logs => List.unmodifiable(_logs);

  static void log(String message, {LxDebugLogType type = LxDebugLogType.info}) {
    final log = LxDebugLog(
      time: DateTime.now(),
      type: type,
      message: message,
    );
    _logs.add(log);
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }
    if (kDebugMode) {
      debugPrint('[LxMusic] $message');
    }
    try {
      globalSink?.call('LxMusic', message);
    } catch (_) {}
  }

  static void info(String message) => log(message);

  static void warn(String message) =>
      log(message, type: LxDebugLogType.warn);

  static void error(String message) =>
      log(message, type: LxDebugLogType.error);

  static String get text => _logs.map((l) => l.toString()).join('\n');

  static void clear() => _logs.clear();
}