import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/modules/setting/controllers/bg_config_controller.dart';
import 'package:yuanying/common/widgets/floating_navigation_bar.dart';

import '../controllers/emby_server_controller.dart';
import '../controllers/emby_history_controller.dart';
import 'emby_home_page.dart';
import 'emby_favorite_page.dart';
import 'emby_history_page.dart';
import 'emby_search_page.dart';
import 'emby_download_page.dart';

class EmbyMainShell extends StatelessWidget {
  const EmbyMainShell({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<EmbyServerController>()) {
      Get.put(EmbyServerController());
    }
    final controller = Get.find<EmbyServerController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final serverId = Get.arguments?['serverId'] as String?;
    if (serverId != null &&
        serverId.isNotEmpty &&
        controller.currentServerId.value != serverId) {
      controller.setDefault(serverId);
    }

    final server = controller.servers.firstWhere(
      (s) => s.id == serverId,
      orElse: () => controller.currentServer!,
    );

    final RxInt selectedIndex = 0.obs;

    return Obx(() {
      if (Get.isRegistered<BgConfigController>()) {
        final _ = Get.find<BgConfigController>().version.value;
      }
      final bgActive = SettingPref.bgActive;

      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Get.back(),
            tooltip: '返回服务器列表',
          ),
          title: Text(server.name),
          actions: [
            Obx(() {
              if (selectedIndex.value == 2) {
                return IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: '清空历史',
                  onPressed: () => _confirmClearHistory(context),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
        body: Obx(() => IndexedStack(
              index: selectedIndex.value,
              children: const [
                EmbyHomePage(),
                EmbyFavoritePage(),
                EmbyHistoryPage(),
                EmbySearchPage(),
                EmbyDownloadPage(),
              ],
            )),
        bottomNavigationBar: Obx(() {
          final style = SettingPref.navigationBarStyle;

          final embyNavigationBars = [
            _EmbyNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: '首页'),
            _EmbyNavItem(icon: Icons.favorite_outline, selectedIcon: Icons.favorite, label: '收藏'),
            _EmbyNavItem(icon: Icons.history_outlined, selectedIcon: Icons.history, label: '历史'),
            _EmbyNavItem(icon: Icons.search_outlined, selectedIcon: Icons.search, label: '搜索'),
            _EmbyNavItem(icon: Icons.download_outlined, selectedIcon: Icons.download, label: '下载'),
          ];

          final baseNavigationBar = NavigationBar(
            backgroundColor: SettingPref.bgActive ? Colors.transparent : null,
            surfaceTintColor: SettingPref.bgActive ? Colors.transparent : null,
            height: 56,
            elevation: SettingPref.bgActive ? 0 : null,
            selectedIndex: selectedIndex.value,
            onDestinationSelected: (index) => selectedIndex.value = index,
            indicatorColor: Colors.transparent,
            labelPadding: const EdgeInsets.only(top: 0),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.primary);
              }
              return TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: colorScheme.outline);
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) => Colors.transparent),
            destinations: embyNavigationBars.map((item) => NavigationDestination(
              tooltip: '',
              icon: Icon(item.icon, size: 24, color: colorScheme.outline),
              selectedIcon: Icon(item.selectedIcon, size: 24, color: colorScheme.primary),
              label: item.label,
            )).toList(),
          );

          final compactBottomBar = BottomNavigationBar(
            elevation: SettingPref.bgActive ? 0 : null,
            backgroundColor: SettingPref.bgActive ? Colors.transparent : null,
            currentIndex: selectedIndex.value,
            onTap: (index) => selectedIndex.value = index,
            type: BottomNavigationBarType.fixed,
            iconSize: 16,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            items: embyNavigationBars.map((item) => BottomNavigationBarItem(
              icon: Icon(item.icon, size: 16, color: colorScheme.outline),
              activeIcon: Icon(item.selectedIcon, size: 16, color: colorScheme.primary),
              label: item.label,
            )).toList(),
          );

          final capsuleNavigationBar = NavigationBar(
            backgroundColor: SettingPref.bgActive ? Colors.transparent : null,
            surfaceTintColor: SettingPref.bgActive ? Colors.transparent : null,
            height: 70,
            elevation: SettingPref.bgActive ? 0 : null,
            selectedIndex: selectedIndex.value,
            onDestinationSelected: (index) => selectedIndex.value = index,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.primary);
              }
              return TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: colorScheme.outline);
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) => Colors.transparent),
            destinations: embyNavigationBars.map((item) => NavigationDestination(
              tooltip: '',
              icon: Icon(item.icon, size: 24, color: colorScheme.outline),
              selectedIcon: Icon(item.selectedIcon, size: 24, color: colorScheme.primary),
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
                selectedIndex: selectedIndex.value,
                onDestinationSelected: (index) => selectedIndex.value = index,
                backgroundColor: bgActive ? colorScheme.surface.withValues(alpha: 0.85) : colorScheme.surface,
                bottomPadding: 8.0,
                destinations: embyNavigationBars.map((item) => FloatingNavigationDestination(
                  label: item.label,
                  icon: Icon(item.icon, size: 24, color: colorScheme.outline),
                  selectedIcon: Icon(item.selectedIcon, size: 24, color: colorScheme.primary),
                )).toList(),
              );
              break;
            case NavigationBarStyle.capsule:
            default:
              bottomBar = capsuleNavigationBar;
              break;
          }

          Widget finalBottomBar = bottomBar;
          if (bgActive) {
            final isDark = theme.brightness == Brightness.dark;
            final surfaceColor = colorScheme.surface;

            if (style != NavigationBarStyle.floating) {
              finalBottomBar = RepaintBoundary(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      width: double.infinity,
                      color: surfaceColor.withValues(alpha: isDark ? 0.75 : 0.65),
                      child: bottomBar,
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

  Future<void> _confirmClearHistory(BuildContext context) async {
    if (!Get.isRegistered<EmbyHistoryController>()) {
      SmartDialog.showToast('历史未初始化');
      return;
    }
    final ctrl = Get.find<EmbyHistoryController>();

    if (ctrl.items.isEmpty) {
      SmartDialog.showToast('历史已空');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('将删除所有播放历史记录。\n\n注意：仅清理历史记录，不会删除服务器上的任何视频文件。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    SmartDialog.show(
      tag: 'clear_history',
      maskColor: Colors.black54,
      clickMaskDismiss: false,
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
            SizedBox(height: 14),
            Text('正在清空历史...', style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );

    try {
      await ctrl.clearAllHistory();
      if (context.mounted) {
        SmartDialog.dismiss(tag: 'clear_history', force: true);
        SmartDialog.showToast('已清空全部历史');
      }
    } catch (e) {
      if (context.mounted) {
        SmartDialog.dismiss(tag: 'clear_history', force: true);
        SmartDialog.showToast('清空失败: $e');
      }
    }
  }
}

class _EmbyNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _EmbyNavItem({required this.icon, required this.selectedIcon, required this.label});
}