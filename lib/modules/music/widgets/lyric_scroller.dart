// lib/modules/music/widgets/lyric_scroller.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_lyric/lyric_ui/ui_netease.dart';
import 'package:flutter_lyric/lyrics_model_builder.dart';
import 'package:flutter_lyric/lyrics_reader_widget.dart';

import 'package:yuanying/modules/music/controllers/music_player_controller.dart';

/// 歌词滚动页
///
/// flutter_lyric 2.0.4+6 API 说明：
/// - `LyricReaderState` 没有暴露 `updatePosition` 或 `updatePlaying` 方法
/// - 正确的方式是在 `position` 或 `playing` 变化时，通过 `setState` 触发重建，
///   并将新的值作为 `LyricsReader` 的参数传入。
class LyricScroller extends StatefulWidget {
  const LyricScroller({super.key});

  @override
  State<LyricScroller> createState() => _LyricScrollerState();
}

class _LyricScrollerState extends State<LyricScroller> {
  final MusicPlayerController _musicController =
      Get.find<MusicPlayerController>();

  StreamSubscription<Duration>? _posSub;
  Worker? _playingWorker;

  @override
  void initState() {
    super.initState();

    // 监听播放进度，有变化时触发 setState 重建
    _posSub = _musicController.positionStream.listen((pos) {
      if (mounted) {
        setState(() {});
      }
    });

    // 监听播放/暂停状态，有变化时触发 setState 重建
    _playingWorker = ever(_musicController.playing, (playing) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playingWorker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final size = Size(screenSize.width, screenSize.height - 200);

    return Obx(() {
      final lyricText = _musicController.lyric.value;
      final isLoading = _musicController.isLoading.value;

      if (isLoading) {
        return const Center(
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

      if (lyricText.isEmpty) {
        return _buildEmptyState('暂无歌词');
      }

      try {
        final model = LyricsModelBuilder.create()
            .bindLyricToMain(lyricText)
            .getModel();

        // 在每次 setState 重建时，传入最新的 position 和 playing 值
        return LyricsReader(
          model: model,
          position: _musicController.position.inMilliseconds,
          lyricUi: UINetease(defaultSize: 16),
          playing: _musicController.playing.value,
          size: size,
          padding: const EdgeInsets.symmetric(horizontal: 40),
        );
      } catch (_) {
        return _buildEmptyState('歌词格式解析失败');
      }
    });
  }

  Widget _buildEmptyState(String message) {
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
          if (_musicController.currentEpisode != null)
            Text(
              '当前播放：${_musicController.currentEpisode!.name}',
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