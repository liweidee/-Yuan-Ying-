// lib/modules/live/views/live_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/live/controllers/live_controller.dart';
import 'package:yuanying/modules/live/widgets/live_player_view.dart';
import 'package:yuanying/modules/live/widgets/live_group_list.dart';
import 'package:yuanying/modules/live/widgets/live_channel_list.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  late final LiveController controller;
  final GlobalKey _playerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<LiveController>(tag: 'live')) {
      Get.put(LiveController(), tag: 'live', permanent: true);
    }
    controller = Get.find<LiveController>(tag: 'live');
    controller.ensurePlayerInitialized();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 有数据则静默刷新，无数据则显示 loading
      final hasData = controller.channels.isNotEmpty;
      final hasError = controller.errorMessage.value.isNotEmpty;

      if (hasData && !hasError) {
        // 已有数据：静默刷新（不显示 loading）
        controller.refreshChannels(showLoading: false);
      } else {
        // 首次进入或错误状态：显示 loading
        controller.refreshChannels(showLoading: true);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final bool isFullScreen = controller.isFullScreen.value;
      final bool isLoading = controller.isLoading.value;
      final String errorMsg = controller.errorMessage.value;
      final bool hasChannels = controller.channels.isNotEmpty;

      if (isFullScreen) {
        return const Scaffold(
          backgroundColor: Colors.transparent,
          body: SizedBox.shrink(),
        );
      }

      if (isLoading) {
        return Scaffold(
          appBar: null,
          body: Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      }

      if (errorMsg.isNotEmpty || !hasChannels) {
        return _buildErrorPage(context);
      }

      return _buildNormalContent(context);
    });
  }

  Widget _buildErrorPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: null,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '直播接口请求失败',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                controller.errorMessage.value.isNotEmpty
                    ? controller.errorMessage.value
                    : '请检查网络或配置',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  await Get.toNamed(AppPages.liveConfig);
                  // 从配置页返回，强制显示 loading 重新加载
                  controller.refreshChannels(showLoading: true);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('直播配置'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNormalContent(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final removeSafeArea = PlayerPref.removeSafeArea;
    final double topPadding = removeSafeArea ? 0.0 : viewPadding.top;

    return Scaffold(
      appBar: null,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isDesktop = constraints.maxWidth > 800;
          final Widget playerWidget = LivePlayerView(
            key: _playerKey,
            isFullScreen: false,
          );

          if (isDesktop) {
            return _buildDesktopLayout(playerWidget);
          } else {
            return _buildMobileLayout(playerWidget, topPadding);
          }
        },
      ),
    );
  }

  Widget _buildMobileLayout(Widget playerWidget, double topPadding) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (topPadding > 0) SizedBox(height: topPadding),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: playerWidget,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                LiveGroupList(width: 110, isDesktop: false),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                    ),
                    child: const LiveChannelList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(Widget playerWidget) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color shadowColor = Theme.of(context).shadowColor;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 320,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: shadowColor.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  LiveGroupList(width: 120, isDesktop: true),
                  Expanded(
                    child: Container(
                      color: colorScheme.surface,
                      child: const LiveChannelList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: playerWidget,
              ),
            ),
          ),
        ],
      ),
    );
  }
}