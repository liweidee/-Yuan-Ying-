import 'dart:io';

/// qjs_ultra 平台分流辅助
///
/// 判定逻辑：
///   - Windows：始终支持
///   - Android：所有 ABI 都支持（4 种架构的 .so 已内嵌）
///   - iOS/macOS：不支持，走 legacy 方案
class QjsPlatformHelper {
  /// 当前平台是否使用 qjs_ultra 引擎
  static bool get isSupported =>
      Platform.isAndroid || Platform.isWindows;

  /// 动态库名称
  static String get libPath {
    if (Platform.isAndroid) return 'libquickjs_bridge.so';
    if (Platform.isWindows) return 'quickjs_bridge.dll';
    throw UnsupportedError('qjs_ultra 不支持当前平台');
  }

  /// 日志用的引擎名称
  static String get engineName => isSupported ? 'qjs_ultra' : 'legacy';
}