import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/common/widgets/image/network_img_layer.dart';
import 'package:yuanying/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/audio/controllers/audio_controller.dart';
import 'package:yuanying/modules/audio/widgets/volume_button.dart';
import 'package:yuanying/plugin/pl_player/models/play_repeat.dart';
import 'package:yuanying/utils/duration_utils.dart';
import 'package:yuanying/utils/platform_utils.dart';

class AudioPage extends StatelessWidget {
  const AudioPage({super.key});

  static void toAudioPage({
    required List<AudioItem> playlist,
    int index = 0,
  }) {
    Get.to(
      () => const AudioPage(),
      arguments: {
        'playlist': playlist,
        'index': index,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(AudioController());
    final colorScheme = ColorScheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final bool isPortrait = size.width < size.height;
    final padding = MediaQuery.viewPaddingOf(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('音频播放'),
        actions: [
          IconButton(
            tooltip: '定时关闭',
            onPressed: () {
              SmartDialog.showToast('定时关闭功能开发中');
            },
            icon: const Icon(Icons.schedule, size: 22),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(
          left: 20 + padding.left,
          right: 20 + padding.right,
          bottom: 30 + padding.bottom,
        ),
        child: isPortrait
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildInfo(colorScheme)),
                  const SizedBox(height: 25),
                  _buildProgressBar(colorScheme),
                  _buildDuration(colorScheme),
                  _buildControls(controller),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _buildInfo(colorScheme)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 25),
                        _buildProgressBar(colorScheme),
                        _buildDuration(colorScheme),
                        _buildControls(controller),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildInfo(ColorScheme colorScheme) {
    final controller = Get.find<AudioController>();

    return Obx(() {
      if (controller.playlist.isEmpty) {
        return const Center(child: Text('暂无音频'));
      }

      final cover = controller.currentCover.value;
      final title = controller.currentTitle.value;
      final artist = controller.currentArtist.value;

      return Column(
        children: [
          Expanded(
            child: ListView(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    child: cover.isNotEmpty
                        ? NetworkImgLayer(
                            src: cover,
                            width: 170,
                            height: 170,
                          )
                        : Container(
                            width: 170,
                            height: 170,
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.music_note,
                              size: 64,
                              color: colorScheme.outline,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  artist.isNotEmpty ? artist : '未知艺术家',
                  style: TextStyle(fontSize: 14, color: colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _buildActionRow(colorScheme, controller),
                const SizedBox(height: 16),
                _buildPlaylistButton(controller),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _buildActionRow(ColorScheme colorScheme, AudioController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildActionButton(
          icon: Icons.sort,
          label: '排序',
          onTap: () => _showSortDialog(controller),
          colorScheme: colorScheme,
        ),
        const SizedBox(width: 30),
        Obx(
          () => _buildActionButton(
            icon: _getPlayModeIcon(controller.playMode.value),
            label: controller.playMode.value.label,
            onTap: controller.togglePlayMode,
            colorScheme: colorScheme,
          ),
        ),
        const SizedBox(width: 30),
        if (PlatformUtils.isDesktop) ...[
          VolumeButton(controller: controller),
        ] else ...[
          _buildActionButton(
            icon: Icons.volume_up,
            label: '音量',
            onTap: () => _showVolumeDialog(controller),
            colorScheme: colorScheme,
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistButton(AudioController controller) {
    return Obx(() {
      final count = controller.playlist.length;
      return GestureDetector(
        onTap: () => _showPlaylist(controller),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: ColorScheme.of(Get.context!).surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.playlist_play, size: 18),
              const SizedBox(width: 8),
              Text(
                '播放列表 ($count)',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_ios, size: 14),
            ],
          ),
        ),
      );
    });
  }

  IconData _getPlayModeIcon(PlayRepeat mode) {
    switch (mode) {
      case PlayRepeat.pause:
        return Icons.pause_circle_outline;
      case PlayRepeat.listOrder:
        return Icons.playlist_play;
      case PlayRepeat.singleCycle:
        return Icons.repeat_one;
      case PlayRepeat.listCycle:
        return Icons.repeat;
    }
  }

  void _showSortDialog(AudioController controller) {
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        title: const Text('排序'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AudioSortOrder.values.map((order) {
            final isSelected = controller.sortOrder.value == order;
            return ListTile(
              title: Text(order.label),
              trailing: isSelected
                  ? const Icon(Icons.check, color: Colors.blue)
                  : null,
              onTap: () {
                controller.onChangeSort(order);
                Get.back();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showPlaylist(AudioController controller) {
    final playlist = controller.playlist;
    if (playlist.isEmpty) return;

    showModalBottomSheet(
      context: Get.context!,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: min(640, MediaQuery.sizeOf(Get.context!).width),
      ),
      builder: (context) {
        final colorScheme = ColorScheme.of(context);
        return FractionallySizedBox(
          heightFactor: 0.7,
          alignment: Alignment.bottomCenter,
          child: Column(
            children: [
              InkWell(
                onTap: Get.back,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), // 替换 Style.bottomSheetRadius
                child: SizedBox(
                  height: 35,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: colorScheme.outline,
                        borderRadius: const BorderRadius.all(Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: playlist.length,
                  itemBuilder: (_, index) {
                    final item = playlist[index];
                    final isCurr = index == controller.currentIndex.value;
                    return ListTile(
                      dense: true,
                      minTileHeight: 45,
                      onTap: () {
                        Get.back();
                        controller.playIndex(index);
                      },
                      leading: isCurr
                          ? Icon(Icons.play_circle, color: colorScheme.primary)
                          : null,
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isCurr
                            ? TextStyle(
                                fontSize: 14,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              )
                            : const TextStyle(fontSize: 14),
                      ),
                      subtitle: item.artist != null
                          ? Text(
                              item.artist!,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
              Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: InkWell(
                  onTap: Get.back,
                  child: SizedBox(
                    height: 45,
                    child: Center(
                      child: Text(
                        '关闭',
                        style: TextStyle(color: colorScheme.outline),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVolumeDialog(AudioController controller) {
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        title: const Text('音量'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_down),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 1,
                    value: controller.desktopVolume.value,
                    onChanged: (value) => controller.setVolume(value),
                  ),
                ),
                const Icon(Icons.volume_up),
              ],
            ),
            Obx(
              () => Text(
                '${(controller.desktopVolume.value * 100).round()}%',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(ColorScheme colorScheme) {
    final controller = Get.find<AudioController>();
    final primary = colorScheme.primary;
    final thumbGlowColor = primary.withAlpha(80);
    final bufferedBarColor = primary.withValues(alpha: 0.4);
    final baseBarColor = colorScheme.brightness == Brightness.dark
        ? const Color(0x33FFFFFF)
        : const Color(0x33999999);

    return Obx(
      () => ProgressBar(
        progress: controller.position.value,
        total: controller.duration.value,
        baseBarColor: baseBarColor,
        progressBarColor: primary,
        bufferedBarColor: bufferedBarColor,
        thumbColor: primary,
        thumbGlowColor: thumbGlowColor,
        thumbGlowRadius: 0,
        thumbRadius: 6,
        onDragStart: (_) {},
        onDragUpdate: (details) {
          controller.position.value = details.timeStamp;
        },
        onSeek: (value) {
          controller.player?.seek(value);
        },
      ),
    );
  }

  Widget _buildDuration(ColorScheme colorScheme) {
    final controller = Get.find<AudioController>();

    return SizedBox(
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Obx(() {
            final pos = controller.position.value;
            return Text(
              DurationUtils.formatDuration(pos.inSeconds),
              style: TextStyle(fontSize: 13, color: colorScheme.outline),
            );
          }),
          Obx(() {
            final dur = controller.duration.value;
            return Text(
              DurationUtils.formatDuration(dur.inSeconds),
              style: TextStyle(fontSize: 13, color: colorScheme.outline),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildControls(AudioController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: controller.playPrev,
          icon: const Icon(size: 40, Icons.skip_previous_rounded),
        ),
        Obx(
          () => IconButton(
            onPressed: controller.playOrPause,
            icon: AnimatedIcon(
              size: 40,
              icon: controller.isPlaying.value
                  ? AnimatedIcons.pause_play
                  : AnimatedIcons.play_pause,
              progress: controller.animController,
            ),
          ),
        ),
        IconButton(
          onPressed: controller.playNext,
          icon: const Icon(size: 40, Icons.skip_next_rounded),
        ),
      ],
    );
  }
}