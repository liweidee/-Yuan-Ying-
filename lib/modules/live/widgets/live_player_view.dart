// lib/modules/live/widgets/live_player_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:yuanying/modules/live/controllers/live_controller.dart';
import 'package:yuanying/utils/platform_utils.dart';

class LivePlayerView extends StatefulWidget {
  final bool showFullscreenBtn;
  final bool isFullScreen;

  const LivePlayerView({
    super.key,
    this.showFullscreenBtn = false,
    this.isFullScreen = false,
  });

  @override
  State<LivePlayerView> createState() => _LivePlayerViewState();
}

class _LivePlayerViewState extends State<LivePlayerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controlsAnimationController;
  final RxBool _controlsVisible = false.obs;

  @override
  void initState() {
    super.initState();
    _controlsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    if (!PlatformUtils.isDesktop) {
      _controlsVisible.value = false;
    }
  }

  @override
  void dispose() {
    _controlsAnimationController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    if (PlatformUtils.isDesktop) return;
    _controlsVisible.value = !_controlsVisible.value;
  }

  void _showControls() {
    if (!_controlsVisible.value) {
      _controlsVisible.value = true;
    }
  }

  void _hideControls() {
    if (_controlsVisible.value) {
      _controlsVisible.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<LiveController>(tag: 'live');
    final colorScheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.viewPaddingOf(context);
    final bottomSafe = padding.bottom;

    final videoController = ctrl.videoController;

    Widget playerContent = Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoController != null)
            Video(controller: videoController)
          else
            const Center(child: Text('加载中...', style: TextStyle(color: Colors.white))),
          Obx(() {
            if (ctrl.isLoading.value || ctrl.isBuffering.value) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }
            return const SizedBox.shrink();
          }),
          Obx(() {
            if (ctrl.channels.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tv_off, size: 48, color: Colors.white54),
                    const SizedBox(height: 8),
                    Text('暂无频道', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          }),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.isFullScreen ? 0 : bottomSafe),
              child: _buildControls(ctrl, colorScheme),
            ),
          ),
        ],
      ),
    );

    if (PlatformUtils.isDesktop) {
      playerContent = MouseRegion(
        onEnter: (_) => _showControls(),
        onExit: (_) => _hideControls(),
        child: playerContent,
      );
    } else {
      playerContent = GestureDetector(
        onTap: _toggleControls,
        child: playerContent,
      );
    }

    return playerContent;
  }

  Widget _buildControls(LiveController ctrl, ColorScheme colorScheme) {
    return AnimatedOpacity(
      opacity: _controlsVisible.value ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: IgnorePointer(
        ignoring: !_controlsVisible.value,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withOpacity(0.7),
                Colors.transparent,
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Obx(() => IconButton(
                    icon: Icon(
                      ctrl.isPlaying.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: ctrl.togglePlayPause,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )),
              const SizedBox(width: 8),
              Obx(() => Expanded(
                    child: Text(
                      ctrl.currentChannel.value?.name ?? '未选择频道',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
              if (widget.showFullscreenBtn)
                Obx(() => IconButton(
                      icon: Icon(
                        ctrl.isFullScreen.value ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () => ctrl.toggleFullScreen(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: ctrl.isFullScreen.value ? '退出全屏' : '全屏',
                    )),
            ],
          ),
        ),
      ),
    );
  }
}