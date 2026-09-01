// lib/modules/music/services/music_player.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/modules/music/services/music_source.dart';
import 'package:yuanying/utils/toast_utils.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/core/constants/storage_keys.dart';

class MusicPlayer {
  // 暴露内部 AudioPlayer 给 AudioPlayerHandler 使用
  AudioPlayer get audio => _audio;
  final AudioPlayer _audio = AudioPlayer();
  
  Episode? current;
  bool isLoading = false;

  // ===== 播放状态流 =====
  final _playingController = StreamController<bool>.broadcast();
  Stream<bool> get playingStream => _playingController.stream;

  // ===== 播放完成回调 =====
  VoidCallback? onPlayCompleted;

  // ===== 公共属性 =====
  bool get isPlaying => _audio.playing;
  Duration get position => _audio.position;
  Duration get duration => _audio.duration ?? Duration.zero;
  Stream<Duration> get positionStream => _audio.positionStream;

  MusicPlayer() {
    _audio.playerStateStream.listen((state) {
      _playingController.add(_audio.playing);
      if (state.processingState == ProcessingState.completed) {
        onPlayCompleted?.call();
      }
    });
  }

  // ===== 初始化 =====
  Future<void> init() async {
    final pos = StorageManager.getSetting<int>(SettingBoxKey.musicPlayerPosition) ?? 0;
    if (pos > 0) {
      await _audio.seek(Duration(milliseconds: pos));
    }
  }

  // ===== 播放 =====
  Future<void> play({Episode? music, String? url, Map<String, String>? headers}) async {
    if (music == null) {
      await _audio.play();
      return;
    }

    current = music;
    isLoading = true;

    try {
      await _audio.stop();
      final playUrl = url ?? music.url;
      await _audio.setUrl(playUrl, headers: headers ?? {});
      await _audio.play();
    } catch (e) {
      if (e is PlayerInterruptedException) {
        return;
      }
      ToastUtils.show('播放失败：$e');
    } finally {
      isLoading = false;
    }
  }

  // ===== 暂停 =====
  Future<void> pause() async {
    await _audio.pause();
  }

  // ===== 恢复 =====
  Future<void> resume() async {
    await _audio.play();
  }

  // ===== 停止 =====
  Future<void> stop() async {
    await _audio.stop();
  }

  // ===== 跳转 =====
  Future<void> seek(Duration position) async {
    await _audio.seek(position);
  }

  // ===== 上一首/下一首（供 AudioPlayerHandler 调用） =====
  Future<void> prev() async {
    // 由 MusicPlayerController 处理，这里空实现
  }

  Future<void> next() async {
    // 由 MusicPlayerController 处理，这里空实现
  }

  // ===== 重置 =====
  Future<void> reset() async {
    try {
      await _audio.stop();
      await _audio.seek(Duration.zero);
    } catch (_) {}
  }

  // ===== 销毁 =====
  void dispose() {
    _audio.dispose();
    _playingController.close();
  }
}