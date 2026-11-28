import 'package:package_info_plus/package_info_plus.dart';
import 'package:yuanying/build_config.dart';

/// 当前安装包版本。
///
/// 原生安装包信息是唯一可信来源；BuildConfig 只用于补充 CI 构建元数据，
/// 这样本地运行和没有传 dart-define 的 CI 也不会再显示 SNAPSHOT。
abstract final class AppVersion {
  static PackageInfo? _packageInfo;

  static Future<void> load() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } catch (_) {
      // 某些测试环境没有注册 package_info 插件，保留 BuildConfig 兜底。
    }
  }

  static String get name {
    final nativeName = _packageInfo?.version.trim() ?? '';
    if (nativeName.isNotEmpty) return nativeName;
    final buildName = BuildConfig.versionName.trim();
    return buildName.isEmpty || buildName == 'SNAPSHOT' ? 'unknown' : buildName;
  }

  static int get code {
    final nativeCode = int.tryParse(_packageInfo?.buildNumber ?? '');
    return nativeCode ?? BuildConfig.versionCode;
  }

  /// 例如 `2.0.8+43`。
  static String get display => '$name+$code';
}
