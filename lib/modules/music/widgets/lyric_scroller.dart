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
/// 关键修复（高亮跳动）：
/// 1. 缓存 `UINetease` —— 生命周期内只创建一次，避免 flutter_lyric 内部状态被重置
/// 2. 缓存 `LyricsModel` —— 只在歌词文本变化时重新解析
/// 3. 只在 position 真正变化时才 setState
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
  Worker? _lyricWorker;

  /// 本地缓存的 position，避免频繁读取 getter
  Duration _position = Duration.zero;

  /// 缓存解析后的 model——仅当歌词文本变化时重新构建
  dynamic _cachedModel;
  String? _cachedLyricText;

  /// 缓存 UI 对象——**修复跳动的核心**
  /// UINetease 的颜色是内部硬编码的，构造参数只控制尺寸/行高
  final UINetease _lyricUi = UINetease(defaultSize: 16);

  @override
  void initState() {
    super.initState();

    // 播放进度：只在 position 变化时 setState
    _posSub = _musicController.positionStream.listen((pos) {
      if (!mounted) return;
      if (pos == _position) return;
      setState(() => _position = pos);
    });

    // 播放/暂停切换：需要一次刷新让 flutter_lyric 感知 playing 变化
    _playingWorker = ever(_musicController.playing, (_) {
      if (mounted) setState(() {});
    });

    // 歌词文本变化：清空 model 缓存，重新解析
    _lyricWorker = ever(_musicController.lyric, (_) {
      _cachedModel = null;
      _cachedLyricText = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _playingWorker?.dispose();
    _lyricWorker?.dispose();
    super.dispose();
  }

  /// 缓存式构建 LyricsModel
  dynamic _getModel(String lyricText) {
    if (_cachedLyricText == lyricText && _cachedModel != null) {
      return _cachedModel;
    }
    try {
      _cachedModel = LyricsModelBuilder.create()
          .bindLyricToMain(lyricText)
          .getModel();
      _cachedLyricText = lyricText;
      return _cachedModel;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final size = Size(screenSize.width, screenSize.height - 200);

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

    final model = _getModel(lyricText);
    if (model == null) {
      return _buildEmptyState('歌词格式解析失败');
    }

    return LyricsReader(
      model: model,
      position: _position.inMilliseconds,
      lyricUi: _lyricUi, // ★ 缓存的 UI 对象（而不是每次 new）
      playing: _musicController.playing.value,
      size: size,
      padding: const EdgeInsets.symmetric(horizontal: 40),
    );
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