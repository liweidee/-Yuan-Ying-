import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// 音乐播放器专用的 iOS 音频会话协调器。
///
/// Android 继续由 audio_service、MediaSession 和前台服务管理，
/// 这里保持 no-op，避免改变现有音频焦点行为。
class PlaybackAudioSession {
  PlaybackAudioSession._();

  static final PlaybackAudioSession instance = PlaybackAudioSession._();

  Future<void> activateForPlayback() async {
    if (!Platform.isIOS) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
    } catch (error) {
      debugPrint('[PlaybackAudioSession] activate failed: $error');
    }
  }

  /// 暂停时保留会话，让系统控制栏仍可恢复播放。
  ///
  /// 这里不会创建静音音频或额外播放引擎。
  Future<void> keepForPause() async {
    if (!Platform.isIOS) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
    } catch (error) {
      debugPrint('[PlaybackAudioSession] keep paused session failed: $error');
    }
  }

  Future<void> deactivateAndNotifyOthers() async {
    if (!Platform.isIOS) return;
    try {
      final session = await AudioSession.instance;
      await session.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    } catch (error) {
      debugPrint('[PlaybackAudioSession] deactivate failed: $error');
    }
  }
}
