import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/common/widgets/floating_navigation_bar.dart';
import '../controllers/alist_server_controller.dart';
import '../controllers/alist_user_controller.dart';
import 'alist_favorite_page.dart';
import 'alist_file_list_page.dart';
import 'alist_recents_page.dart';
import 'alist_settings_page.dart';

class AlistMainShell extends StatefulWidget {
  const AlistMainShell({super.key});

  @override
  State<AlistMainShell> createState() => _AlistMainShellState();
}

class _AlistMainShellState extends State<AlistMainShell> {
  final RxInt _selectedIndex = 0.obs;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<AlistServerController>()) {
      Get.put(AlistServerController());
    }
    if (!Get.isRegistered<AlistUserController>()) {
      Get.put(AlistUserController(), permanent: true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setupServer();
    });
  }

  void _setupServer() {
    final serverCtrl = Get.find<AlistServerController>();
    final serverId = Get.arguments?['serverId'] as String?;
    if (serverId != null &&
        serverId.isNotEmpty &&
        serverCtrl.currentServerId.value != serverId) {
      serverCtrl.setDefault(serverId);
    }
    final server = serverCtrl.currentServer;
    if (server != null) {
      final userCtrl = Get.find<AlistUserController>();
      userCtrl.switchServer(
        server.id,
        serverUrl: server.serverUrl,
        ignoreSSLError: server.ignoreSSLError,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Obx(() => IndexedStack(
            index: _selectedIndex.value,
            children: const [
              AlistFileListWrapper(),
              AlistRecentsPage(),
              AlistFavoritePage(),
              AlistSettingsPage(),
            ],
          )),
      bottomNavigationBar: Obx(() {
        final style = SettingPref.navigationBarStyle;

        final alistNavigationBars = [
          _AlistNavItem(
            icon: Icons.folder_outlined,
            selectedIcon: Icons.folder,
            label: '文件',
          ),
          _AlistNavItem(
            icon: Icons.timelapse_outlined,
            selectedIcon: Icons.timelapse,
            label: '最近',
          ),
          _AlistNavItem(
            icon: Icons.star_outline,
            selectedIcon: Icons.star,
            label: '收藏',
          ),
          _AlistNavItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: '设置',
          ),
        ];

        // 1. 基础 NavigationBar
        final baseNavigationBar = NavigationBar(
          height: 56,
          elevation: 0,
          selectedIndex: _selectedIndex.value,
          onDestinationSelected: (index) => _selectedIndex.value = index,
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
          destinations: alistNavigationBars.map((item) {
            return NavigationDestination(
              tooltip: '',
              icon: Icon(item.icon, size: 24, color: colorScheme.outline),
              selectedIcon: Icon(
                item.selectedIcon,
                size: 24,
                color: colorScheme.primary,
              ),
              label: item.label,
            );
          }).toList(),
        );

        // 2. 紧凑风格 BottomNavigationBar
        final compactBottomBar = BottomNavigationBar(
          currentIndex: _selectedIndex.value,
          onTap: (index) => _selectedIndex.value = index,
          type: BottomNavigationBarType.fixed,
          iconSize: 16,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: alistNavigationBars.map((item) {
            return BottomNavigationBarItem(
              icon: Icon(item.icon, size: 16, color: colorScheme.outline),
              activeIcon: Icon(
                item.selectedIcon,
                size: 16,
                color: colorScheme.primary,
              ),
              label: item.label,
            );
          }).toList(),
        );

        // 3. 胶囊 NavigationBar
        final capsuleNavigationBar = NavigationBar(
          height: 70,
          elevation: 0,
          selectedIndex: _selectedIndex.value,
          onDestinationSelected: (index) => _selectedIndex.value = index,
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
          destinations: alistNavigationBars.map((item) {
            return NavigationDestination(
              tooltip: '',
              icon: Icon(item.icon, size: 24, color: colorScheme.outline),
              selectedIcon: Icon(
                item.selectedIcon,
                size: 24,
                color: colorScheme.primary,
              ),
              label: item.label,
            );
          }).toList(),
        );

        // 4. 根据样式选择
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
              selectedIndex: _selectedIndex.value,
              onDestinationSelected: (index) => _selectedIndex.value = index,
              backgroundColor: colorScheme.surface,
              bottomPadding: 8.0,
              destinations: alistNavigationBars.map((item) {
                return FloatingNavigationDestination(
                  label: item.label,
                  icon: Icon(item.icon, size: 24, color: colorScheme.outline),
                  selectedIcon: Icon(
                    item.selectedIcon,
                    size: 24,
                    color: colorScheme.primary,
                  ),
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

class _AlistNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _AlistNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}