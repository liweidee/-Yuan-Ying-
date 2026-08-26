// lib/modules/live/widgets/live_player_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart' show NoVideoControls, Video;
import 'package:yuanying/modules/live/controllers/live_controller.dart';
import 'package:yuanying/utils/platform_utils.dart';

class LivePlayerView extends StatelessWidget {
  final bool isFullScreen;

  const LivePlayerView({
    super.key,
    this.isFullScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<LiveController>(tag: 'live');
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

    Widget playerContent = Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ===== 视频渲染层 =====
          if (ctrl.videoController != null)
            Obx(() => Video(
              controller: ctrl.videoController!,
              controls: NoVideoControls,
              fit: ctrl.videoFit.value,
            )),

          // ===== 加载/缓冲指示 =====
          Obx(() {
            if (ctrl.isLoading.value || ctrl.isBuffering.value) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            return const SizedBox.shrink();
          }),

          // ===== 空状态 =====
          Obx(() {
            if (ctrl.channels.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tv_off, size: 48, color: Colors.white54),
                    const SizedBox(height: 8),
                    Text(
                      '暂无频道',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          }),

          // ===== 底部自定义控制栏 =====
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.only(bottom: isFullScreen ? 0 : bottomSafe),
              child: _buildControls(ctrl),
            ),
          ),
        ],
      ),
    );

    // ===== 桌面端鼠标交互 =====
    if (PlatformUtils.isDesktop) {
      return Obx(() {
        final showControls = ctrl.controlsVisible.value;
        final fullScreen = ctrl.isFullScreen.value;
        return MouseRegion(
          cursor: !showControls && fullScreen
              ? SystemMouseCursors.none
              : MouseCursor.defer,
          onEnter: (_) => ctrl.showControls(),
          onHover: (_) => ctrl.showControls(),
          onExit: (_) => ctrl.hideControls(),
          child: playerContent,
        );
      });
    }

    // ===== 移动端点击显示控制条 =====
    return GestureDetector(
      onTap: () => ctrl.showControls(),
      child: playerContent,
    );
  }

  // ============================================================
  // 底部控制栏构建
  // ============================================================

  Widget _buildControls(LiveController ctrl) {
    return Obx(() {
      return AnimatedOpacity(
        opacity: ctrl.controlsVisible.value ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: IgnorePointer(
          ignoring: !ctrl.controlsVisible.value,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.7), Colors.transparent],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildProgressRow(ctrl),
                const SizedBox(height: 4),
                _buildButtonRow(ctrl),
              ],
            ),
          ),
        ),
      );
    });
  }

  // ============================================================
  // 进度行（纯展示，不可拖动）
  // ============================================================

  Widget _buildProgressRow(LiveController ctrl) {
    return Row(
      children: [
        Obx(() => Text(
          ctrl.formatDuration(ctrl.position.value),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        )),
        const SizedBox(width: 8),
        Expanded(
          child: Obx(() {
            final dur = ctrl.duration.value;
            final pos = ctrl.position.value;
            final double max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
            final double value = pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble();

            return SliderTheme(
              data: SliderThemeData(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
              ),
              child: Slider(
                value: value / max,
                min: 0,
                max: 1,
                onChanged: null,
              ),
            );
          }),
        ),
        const SizedBox(width: 8),
        Obx(() => Text(
          ctrl.formatDuration(ctrl.duration.value),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        )),
      ],
    );
  }

  // ============================================================
  // 按钮行
  // ============================================================

  Widget _buildButtonRow(LiveController ctrl) {
    return Row(
      children: [
        // 播放/暂停
        Obx(() => IconButton(
          icon: Icon(
            ctrl.isPlaying.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 22,
          ),
          onPressed: ctrl.togglePlayPause,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        )),
        const SizedBox(width: 8),

        // 频道名
        Obx(() => Expanded(
          child: Text(
            ctrl.currentChannel.value?.name ?? '未选择频道',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        )),

        // 画面比例下拉菜单
        Obx(() => PopupMenuButton<BoxFit>(
          tooltip: '画面比例',
          requestFocus: false,
          initialValue: ctrl.videoFit.value,
          color: Colors.black.withOpacity(0.8),
          itemBuilder: (context) {
            final fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
            return fits.map((fit) => PopupMenuItem<BoxFit>(
              height: 35,
              padding: const EdgeInsets.only(left: 30),
              value: fit,
              onTap: () => ctrl.setVideoFit(fit),
              child: Text(
                ctrl.getFitName(fit),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
              ),
            )).toList();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              ctrl.getFitName(ctrl.videoFit.value),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
        )),

        // 全屏
        Obx(() => IconButton(
          icon: Icon(
            ctrl.isFullScreen.value ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            color: Colors.white,
            size: 22,
          ),
          onPressed: () => ctrl.toggleFullScreen(Get.context!),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: ctrl.isFullScreen.value ? '退出全屏' : '全屏',
        )),
      ],
    );
  }
}