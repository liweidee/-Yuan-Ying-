import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:yuanying/common/assets.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/common/widgets/floating_navigation_bar.dart';

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    _controller.updateUseBottomNav(width: size.width, height: size.height);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final padding = MediaQuery.viewPaddingOf(context);

    return PopScope(
      canPop: _controller.directExitOnBack && _controller.selectedIndex.value == 0,
      onPopInvoked: (didPop) {
        if (!didPop && _controller.directExitOnBack) {
          if (_controller.selectedIndex.value != 0) {
            _controller.switchPage(0);
          }
        }
      },
      child: Obx(() {
        // 依赖 navStyleVersion，样式切换后触发重建
        final _ = _controller.navStyleVersion.value;

        final useBottomNav = _controller.useBottomNav.value;
        final selectedIndex = _controller.selectedIndex.value;
        final navigationBars = _controller.navigationBars;

        if (useBottomNav) {
          return Scaffold(
            extendBody: true,
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              toolbarHeight: 0,
              backgroundColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Theme.of(context).brightness == Brightness.light
                    ? Brightness.dark
                    : Brightness.light,
              ),
            ),
            body: navigationBars[selectedIndex].page,
            bottomNavigationBar: _buildMobileBottomBar(
              colorScheme: colorScheme,
              selectedIndex: selectedIndex,
              navigationBars: navigationBars,
            ),
          );
        } else {
          return Scaffold(
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              toolbarHeight: 0,
              backgroundColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Theme.of(context).brightness == Brightness.light
                    ? Brightness.dark
                    : Brightness.light,
              ),
            ),
            body: Row(
              children: [
                Container(
                  width: 80,
                  padding: EdgeInsets.only(
                    top: padding.top + 15,
                    bottom: padding.bottom + 15,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      right: BorderSide(
                        color: colorScheme.outline.withValues(alpha: 0.06),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildAppLogo(),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: navigationBars.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
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
                Expanded(
                  child: navigationBars[selectedIndex].page,
                ),
              ],
            ),
          );
        }
      }),
    );
  }

  // ============================================================
  // 底部栏方式：始终渲染，通过偏移量控制位置
  // ============================================================

  Widget _buildMobileBottomBar({
    required ColorScheme colorScheme,
    required int selectedIndex,
    required List<NavigationBarType> navigationBars,
  }) {
    final style = SettingPref.navigationBarStyle;

    // ============================================================
    // 1. 基础 NavigationBar
    // ============================================================
    final baseNavigationBar = NavigationBar(
      height: 56,
      elevation: 0,
      selectedIndex: selectedIndex,
      onDestinationSelected: _controller.switchPage,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          );
        }
        return TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
          color: colorScheme.outline,
        );
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        // 只要包含 pressed、hovered、focused 中的任意一种，都返回透明
        if (states.any((state) =>
            state == WidgetState.pressed ||
            state == WidgetState.hovered ||
            state == WidgetState.focused
        )) {
          return Colors.transparent;
        }
        return null; // 其他极少情况保留默认
      }),
      destinations: navigationBars.map((item) {
        return NavigationDestination(
          tooltip: '',
          icon: Icon(item.icon.icon, size: 24, color: colorScheme.outline),
          selectedIcon: Icon(item.selectIcon.icon, size: 24, color: colorScheme.primary),
          label: item.label,
        );
      }).toList(),
    );

    // ============================================================
    // 2. 胶囊 NavigationBar
    // ============================================================
    final capsuleNavigationBar = NavigationBar(
      height: 70,
      elevation: 0,
      selectedIndex: selectedIndex,
      onDestinationSelected: _controller.switchPage,
      // 不设置 indicatorColor，使用默认 primary 胶囊背景
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          );
        }
        return TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
          color: colorScheme.outline,
        );
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return Colors.transparent;
        }
        return null;
      }),
      destinations: navigationBars.map((item) {
        return NavigationDestination(
          tooltip: '',
          icon: Icon(item.icon.icon, size: 24, color: colorScheme.outline),
          selectedIcon: Icon(item.selectIcon.icon, size: 24, color: colorScheme.primary),
          label: item.label,
        );
      }).toList(),
    );

    // ============================================================
    // 3. 根据样式选择
    // ============================================================
    Widget bottomBar;
    switch (style) {
      case NavigationBarStyle.default_:
        // ===== 默认样式 =====
        bottomBar = baseNavigationBar;
        break;

      case NavigationBarStyle.floating:
        // ===== 悬浮样式 =====
        bottomBar = FloatingNavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: _controller.switchPage,
          backgroundColor: colorScheme.surface,
          bottomPadding: 8.0,
          destinations: navigationBars.map((item) {
            return FloatingNavigationDestination(
              label: item.label,
              icon: Icon(item.icon.icon, size: 24, color: colorScheme.outline),
              selectedIcon: Icon(item.selectIcon.icon, size: 24, color: colorScheme.primary),
            );
          }).toList(),
        );
        break;

      case NavigationBarStyle.capsule:
        // ===== 胶囊样式 =====
        bottomBar = capsuleNavigationBar;
        break;
    }

    // ============================================================
    // 4. 底栏收齐逻辑
    // ============================================================
    return Obx(() {
      if (!_controller.hideBottomBar.value) {
        return bottomBar;
      }
      final offset = _controller.barOffset.value;
      const maxOffset = 56.0;
      if (offset >= maxOffset) {
        return const SizedBox.shrink();
      }
      return Transform.translate(
        offset: Offset(0, offset),
        child: bottomBar,
      );
    });
  }

  Widget _buildAppLogo() {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: Image.asset(
        'assets/images/logo/logo.png',
        width: 44,
        height: 44,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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