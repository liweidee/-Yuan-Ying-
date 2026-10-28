// lib/modules/manual_source/models/web_source_meta.dart
import 'dart:convert';

/// `.web.json` 元信息
class WebSourceMeta {
  final String name;
  final String homePage;
  final String? ext;

  WebSourceMeta({
    required this.name,
    required this.homePage,
    this.ext,
  });

  /// 解析内容，失败返回 null
  static WebSourceMeta? parse(String content) {
    try {
      final j = jsonDecode(content);
      if (j is! Map) return null;

      final api = j['api']?.toString() ?? '';
      String homePage = api;
      if (homePage.startsWith('web://')) {
        homePage = homePage.substring(6); // 'web://'.length == 6
      }
      if (homePage.isEmpty) return null;

      return WebSourceMeta(
        name: j['name']?.toString() ?? 'Web 源',
        homePage: homePage,
        ext: j['ext']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 显式带 `.js` 路径时可省略（同目录同名）
  String? jsPathOf(String webJsonPath) {
    if (!webJsonPath.endsWith('.web.json')) return null;
    return webJsonPath.replaceAll('.web.json', '.js');
  }
}