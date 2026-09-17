import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/common/widgets/floating_navigation_bar.dart';
import '../controllers/fnos_server_controller.dart';
import 'fnos_home_page.dart';
import 'fnos_library_page.dart';
import 'fnos_favorite_page.dart';
import 'fnos_search_page.dart';

class FnosMainShell extends StatelessWidget {
  const FnosMainShell({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<FnosServerController>()) {
      Get.put(FnosServerController());
    }
    final controller = Get.find<FnosServerController>();
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

    final navItems = [
      _FnosNavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: '首页',
      ),
      _FnosNavItem(
        icon: Icons.favorite_outline,
        selectedIcon: Icons.favorite,
        label: '收藏',
      ),
      _FnosNavItem(
        icon: Icons.video_library_outlined,
        selectedIcon: Icons.video_library,
        label: '媒体库',
      ),
      _FnosNavItem(
        icon: Icons.search_outlined,
        selectedIcon: Icons.search,
        label: '搜索',
      ),
    ];

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
      ),
      body: Obx(() => IndexedStack(
            index: selectedIndex.value,
            children: const [
              FnosHomePage(),
              FnosFavoritePage(),
              FnosLibraryPage(),
              FnosSearchPage(),
            ],
          )),
      bottomNavigationBar: Obx(() {
        final style = SettingPref.navigationBarStyle;

        final baseNavigationBar = NavigationBar(
          height: 56,
          elevation: 0,
          selectedIndex: selectedIndex.value,
          onDestinationSelected: (i) => selectedIndex.value = i,
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
            if (states.any((s) =>
                s == WidgetState.pressed ||
                s == WidgetState.hovered ||
                s == WidgetState.focused)) {
              return Colors.transparent;
            }
            return null;
          }),
          destinations: navItems.map((item) {
            return NavigationDestination(
              tooltip: '',
              icon: Icon(item.icon, size: 24, color: colorScheme.outline),
              selectedIcon: Icon(item.selectedIcon,
                  size: 24, color: colorScheme.primary),
              label: item.label,
            );
          }).toList(),
        );

        final compactBottomBar = BottomNavigationBar(
          currentIndex: selectedIndex.value,
          onTap: (i) => selectedIndex.value = i,
          type: BottomNavigationBarType.fixed,
          iconSize: 16,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: navItems.map((item) {
            return BottomNavigationBarItem(
              icon: Icon(item.icon, size: 16, color: colorScheme.outline),
              activeIcon: Icon(item.selectedIcon,
                  size: 16, color: colorScheme.primary),
              label: item.label,
            );
          }).toList(),
        );

        final capsuleNavigationBar = NavigationBar(
          height: 70,
          elevation: 0,
          selectedIndex: selectedIndex.value,
          onDestinationSelected: (i) => selectedIndex.value = i,
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
          destinations: navItems.map((item) {
            return NavigationDestination(
              tooltip: '',
              icon: Icon(item.icon, size: 24, color: colorScheme.outline),
              selectedIcon: Icon(item.selectedIcon,
                  size: 24, color: colorScheme.primary),
              label: item.label,
            );
          }).toList(),
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
              onDestinationSelected: (i) => selectedIndex.value = i,
              backgroundColor: colorScheme.surface,
              bottomPadding: 8.0,
              destinations: navItems.map((item) {
                return FloatingNavigationDestination(
                  label: item.label,
                  icon: Icon(item.icon,
                      size: 24, color: colorScheme.outline),
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
}

class _FnosNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _FnosNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}