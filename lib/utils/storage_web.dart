// lib/utils/storage_web.dart
// 仅在 Web 平台编译和使用
import 'dart:html' as html;
import 'dart:convert';

class StorageWebHelper {
  static void saveCustomSites(List<Map<String, dynamic>> sites) {
    final jsonStr = jsonEncode(sites);
    html.window.localStorage['custom_sites'] = jsonStr;
  }

  static List<Map<String, dynamic>> getCustomSites() {
    final jsonStr = html.window.localStorage['custom_sites'];
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }
}