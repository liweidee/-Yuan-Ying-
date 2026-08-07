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
  void updateBottomBarOffset(double offset) {
    if (!hideBottomBar.value || !useBottomNav.value) {
      barOffset.value = 0.0;
      return;
    }
    const maxOffset = 56.0;
    final clamped = offset.clamp(0.0, maxOffset);
    if (isInstantMode) {
      barOffset.value = clamped > maxOffset * 0.5 ? maxOffset : 0.0;
    } else {
      barOffset.value = clamped;
    }
  }

  void updateTopBarOffset(double offset) {
    if (!hideTopBar.value) {
      topBarOffset.value = 0.0;
      return;
    }
    // 钳制最小值为 0，防止下拉刷新产生负偏移
    final clamped = offset.clamp(0.0, double.infinity);
    topBarOffset.value = clamped;
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