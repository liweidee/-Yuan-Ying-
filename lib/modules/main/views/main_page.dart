import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:yuanying/common/assets.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/modules/setting/controllers/bg_config_controller.dart';
import 'package:yuanying/common/widgets/floating_navigation_bar.dart';
import 'package:yuanying/core/theme/style.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late final MainController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(MainController());
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    _controller.updateUseBottomNav(width: size.width, height: size.height);
  }

  double _getBottomBarHeight(NavigationBarStyle style) {
    double baseHeight;
    switch (style) {
      case NavigationBarStyle.default_:
      case NavigationBarStyle.defaultCompact:
        baseHeight = 56.0;
        break;
      case NavigationBarStyle.capsule:
        baseHeight = 70.0;
        break;
      case NavigationBarStyle.floating:
        baseHeight = 56.0;
        break;
      case NavigationBarStyle.minimal:
        baseHeight = 48.0;
        break;
    }
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    return baseHeight + bottomPadding;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final padding = MediaQuery.viewPaddingOf(context);

    // PopScope 移入 Obx 内部：让 canPop / onPopInvoked 能随
    //   selectedIndex 与 isWebFullscreen 变化实时刷新。
    return Obx(() {
      final _ = _controller.navStyleVersion.value;

      if (Get.isRegistered<BgConfigController>()) {
        final _ = Get.find<BgConfigController>().version.value;
      }
      final bgActive = SettingPref.bgActive;

      final useBottomNav = _controller.useBottomNav.value;
      final selectedIndex = _controller.selectedIndex.value;
      final navigationBars = _controller.navigationBars;
      final isWebFullscreen = _controller.isWebFullscreen.value;

      return PopScope(
        // 全屏时禁止直接 pop，先由 onPopInvoked 退出全屏
        canPop: !isWebFullscreen &&
            _controller.directExitOnBack &&
            selectedIndex == 0,
        onPopInvoked: (didPop) {
          if (didPop) return;

          // 全屏时：系统返回键先退出全屏，不退出 App
          if (isWebFullscreen) {
            _controller.setWebFullscreen(false);
            return;
          }

          // 原有逻辑（回首页）
          if (_controller.directExitOnBack && selectedIndex != 0) {
            _controller.switchPage(0);
          }
        },
        child: useBottomNav
            ? Scaffold(
                extendBody: true,
                resizeToAvoidBottomInset: false,
                // backgroundColor: bgActive ? Colors.transparent : colorScheme.surface,
                appBar: AppBar(
                  toolbarHeight: 0,
                  // 仅在LivePage tab 时状态栏区域用黑色填充，其他 tab 保持透明
                  backgroundColor:
                      navigationBars[selectedIndex] == NavigationBarType.live
                          ? Colors.black
                          : Colors.transparent,
                  elevation: 0,
                  systemOverlayStyle: SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness:
                        theme.brightness == Brightness.light
                            ? Brightness.dark
                            : Brightness.light,
                  ),
                ),
                body: navigationBars[selectedIndex].page,
                // 全屏时隐藏移动端底部导航栏
                bottomNavigationBar: isWebFullscreen
                    ? null
                    : _buildMobileBottomBar(
                        colorScheme: colorScheme,
                        selectedIndex: selectedIndex,
                        navigationBars: navigationBars,
                      ),
              )
            // ================= 桌面端 =================
            : _buildDesktopBody(
                theme: theme,
                colorScheme: colorScheme,
                bgActive: bgActive,
                padding: padding,
                selectedIndex: selectedIndex,
                navigationBars: navigationBars,
                isWebFullscreen: isWebFullscreen,
              ),
      );
    });
  }

  // ================= 桌面端布局 =================
  // 抽成独立方法，便于"全屏时隐藏左侧导航栏"的 if 包裹与 key 保护。
  //   结构、颜色、动画逻辑与原内联版本完全一致。
  Widget _buildDesktopBody({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required bool bgActive,
    required EdgeInsets padding,
    required int selectedIndex,
    required List<NavigationBarType> navigationBars,
    required bool isWebFullscreen,
  }) {
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: bgActive ? Colors.transparent : colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: theme.brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light,
        ),
      ),
      body: Row(
        children: [
          // 桌面端左侧导航栏：必须有 ClipRect 限制范围！
          // 全屏时隐藏；固定 key 保证 Element 复用
          if (!isWebFullscreen)
            RepaintBoundary(
              key: const ValueKey('desktop_nav'),
              child: ClipRect(
                child: BackdropFilter(
                  filter: bgActive
                      ? ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15)
                      : ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: Container(
                    width: 80,
                    padding: EdgeInsets.only(
                      top: padding.top + 15,
                      bottom: padding.bottom + 15,
                    ),
                    decoration: BoxDecoration(
                      color: bgActive
                          ? colorScheme.surface
                              .withValues(alpha: isDark ? 0.65 : 0.55)
                          : colorScheme.surface,
                      border: Border(
                        right: BorderSide(
                          // 开启壁纸时，边框更透一点，不破坏通透感；未开启时使用标准的 outline
                          color: bgActive
                              ? colorScheme.outline.withValues(alpha: 0.1)
                              : colorScheme.outline.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      // 如果你之前觉得有阴影，也可以加上这层极弱的阴影（二选一即可，建议只留边框）
                      // boxShadow: [
                      //   BoxShadow(
                      //     color: Colors.black.withValues(alpha: 0.05),
                      //     blurRadius: 4,
                      //     offset: const Offset(1, 0),
                      //   ),
                      // ],
                    ),
                    child: Column(
                      children: [
                        _buildAppLogo(),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: navigationBars.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final item = navigationBars[index];
                              final isSelected = index == selectedIndex;
                              return _NavItem(
                                key: ValueKey('nav_$index'),
                                item: item,
                                isSelected: isSelected,
                                onTap: () => _controller.switchPage(index),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // 固定 key：防止全屏切换时 page 的 Element 被重建导致 WebView 重载
          Expanded(
            key: const ValueKey('desktop_content'),
            child: navigationBars[selectedIndex].page,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar({
    required ColorScheme colorScheme,
    required int selectedIndex,
    required List<NavigationBarType> navigationBars,
  }) {
    final style = SettingPref.navigationBarStyle;

    final baseNavigationBar = NavigationBar(
      backgroundColor: SettingPref.bgActive ? Colors.transparent : null,
      surfaceTintColor: SettingPref.bgActive ? Colors.transparent : null,
      height: 56,
      elevation: SettingPref.bgActive ? 0 : null,
      selectedIndex: selectedIndex,
      onDestinationSelected: _controller.switchPage,
      indicatorColor: Colors.transparent,
      labelPadding: const EdgeInsets.only(top: 0),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.primary);
        }
        return TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: colorScheme.outline);
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) => Colors.transparent),
      destinations: navigationBars.map((item) => NavigationDestination(
        tooltip: '',
        icon: Icon(item.icon.icon, size: 24, color: colorScheme.outline),
        selectedIcon: Icon(item.selectIcon.icon, size: 24, color: colorScheme.primary),
        label: item.label,
      )).toList(),
    );

    Widget compactBottomBar = BottomNavigationBar(
      elevation: SettingPref.bgActive ? 0 : null,
      backgroundColor: SettingPref.bgActive ? Colors.transparent : null,
      currentIndex: selectedIndex,
      onTap: _controller.switchPage,
      type: BottomNavigationBarType.fixed,
      iconSize: 16,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      items: navigationBars.map((item) => BottomNavigationBarItem(
        icon: Icon(item.icon.icon, size: 16, color: colorScheme.outline),
        activeIcon: Icon(item.selectIcon.icon, size: 16, color: colorScheme.primary),
        label: item.label,
      )).toList(),
    );

    final capsuleNavigationBar = NavigationBar(
      backgroundColor: SettingPref.bgActive ? Colors.transparent : null,
      surfaceTintColor: SettingPref.bgActive ? Colors.transparent : null,
      height: 70,
      elevation: SettingPref.bgActive ? 0 : null,
      selectedIndex: selectedIndex,
      onDestinationSelected: _controller.switchPage,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.primary);
        }
        return TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: colorScheme.outline);
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) => Colors.transparent),
      destinations: navigationBars.map((item) => NavigationDestination(
        tooltip: '',
        icon: Icon(item.icon.icon, size: 24, color: colorScheme.outline),
        selectedIcon: Icon(item.selectIcon.icon, size: 24, color: colorScheme.primary),
        label: item.label,
      )).toList(),
    );

    final minimalNavigationBar = NavigationBar(
      backgroundColor: SettingPref.bgActive ? Colors.transparent : null,
      surfaceTintColor: SettingPref.bgActive ? Colors.transparent : null,
      height: 48,
      elevation: SettingPref.bgActive ? 0 : null,
      selectedIndex: selectedIndex,
      onDestinationSelected: _controller.switchPage,
      indicatorColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      overlayColor: WidgetStateProperty.resolveWith((states) => Colors.transparent),
      destinations: navigationBars.map((item) => NavigationDestination(
        tooltip: item.label,
        icon: Icon(item.icon.icon, size: 24, color: colorScheme.outline),
        selectedIcon: Icon(item.selectIcon.icon, size: 24, color: colorScheme.primary),
        label: item.label,
      )).toList(),
    );

    Widget bottomBar;
    switch (style) {
      case NavigationBarStyle.default_:
        bottomBar = baseNavigationBar;
        break;
      case NavigationBarStyle.defaultCompact:
        bottomBar = compactBottomBar;
        break;
      case NavigationBarStyle.floating:
        bottomBar = FloatingNavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: _controller.switchPage,
          backgroundColor: SettingPref.bgActive
              ? colorScheme.surface.withValues(alpha: 0.85)
              : colorScheme.surface,
          bottomPadding: 8.0,
          destinations: navigationBars.map((item) => FloatingNavigationDestination(
            label: item.label,
            icon: Icon(item.icon.icon, size: 24, color: colorScheme.outline),
            selectedIcon: Icon(item.selectIcon.icon, size: 24, color: colorScheme.primary),
          )).toList(),
        );
        break;
      case NavigationBarStyle.capsule:
        bottomBar = capsuleNavigationBar;
        break;
      case NavigationBarStyle.minimal:
        bottomBar = minimalNavigationBar;
        break;
    }

    final double actualHeight = _getBottomBarHeight(style);
    _controller.bottomBarHeight.value = actualHeight;

    // 统一处理底栏的毛玻璃效果（必须有 ClipRect 包裹）
    Widget finalBottomBar = bottomBar;
    if (SettingPref.bgActive) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final surfaceColor = colorScheme.surface;

      if (style != NavigationBarStyle.floating) {
        finalBottomBar = RepaintBoundary(
          child: ClipRect( // 限制模糊范围，绝对不让整页模糊
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                width: double.infinity, // 撑满全宽去白边
                color: surfaceColor.withValues(alpha: isDark ? 0.75 : 0.65), // 无边框
                child: bottomBar,
              ),
            ),
          ),
        );
      }
    }

    return Obx(() {
      if (!_controller.hideBottomBar.value) {
        return finalBottomBar;
      }
      if (_controller.isInstantMode) {
        final bool show = _controller.showBottomBar.value;
        return AnimatedSlide(
          offset: Offset(0, show ? 0 : 1),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: finalBottomBar,
        );
      } else {
        final double slideFactor = (_controller.barOffset.value / Style.topBarHeight).clamp(0.0, 1.0);
        return FractionalTranslation(
          translation: Offset(0, slideFactor),
          child: finalBottomBar,
        );
      }
    });
  }

  Widget _buildAppLogo() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: 56,
      height: 56,
      child: Image.asset(
        isDark ? Assets.logoDark : Assets.logoLight,
        width: 44,
        height: 44,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) => Icon(
          Icons.tv,
          size: 32,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final NavigationBarType item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? item.selectIcon.icon : item.icon.icon,
                size: 22,
                color: isSelected ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}