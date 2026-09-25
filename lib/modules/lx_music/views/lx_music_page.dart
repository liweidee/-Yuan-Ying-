import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../../../common/widgets/floating_navigation_bar.dart';
import '../../../models/common/nav_bar_config.dart';
import '../../../modules/setting/models/setting_pref.dart';
import '../../music/views/music_player_view.dart';
import '../controllers/lx_board_controller.dart';
import '../controllers/lx_download_controller.dart';
import '../controllers/lx_music_controller.dart';
import '../controllers/lx_search_controller.dart';
import '../controllers/lx_songlist_controller.dart';
import '../controllers/lx_source_controller.dart';
import 'lx_board_tab.dart';
import 'lx_debug_log_page.dart';
import 'lx_download_tab.dart';
import 'lx_search_tab.dart';
import 'lx_settings_tab.dart';
import 'lx_source_manage_page.dart';
import 'lx_playlist_page.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/modules/lx_music/utils/lx_player_helper.dart';

/// 洛雪音乐主页面（底部导航 + IndexedStack + 全局播放条）
class LxMusicPage extends StatefulWidget {
  const LxMusicPage({super.key});

  @override
  State<LxMusicPage> createState() => _LxMusicPageState();
}

class _LxMusicPageState extends State<LxMusicPage> {
  final RxInt selectedIndex = 0.obs;

  /// 改为 late final，initState 里同步赋值
  late final LxMusicController _musicController;

  @override
  void initState() {
    super.initState();
    // 同步注册 controller（各 controller 的 onInit 里 Rx 修改已包 microtask，安全）
    _musicController = Get.put(LxMusicController());
    if (!Get.isRegistered<LxSearchController>()) {
      Get.put(LxSearchController());
    }
    if (!Get.isRegistered<LxSonglistController>()) {
      Get.put(LxSonglistController());
    }
    if (!Get.isRegistered<LxBoardController>()) {
      Get.put(LxBoardController());
    }
    if (!Get.isRegistered<LxSourceController>()) {
      Get.put(LxSourceController());
    }
    if (!Get.isRegistered<LxDownloadController>()) {
      Get.put(LxDownloadController());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Get.back(),
          tooltip: '返回',
        ),
        title: Obx(() => Text(
              _navItems[selectedIndex.value].label,
              style: const TextStyle(fontSize: 18),
            )),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '我的歌单',
            icon: const Icon(Icons.library_music_rounded, size: 22),
            onPressed: () => Get.to(() => const LxPlaylistPage()),
          ),
          IconButton(
            tooltip: '自定义源',
            icon: const Icon(Icons.code_rounded, size: 22),
            onPressed: () => Get.to(() => const LxSourceManagePage()),
          ),
          IconButton(
            tooltip: '调试日志',
            icon: const Icon(Icons.bug_report_outlined, size: 22),
            onPressed: () => Get.to(() => const LxDebugLogPage()),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              if (!_musicController.engineReady.value) {
                return const Center(child: CircularProgressIndicator());
              }
              return IndexedStack(
                index: selectedIndex.value,
                children: const [
                  LxBoardTab(),
                  LxSearchTab(),
                  LxDownloadTab(),
                  LxSettingsTab(),
                ],
              );
            }),
          ),
          // 全局播放条：仅在"本次会话播过洛雪歌曲" + "当前是洛雪渠道"时显示
          Obx(() {
            if (!LxPlayerHelper.hasPlayedInSession.value) {
              return const SizedBox.shrink();
            }
            final controller = Get.find<MusicPlayerController>();
            if (!controller.isLxChannel) {
              return const SizedBox.shrink();
            }
            return MusicPlayerView(
              cancelMargin: true,
              onClose: () {
                // 暂停播放 + 隐藏底条（保留队列）
                controller.pause();
                LxPlayerHelper.hasPlayedInSession.value = false;
                SmartDialog.showToast('已停止播放');
              },
            );
          }),
        ],
      ),
      bottomNavigationBar: Obx(() {
        final style = SettingPref.navigationBarStyle;
        final idx = selectedIndex.value;

        final baseNavigationBar = NavigationBar(
          height: 56,
          elevation: 0,
          selectedIndex: idx,
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
          destinations: _navItems.map((item) {
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
          currentIndex: idx,
          onTap: (i) => selectedIndex.value = i,
          type: BottomNavigationBarType.fixed,
          iconSize: 16,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: _navItems.map((item) {
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
          selectedIndex: idx,
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
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return Colors.transparent;
            }
            return null;
          }),
          destinations: _navItems.map((item) {
            return NavigationDestination(
              tooltip: '',
              icon: Icon(item.icon, size: 24, color: colorScheme.outline),
              selectedIcon: Icon(item.selectedIcon,
                  size: 24, color: colorScheme.primary),
              label: item.label,
            );
          }).toList(),
        );

        switch (style) {
          case NavigationBarStyle.default_:
            return baseNavigationBar;
          case NavigationBarStyle.defaultCompact:
            return compactBottomBar;
          case NavigationBarStyle.floating:
            return FloatingNavigationBar(
              selectedIndex: idx,
              onDestinationSelected: (i) => selectedIndex.value = i,
              backgroundColor: colorScheme.surface,
              bottomPadding: 8.0,
              destinations: _navItems.map((item) {
                return FloatingNavigationDestination(
                  label: item.label,
                  icon:
                      Icon(item.icon, size: 24, color: colorScheme.outline),
                  selectedIcon: Icon(item.selectedIcon,
                      size: 24, color: colorScheme.primary),
                );
              }).toList(),
            );
          case NavigationBarStyle.capsule:
          default:
            return capsuleNavigationBar;
        }
      }),
    );
  }
}

class _LxNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _LxNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

const List<_LxNavItem> _navItems = [
  _LxNavItem(
    icon: Icons.leaderboard_outlined,
    selectedIcon: Icons.leaderboard,
    label: '榜单',
  ),
  _LxNavItem(
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
    label: '搜索',
  ),
  _LxNavItem(
    icon: Icons.download_outlined,
    selectedIcon: Icons.download,
    label: '下载',
  ),
  _LxNavItem(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: '设置',
  ),
];