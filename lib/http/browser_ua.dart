import 'package:yuanying/utils/platform_utils.dart';

abstract final class BrowserUa {
  static String get platform => PlatformUtils.isMobile ? mob : pc;

  // Windows Chrome（主流，兼容性最好）
  static const pc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  // 备选：Windows Edge
  static const pcEdge =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0';

  // macOS Safari（仅在需要时使用）
  static const pcSafari =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15';

  // 移动端 Chrome（更新到最新版本）
  static const mob =
      'Mozilla/5.0 (Linux; Android 14; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.6478.122 Mobile Safari/537.36';

  // 移动端 Safari（iOS）
  static const mobSafari =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';
}