import 'package:dio/dio.dart';
import 'webview_sniffer.dart';

/// 资源嗅探服务 - 优先使用 WebView 嗅探，失败时回退到简易嗅探
class ResourceSniffer {
  static final Dio _dio = Dio();

  /// 从页面嗅探真实播放地址（使用 WebView）
  static Future<String?> sniff({
    required String url,
    Map<String, String>? headers,
    String? script,
    bool useWebView = true,
  }) async {
    if (useWebView) {
      try {
        final result = await WebViewSniffer.sniff(
          url: url,
          headers: headers,
          script: script,
        );
        if (result != null) {
          return result;
        }
      } catch (e) {
        // WebView 嗅探失败，回退到简易嗅探
      }
    }

    // 回退到简易嗅探
    return sniffSimple(url, headers: headers);
  }

  /// 简易嗅探（兜底方案）
  static Future<String?> sniffSimple(String url, {Map<String, String>? headers}) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: headers ?? {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );
      final content = response.data as String;

      // 简化正则表达式，避免转义问题
      final patterns = [
        r'"(?:url|playUrl|play_url|video|src|source)"\s*[:=]\s*"([^"]+)"',
        r'https?://[^\s<>]+\.(?:m3u8|mp4|flv)(?:[^\s<>]*)?',
      ];

      for (final pattern in patterns) {
        final match = RegExp(pattern, caseSensitive: false).firstMatch(content);
        if (match != null) {
          final matchedUrl = match.group(1) ?? match.group(0);
          if (matchedUrl != null && matchedUrl.startsWith('http')) {
            return matchedUrl;
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}