import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/models/common/bar_hide_type.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';

class MainController extends GetxController {
  // ===== 导航配置 =====
  late List<NavigationBarType> navigationBars = NavigationBarType.values.toList();

  // ===== 状态管理 =====
  final RxInt selectedIndex = 0.obs;
  final RxBool useBottomNav = true.obs;

  // ===== 顶部栏 Instant 模式专用状态 =====
  final RxBool showTopBar = true.obs;   // 用于 instant 模式

  // ===== 底部栏 Instant 模式专用状态 =====
  final RxBool showBottomBar = true.obs;   // 用于 instant 模式

  // ===== 底栏收齐 =====
  final RxDouble barOffset = 0.0.obs;
  final RxBool hideBottomBar = SettingPref.hideBottomBar.obs;
  BarHideType get barHideType => SettingPref.barHideType;

  // ===== 顶部栏收齐 =====
  final RxDouble topBarOffset = 0.0.obs;
  final RxBool hideTopBar = SettingPref.hideTopBar.obs;

  // ===== 返回时直接退出 =====
  bool directExitOnBack = SettingPref.directExitOnBack;

  bool get isInstantMode => barHideType == BarHideType.instant;

  final RxInt navStyleVersion = 0.obs;

  final RxDouble bottomBarHeight = 56.0.obs;

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
    super.onInit();
    setNavBarConfig();
    _updateUseBottomNav();
    barOffset.value = 0.0;
    topBarOffset.value = 0.0;
    showBottomBar.value = true;
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

  NavigationBarStyle get currentNavBarStyle => SettingPref.navigationBarStyle;

  void refreshNavBarStyle() {
    navStyleVersion.value++;
  }

  // ===== 底栏偏移更新 =====
  void updateBottomBarOffset(double offset, {bool? isScrollingDown}) {
    if (!hideBottomBar.value || !useBottomNav.value) {
      barOffset.value = 0.0;
      showBottomBar.value = true;
      return;
    }

    if (isInstantMode) {
      // 即时模式：只更新 showBottomBar
      if (isScrollingDown != null) {
        showBottomBar.value = !isScrollingDown; // 根据你的方向映射调整
      }
      // 不更新 barOffset
    } else {
      // 同步模式：更新 barOffset
      final maxOffset = bottomBarHeight.value;
      final clamped = offset.clamp(0.0, maxOffset);
      barOffset.value = clamped;
    }
  }

  void updateTopBarOffset(double offset, {bool? isScrollingDown}) {
    if (!hideTopBar.value) {
      topBarOffset.value = 0.0;
      showTopBar.value = true;
      return;
    }

    if (isInstantMode) {
      if (isScrollingDown != null) {
        showTopBar.value = !isScrollingDown;
      }
    } else {
      final safeOffset = offset.clamp(0.0, double.infinity);
      const double maxOffset = 52.0;
      topBarOffset.value = safeOffset.clamp(0.0, maxOffset);
    }
  }

  void refreshHideBottomBar() {
    hideBottomBar.value = SettingPref.hideBottomBar;
    if (!hideBottomBar.value) {
      barOffset.value = 0.0;
    }
  }

  void refreshHideTopBar() {
    hideTopBar.value = SettingPref.hideTopBar;
    if (!hideTopBar.value) {
      topBarOffset.value = 0.0;
    }
  }
}