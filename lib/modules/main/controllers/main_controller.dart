// lib/modules/main/controllers/main_controller.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/models/common/bar_hide_type.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/modules/live/controllers/live_controller.dart';

class MainController extends GetxController {
  // ===== 导航配置 =====
  late List<NavigationBarType> navigationBars = NavigationBarType.values.toList();

  // ===== 状态管理 =====
  final RxInt selectedIndex = 0.obs;
  final RxBool useBottomNav = true.obs;

  // ===== 顶部栏 Instant 模式专用状态 =====
  final RxBool showTopBar = true.obs;

  // ===== 底部栏 Instant 模式专用状态 =====
  final RxBool showBottomBar = true.obs;

  // ===== 同步模式共享偏移 =====
  final RxDouble barOffset = 0.0.obs;

  // ===== 底栏收齐设置 =====
  final RxBool hideBottomBar = SettingPref.hideBottomBar.obs;
  BarHideType get barHideType => SettingPref.barHideType;

  // ===== 顶部栏收齐设置 =====
  final RxBool hideTopBar = SettingPref.hideTopBar.obs;

  // ===== 返回时直接退出 =====
  bool directExitOnBack = SettingPref.directExitOnBack;

  bool get isInstantMode => barHideType == BarHideType.instant;

  final RxInt navStyleVersion = 0.obs;

  final RxDouble bottomBarHeight = 56.0.obs;

  bool get needsCorrection => hideTopBar.value;

  // ============================================================
  // 获取直播 Tab 的索引
  // ============================================================

  int get liveTabIndex {
    for (int i = 0; i < navigationBars.length; i++) {
      if (navigationBars[i] == NavigationBarType.live) {
        return i;
      }
    }
    return -1;
  }

  // ============================================================
  // 通知 LiveController
  // ============================================================

  void _notifyLiveController({required bool pause}) {
    try {
      final LiveController liveController = Get.find<LiveController>(tag: 'live');
      if (pause) {
        liveController.pauseBySystem();
      } else {
        liveController.resumeBySystem();
      }
    } catch (_) {
      // LiveController 未注册，静默忽略
    }
  }

  // ============================================================

  void setNavBarConfig() {
    final List<int>? savedSort = SettingPref.navBarSort;
    final List<NavigationBarType> allValues = NavigationBarType.values.toList();

    if (savedSort == null || savedSort.isEmpty) {
      navigationBars = allValues;
    } else {
      navigationBars = savedSort
          .map((i) => NavigationBarType.values[i])
          .whereType<NavigationBarType>()
          .toList();

      final Set<int> savedIndices = savedSort.toSet();
      bool hasMissing = false;
      for (int i = 0; i < allValues.length; i++) {
        if (!savedIndices.contains(i)) {
          navigationBars.add(allValues[i]);
          savedSort.add(i);
          hasMissing = true;
        }
      }

      if (navigationBars.isEmpty) {
        navigationBars = allValues;
      }

      if (hasMissing) {
        SettingPref.navBarSort = savedSort;
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
    showBottomBar.value = true;
    showTopBar.value = true;
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

  // ============================================================
  // switchPage：添加直播通知
  // ============================================================

  void switchPage(int index) {
    if (selectedIndex.value == index) return;

    final int oldIndex = selectedIndex.value;
    final int liveIdx = liveTabIndex;

    // 如果从直播 Tab 切出去 → 暂停直播
    if (liveIdx != -1 && oldIndex == liveIdx) {
      _notifyLiveController(pause: true);
    }

    selectedIndex.value = index;

    // 如果切到直播 Tab → 恢复直播（仅当用户没有手动暂停时）
    if (liveIdx != -1 && index == liveIdx) {
      _notifyLiveController(pause: false);
    }
  }

  // ============================================================

  NavigationBarStyle get currentNavBarStyle => SettingPref.navigationBarStyle;

  void refreshNavBarStyle() {
    navStyleVersion.value++;
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
      barOffset.value = 0.0;
    }
  }
}