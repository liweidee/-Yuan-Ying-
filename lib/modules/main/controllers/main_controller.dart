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
  final RxBool showTopBar = true.obs;

  // ===== 底部栏 Instant 模式专用状态 =====
  final RxBool showBottomBar = true.obs;

  // ===== 同步模式共享偏移（顶部和底部共享） =====
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

  // ===== 是否需要进行滚动校正（仅当顶部栏可隐藏时） =====
  bool get needsCorrection => hideTopBar.value;

  // ============================================================

  // void setNavBarConfig() {
  //   final List<int>? navBarSort = SettingPref.navBarSort;
  //   if (navBarSort == null || navBarSort.isEmpty) {
  //     navigationBars = NavigationBarType.values.toList();
  //   } else {
  //     navigationBars = navBarSort
  //         .map((i) => NavigationBarType.values[i])
  //         .whereType<NavigationBarType>()
  //         .toList();
  //     if (navigationBars.isEmpty) {
  //       navigationBars = NavigationBarType.values.toList();
  //     }
  //   }
  //   final defPage = SettingPref.defaultHomePage;
  //   final index = navigationBars.indexOf(defPage);
  //   selectedIndex.value = index >= 0 ? index : 0;
  // }

  void setNavBarConfig() {
    final List<int>? savedSort = SettingPref.navBarSort;
    final List<NavigationBarType> allValues = NavigationBarType.values.toList();

    if (savedSort == null || savedSort.isEmpty) {
      navigationBars = allValues;
    } else {
      // 从保存的索引恢复
      navigationBars = savedSort
          .map((i) => NavigationBarType.values[i])
          .whereType<NavigationBarType>()
          .toList();

      // 迁移逻辑：检查是否有遗漏的枚举项（如新增的 live）
      final Set<int> savedIndices = savedSort.toSet();
      bool hasMissing = false;
      for (int i = 0; i < allValues.length; i++) {
        if (!savedIndices.contains(i)) {
          // 缺失的枚举项追加到末尾
          navigationBars.add(allValues[i]);
          savedSort.add(i);
          hasMissing = true;
        }
      }

      // 如果列表为空（理论上不会），降级为全部
      if (navigationBars.isEmpty) {
        navigationBars = allValues;
      }

      // 如果有缺失项，保存更新后的排序
      if (hasMissing) {
        SettingPref.navBarSort = savedSort;
      }
    }

    // 设置默认选中的页面
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

  void switchPage(int index) {
    if (selectedIndex.value == index) return;
    selectedIndex.value = index;
  }

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