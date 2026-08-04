import 'package:get/get.dart';
import 'package:yuanying/utils/theme_utils.dart';

extension GetExt on GetInterface {
  S putOrFind<S>(InstanceBuilderCallback<S> dep, {String? tag}) =>
      GetInstance().putOrFind(dep, tag: tag);

  /// 更新应用主题
  void updateMyAppTheme() {
    // 刷新 ThemeUtils 中的主题对象（lightTheme/darkTheme）
    ThemeUtils.refreshTheme();

    // 强制重建整个应用（等同于 rootController.update()）
    Get.forceAppUpdate();
  }
}