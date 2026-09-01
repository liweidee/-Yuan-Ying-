// lib/modules/music/widgets/lyric_scroller.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_lyric/lyric_ui/ui_netease.dart';
import 'package:flutter_lyric/lyrics_model_builder.dart';
import 'package:flutter_lyric/lyrics_reader_widget.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';

class LyricScroller extends StatelessWidget {
  const LyricScroller({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MusicPlayerController>();
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Obx(() {
      final lyricText = controller.lyric.value;
      final hasLyric = lyricText.isNotEmpty;

      if (controller.isLoading.value) {
        return Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white54,
            ),
          ),
        );
      }

      if (hasLyric) {
        try {
          final model = LyricsModelBuilder.create()
              .bindLyricToMain(lyricText)
              .getModel();

          return LyricsReader(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            model: model,
            position: controller.position.inMilliseconds,
            lyricUi: UINetease(defaultSize: 16),
            playing: controller.playing.value,
            size: Size(
              screenWidth,
              screenHeight - 200,
            ),
          );
        } catch (e) {
          return _buildEmptyState(controller, '歌词格式解析失败');
        }
      } else {
        return _buildEmptyState(controller, '暂无歌词');
      }
    });
  }

  Widget _buildEmptyState(MusicPlayerController controller, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          if (controller.currentEpisode != null)
            Text(
              '当前播放：${controller.currentEpisode!.name}',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }
}