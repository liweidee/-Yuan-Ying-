import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/models/common/bar_hide_type.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
// import 'package:yuanying/utils/storage_manager.dart';
// import 'package:yuanying/core/constants/storage_keys.dart';

class MainController extends GetxController {
  // ===== 导航配置 =====
  late List<NavigationBarType> navigationBars = NavigationBarType.values.toList();

  // ===== 状态管理 =====
  final RxInt selectedIndex = 0.obs;
  final RxBool useBottomNav = true.obs;

  // ===== 底栏收齐 - 只保留偏移量，无额外状态 =====
  final RxDouble barOffset = 0.0.obs;
  final RxBool hideBottomBar = SettingPref.hideBottomBar.obs;
  BarHideType get barHideType => SettingPref.barHideType;

  // ===== 返回时直接退出 =====
  bool directExitOnBack = SettingPref.directExitOnBack;

  // 判断是否为即时模式
  bool get isInstantMode => barHideType == BarHideType.instant;

  // ===== 导航栏样式版本号（用于触发 UI 刷新） =====
  final RxInt navStyleVersion = 0.obs;

  // ============================================================
  // 核心方法
  // ============================================================

  void setNavBarConfig() {
    final List<int>? navBarSort = SettingPref.navBarSort;
    if (navBarSort == null || navBarSort.isEmpty) {
      navigationBars = NavigationBarType.values.toList();
    } else {
      navigationBars = navBarSort
          .map((i) => NavigationBarType.values[i])
          .whereType<NavigationBarType>()
          .toList();
      if (navigationBars.isEmpty) {
        navigationBars = NavigationBarType.values.toList();
      }
    }
    final defPage = SettingPref.defaultHomePage;
    final index = navigationBars.indexOf(defPage);
    selectedIndex.value = index >= 0 ? index : 0;
  }

  @override
  void onInit() {
    // StorageManager.deleteSetting(SettingBoxKey.navBarSort);
    super.onInit();
    setNavBarConfig();
    _updateUseBottomNav();
    barOffset.value = 0.0;
  }

  void updateUseBottomNav({double? width, double? height}) {
    _updateUseBottomNav(width: width, height: height);
  }

  void _updateUseBottomNav({double? width, double? height}) {
    if (width != null && height != null) {
      useBottomNav.value = _isPortrait(width, height);
    } else {
      final context = Get.context;
      if (context != null) {
        final size = MediaQuery.sizeOf(context);
        useBottomNav.value = _isPortrait(size.width, size.height);
      } else {
        useBottomNav.value = true;
      }
    }
  }

  bool _isPortrait(double width, double height) {
    return width < 600 || height >= width;
  }

  void switchPage(int index) {
    if (selectedIndex.value == index) return;
    selectedIndex.value = index;
  }

  // ============================================================
  // 导航栏样式刷新方法
  // ============================================================

  /// 获取当前导航栏样式（直接读取存储值）
  NavigationBarStyle get currentNavBarStyle => SettingPref.navigationBarStyle;

  /// 刷新导航栏样式（切换样式后调用）
  void refreshNavBarStyle() {
    navStyleVersion.value++;
  }

  // ============================================================
  // 底栏偏移 - 直接设置偏移量，永远不隐藏 Widget
  // ============================================================

  void updateBottomBarOffset(double offset) {
    if (!hideBottomBar.value || !useBottomNav.value) {
      barOffset.value = 0.0;
      return;
    }
    const maxOffset = 56.0;
    final clamped = offset.clamp(0.0, maxOffset);
    
    // ===== 即时模式直接跳转，同步模式平滑过渡 =====
    if (isInstantMode) {
      // 即时模式：超过一半就完全隐藏，否则完全显示
      if (clamped > maxOffset * 0.5) {
        barOffset.value = maxOffset;
      } else {
        barOffset.value = 0.0;
      }
    } else {
      // 同步模式：线性跟随
      barOffset.value = clamped;
    }
  }

  void refreshHideBottomBar() {
    hideBottomBar.value = SettingPref.hideBottomBar;
    if (!hideBottomBar.value) {
      barOffset.value = 0.0;
    }
  }
}