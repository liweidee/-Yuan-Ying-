import 'i_spider_service.dart';

/// 站点切换结果
///
/// 语义：切源是可失败的操作。
/// - success：源已就绪，可发起业务调用
/// - failure：源不可用（加载失败 / 超时 / 脚本异常 / 平台不支持）
///
/// 注意：failure 不表示"源永久不可用"。用户可重新选择该源重试。
class SiteSwitchResult {
  final bool success;
  final String? error;
  final String? siteKey;

  const SiteSwitchResult._({
    required this.success,
    this.error,
    this.siteKey,
  });

  factory SiteSwitchResult.success({String? siteKey}) =>
      SiteSwitchResult._(success: true, siteKey: siteKey);

  factory SiteSwitchResult.failure(String error, {String? siteKey}) =>
      SiteSwitchResult._(success: false, error: error, siteKey: siteKey);

  @override
  String toString() => success
      ? 'SiteSwitchResult.success($siteKey)'
      : 'SiteSwitchResult.failure($error)';
}

/// 安全切站的扩展方法。
///
/// 用 extension 而非接口方法，原因：
/// Dart 的 implements 不继承方法体，接口里带默认实现的成员
/// 仍会被要求实现类 override。extension 不参与 implements 契约，
/// 所有 ISpiderService 实现类无需改动。
extension SpiderSwitchSafeExtension on ISpiderService {
  Future<SiteSwitchResult> switchSiteSafe(
    String apiUrl,
    String siteKey, {
    dynamic ext,
  }) async {
    try {
      switchSite(apiUrl, siteKey, ext: ext);
      await Future<void>.delayed(Duration.zero);
      return SiteSwitchResult.success(siteKey: siteKey);
    } catch (e) {
      return SiteSwitchResult.failure(e.toString(), siteKey: siteKey);
    }
  }
}