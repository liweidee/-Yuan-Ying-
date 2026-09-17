import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/common/widgets/floating_navigation_bar.dart';

import '../controllers/jellyfin_server_controller.dart';
import '../controllers/jellyfin_history_controller.dart';
import 'jellyfin_home_page.dart';
import 'jellyfin_favorite_page.dart';
import 'jellyfin_history_page.dart';
import 'jellyfin_search_page.dart';
import 'jellyfin_download_page.dart';

class JellyfinMainShell extends StatelessWidget {
  const JellyfinMainShell({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<JellyfinServerController>()) {
      Get.put(JellyfinServerController());
    }
    final controller = Get.find<JellyfinServerController>();
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Get.back(),
          tooltip: '返回服务器列表',
        ),
        title: Text(server.name),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        // 动态 actions：仅在"历史"Tab（index=2）显示清空按钮
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
      // Tab：首页 / 收藏 / 历史 / 搜索 / 下载
      body: Obx(() => IndexedStack(
            index: selectedIndex.value,
            children: const [
              JellyfinHomePage(),
              JellyfinFavoritePage(),
              JellyfinHistoryPage(),
              JellyfinSearchPage(),
              JellyfinDownloadPage(),
            ],
          )),
      bottomNavigationBar: Obx(() {
        final style = SettingPref.navigationBarStyle;

        final jellyfinNavigationBars = [
          _JellyfinNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: '首页',
          ),
          _JellyfinNavItem(
            icon: Icons.favorite_outline,
            selectedIcon: Icons.favorite,
            label: '收藏',
          ),
          _JellyfinNavItem(
            icon: Icons.history_outlined,
            selectedIcon: Icons.history,
            label: '历史',
          ),
          _JellyfinNavItem(
            icon: Icons.search_outlined,
            selectedIcon: Icons.search,
            label: '搜索',
          ),
          _JellyfinNavItem(
            icon: Icons.download_outlined,
            selectedIcon: Icons.download,
            label: '下载',
          ),
        ];

        // ========== 基础 NavigationBar ==========
        final baseNavigationBar = NavigationBar(
          height: 56,
          elevation: 0,
          selectedIndex: selectedIndex.value,
          onDestinationSelected: (index) => selectedIndex.value = index,
          indicatorColor: Colors.transparent,
          labelPadding: const EdgeInsets.only(top: 0),
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
            if (states.any((state) =>
                state == WidgetState.pressed ||
                state == WidgetState.hovered ||
                state == WidgetState.focused)) {
              return Colors.transparent;
            }
            return null;
          }),
          destinations: jellyfinNavigationBars.map((item) {
            return NavigationDestination(
              tooltip: '',
              icon: Icon(item.icon, size: 24, color: colorScheme.outline),
              selectedIcon: Icon(item.selectedIcon,
                  size: 24, color: colorScheme.primary),
              label: item.label,
            );
          }).toList(),
        );

        // ========== 紧凑风格 ==========
        final compactBottomBar = BottomNavigationBar(
          currentIndex: selectedIndex.value,
          onTap: (index) => selectedIndex.value = index,
          type: BottomNavigationBarType.fixed,
          iconSize: 16,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: jellyfinNavigationBars.map((item) {
            return BottomNavigationBarItem(
              icon: Icon(item.icon, size: 16, color: colorScheme.outline),
              activeIcon: Icon(item.selectedIcon,
                  size: 16, color: colorScheme.primary),
              label: item.label,
            );
          }).toList(),
        );

        // ========== 胶囊 ==========
        final capsuleNavigationBar = NavigationBar(
          height: 70,
          elevation: 0,
          selectedIndex: selectedIndex.value,
          onDestinationSelected: (index) => selectedIndex.value = index,
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
          destinations: jellyfinNavigationBars.map((item) {
            return NavigationDestination(
              tooltip: '',
              icon: Icon(item.icon, size: 24, color: colorScheme.outline),
              selectedIcon: Icon(item.selectedIcon,
                  size: 24, color: colorScheme.primary),
              label: item.label,
            );
          }).toList(),
        );

        // ========== 样式分发 ==========
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
              backgroundColor: colorScheme.surface,
              bottomPadding: 8.0,
              destinations: jellyfinNavigationBars.map((item) {
                return FloatingNavigationDestination(
                  label: item.label,
                  icon:
                      Icon(item.icon, size: 24, color: colorScheme.outline),
                  selectedIcon: Icon(item.selectedIcon,
                      size: 24, color: colorScheme.primary),
                );
              }).toList(),
            );
            break;
          case NavigationBarStyle.capsule:
          default:
            bottomBar = capsuleNavigationBar;
            break;
        }

        return bottomBar;
      }),
    );
  }

  /// 清空全部播放历史（带确认 + 进度提示）
  Future<void> _confirmClearHistory(BuildContext context) async {
    if (!Get.isRegistered<JellyfinHistoryController>()) {
      SmartDialog.showToast('历史未初始化');
      return;
    }
    final ctrl = Get.find<JellyfinHistoryController>();

    if (ctrl.items.isEmpty) {
      SmartDialog.showToast('历史已空');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('将删除所有播放历史记录。\n\n'
            '注意：仅清理历史记录，不会删除服务器上的任何视频文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // ---- 显示进度 ----
    SmartDialog.show(
      tag: 'clear_history',
      maskColor: Colors.black54,
      clickMaskDismiss: false,
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 14),
            Text(
              '正在清空历史...',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
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

class _JellyfinNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _JellyfinNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}