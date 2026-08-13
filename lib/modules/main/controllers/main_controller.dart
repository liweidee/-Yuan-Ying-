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
  double _lastTopScrollOffset = 0;      // 用于方向回退

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
      return;
    }
    final maxOffset = bottomBarHeight.value; // 使用动态高度

    if (isInstantMode) {
      // ---- 即时模式：根据方向控制 ----
      if (isScrollingDown != null) {
        // 向下滚动 → 显示 (barOffset=0)，向上滚动 → 隐藏 (barOffset=maxOffset)
        barOffset.value = isScrollingDown ? maxOffset : 0.0;   // 反转
      } else {
        // 回退：使用阈值（保持兼容）
        final clamped = offset.clamp(0.0, maxOffset);
        barOffset.value = clamped > maxOffset * 0.5 ? maxOffset : 0.0;
      }
    } else {
      // ---- 同步模式：线性偏移 ----
      final clamped = offset.clamp(0.0, maxOffset);
      barOffset.value = clamped;
    }
  }

  void updateTopBarOffset(double offset, {bool? isScrollingDown}) {
    if (!hideTopBar.value) {
      // 如果未启用隐藏，重置所有状态
      topBarOffset.value = 0.0;
      showTopBar.value = true;
      return;
    }

    // 钳制偏移量非负（与 PiliPlus 相同）
    final safeOffset = offset.clamp(0.0, double.infinity);

    if (isInstantMode) {
      bool down;
      if (isScrollingDown != null) {
        down = isScrollingDown;
      } else {
        down = safeOffset > _lastTopScrollOffset;
        _lastTopScrollOffset = safeOffset;
      }
      showTopBar.value = !down;   // 反转
    } else {
      // ---- Sync 模式：线性偏移 ----
      const double maxOffset = 52.0; // 必须与顶部栏高度一致
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