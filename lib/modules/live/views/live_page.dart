// lib/modules/live/views/live_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
      controller.refreshChannels();
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
      final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
      final bool removeSafeArea = PlayerPref.removeSafeArea;
      final double topPadding = isFullScreen ? 0.0 : (removeSafeArea ? 0.0 : viewPadding.top);

      if (isFullScreen) {
        return const Scaffold(
          backgroundColor: Colors.transparent,
          body: SizedBox.shrink(),
        );
      }

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
    });
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