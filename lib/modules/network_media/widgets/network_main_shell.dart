import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/modules/setting/controllers/bg_config_controller.dart';
import 'package:yuanying/common/widgets/floating_navigation_bar.dart';

/// 通用网络模块壳：2 个 Tab（文件 / 下载）
/// 底栏样式跟随源影全局设置（默认/紧凑/胶囊/悬浮）
class NetworkMainShell extends StatefulWidget {
  const NetworkMainShell({
    super.key,
    required this.title,
    required this.filePage,
    required this.downloadPage,
    this.onBack,
  });

  final String title;
  final Widget filePage;
  final Widget downloadPage;
  final VoidCallback? onBack;

  @override
  State<NetworkMainShell> createState() => _NetworkMainShellState();
}

class _NetworkMainShellState extends State<NetworkMainShell> {
  final RxInt _selectedIndex = 0.obs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final destinations = [
      _NavItem(Icons.folder_outlined, Icons.folder, '文件'),
      _NavItem(Icons.download_outlined, Icons.download, '下载'),
    ];

    return Obx(() {
      // 监听壁纸开关状态变化
      if (Get.isRegistered<BgConfigController>()) {
        final _ = Get.find<BgConfigController>().version.value;
      }
      final bgActive = SettingPref.bgActive;
      final bgColor = bgActive ? Colors.transparent : cs.surface;

      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: widget.onBack ?? () => Get.back(),
            tooltip: '返回',
          ),
          title: Text(widget.title),
          backgroundColor: bgColor,
          foregroundColor: cs.onSurface,
          elevation: 0,
        ),
        body: Obx(() => IndexedStack(
              index: _selectedIndex.value,
              children: [widget.filePage, widget.downloadPage],
            )),
        bottomNavigationBar: Obx(() {
          final style = SettingPref.navigationBarStyle;

          Widget bottomBar;
          switch (style) {
            case NavigationBarStyle.default_:
              bottomBar = NavigationBar(
                backgroundColor: SettingPref.bgActive ? Colors.transparent : null,
                surfaceTintColor: SettingPref.bgActive ? Colors.transparent : null,
                height: 56,
                elevation: 0,
                selectedIndex: _selectedIndex.value,
                onDestinationSelected: (i) => _selectedIndex.value = i,
                indicatorColor: Colors.transparent,
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final sel = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                    color: sel ? cs.primary : cs.outline,
                  );
                }),
                destinations: destinations
                    .map((d) => NavigationDestination(
                          tooltip: '',
                          icon: Icon(d.icon, size: 24, color: cs.outline),
                          selectedIcon:
                              Icon(d.selectedIcon, size: 24, color: cs.primary),
                          label: d.label,
                        ))
                    .toList(),
              );
              break;

            case NavigationBarStyle.defaultCompact:
              bottomBar = BottomNavigationBar(
                backgroundColor: SettingPref.bgActive ? Colors.transparent : null,
                currentIndex: _selectedIndex.value,
                onTap: (i) => _selectedIndex.value = i,
                type: BottomNavigationBarType.fixed,
                iconSize: 16,
                selectedFontSize: 12,
                unselectedFontSize: 12,
                items: destinations
                    .map((d) => BottomNavigationBarItem(
                          icon: Icon(d.icon, size: 16, color: cs.outline),
                          activeIcon:
                              Icon(d.selectedIcon, size: 16, color: cs.primary),
                          label: d.label,
                        ))
                    .toList(),
              );
              break;

            case NavigationBarStyle.floating:
              bottomBar = FloatingNavigationBar(
                selectedIndex: _selectedIndex.value,
                onDestinationSelected: (i) => _selectedIndex.value = i,
                backgroundColor: bgActive
                    ? cs.surface.withValues(alpha: 0.85)
                    : cs.surface,
                bottomPadding: 8.0,
                destinations: destinations
                    .map((d) => FloatingNavigationDestination(
                          label: d.label,
                          icon: Icon(d.icon, size: 24, color: cs.outline),
                          selectedIcon:
                              Icon(d.selectedIcon, size: 24, color: cs.primary),
                        ))
                    .toList(),
              );
              break;

            case NavigationBarStyle.capsule:
            default:
              bottomBar = NavigationBar(
                backgroundColor: SettingPref.bgActive ? Colors.transparent : null,
                surfaceTintColor: SettingPref.bgActive ? Colors.transparent : null,
                height: 70,
                elevation: 0,
                selectedIndex: _selectedIndex.value,
                onDestinationSelected: (i) => _selectedIndex.value = i,
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final sel = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                    color: sel ? cs.primary : cs.outline,
                  );
                }),
                destinations: destinations
                    .map((d) => NavigationDestination(
                          tooltip: '',
                          icon: Icon(d.icon, size: 24, color: cs.outline),
                          selectedIcon:
                              Icon(d.selectedIcon, size: 24, color: cs.primary),
                          label: d.label,
                        ))
                    .toList(),
              );
              break;
          }

          // 统一处理底栏的毛玻璃效果（性能与清晰度优化版）
          Widget finalBottomBar = bottomBar;
          if (bgActive) {
            final isDark = theme.brightness == Brightness.dark;
            final alpha = isDark ? 0.80 : 0.75;

            if (style != NavigationBarStyle.floating) {
              finalBottomBar = RepaintBoundary(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: alpha),
                        border: Border(
                          top: BorderSide(
                            color: cs.outline.withValues(alpha: 0.1),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          1.1, 0, 0, 0, 0,
                          0, 1.1, 0, 0, 0,
                          0, 0, 1.1, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                        child: bottomBar,
                      ),
                    ),
                  ),
                ),
              );
            }
          }
          return finalBottomBar;
        }),
      );
    });
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.icon, this.selectedIcon, this.label);
}