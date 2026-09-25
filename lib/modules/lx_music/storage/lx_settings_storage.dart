import 'package:shared_preferences/shared_preferences.dart';

/// 洛雪音乐设置存储（用 SharedPreferences）
class LxSettingsStorage {
  LxSettingsStorage._();
  static final LxSettingsStorage instance = LxSettingsStorage._();

  static const String _keyQuality = 'lx_quality';

  /// 默认音质
  static const String defaultQuality = '320k';

  /// 可选音质（对齐洛雪 QUALITYS）
  static const List<Map<String, String>> qualityOptions = [
    {'id': '128k', 'name': '标准', 'sub': '128kbps'},
    {'id': '320k', 'name': '高品', 'sub': '320kbps MP3'},
    {'id': 'flac', 'name': '无损', 'sub': 'FLAC'},
    {'id': 'flac24bit', 'name': 'Hi-Res', 'sub': 'FLAC 24bit'},
  ];

  /// 获取音质
  Future<String> getQuality() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyQuality) ?? defaultQuality;
    } catch (_) {
      return defaultQuality;
    }
  }

  /// 设置音质
  Future<void> setQuality(String quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyQuality, quality);
    } catch (_) {}
  }

  /// 音质显示名
  static String qualityLabel(String q) {
    for (final opt in qualityOptions) {
      if (opt['id'] == q) return opt['name'] ?? q;
    }
    return q;
  }
}