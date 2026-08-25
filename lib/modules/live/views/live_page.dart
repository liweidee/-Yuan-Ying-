// lib/modules/live/views/live_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/live/controllers/live_controller.dart';
import 'package:yuanying/modules/live/widgets/live_player_view.dart';
import 'package:yuanying/modules/live/widgets/live_group_list.dart';
import 'package:yuanying/modules/live/widgets/live_channel_list.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  late final LiveController controller;

  @override
  void initState() {
    super.initState();
    Get.lazyPut<LiveController>(() => LiveController(), tag: 'live');
    controller = Get.find<LiveController>(tag: 'live');
    controller.ensurePlayerInitialized();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.refreshChannels();
    });
  }

  @override
  void dispose() {
    // 如果当前正在播放，暂停并标记为用户主动暂停，阻止自动恢复
    if (controller.isPlaying.value) {
      controller.pause(markUserPaused: true);
    }
    // 如果已经暂停，不做任何操作，保留 userPaused 状态（可能已经是 true）
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 每次 build 后尝试恢复播放，但仅当不是用户主动暂停时
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.userPaused.value && 
          controller.currentChannel.value != null && 
          !controller.isPlaying.value) {
        controller.resumeIfNeeded();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final config = controller.currentConfig.value;
          return Text(config != null ? '${config.name}' : '直播');
        }),
        centerTitle: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.refreshChannels,
            tooltip: '刷新频道',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 800;
          if (isDesktop) {
            return _buildDesktopLayout(context);
          } else {
            return _buildMobileLayout(context);
          }
        },
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        const AspectRatio(
          aspectRatio: 16 / 9,
          child: LivePlayerView(showFullscreenBtn: true),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                LiveGroupList(width: 76, isDesktop: false),
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

  Widget _buildDesktopLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shadowColor = Theme.of(context).shadowColor;

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
                  LiveGroupList(width: 90, isDesktop: true),
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
                child: const LivePlayerView(showFullscreenBtn: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}