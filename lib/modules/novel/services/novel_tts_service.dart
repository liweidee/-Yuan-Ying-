import 'package:flutter_tts/flutter_tts.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/services/silence_keeper.dart';

class NovelTtsService extends GetxService {
  final FlutterTts _tts = FlutterTts();
  bool _inited = false;
  double rate = 0.5;
  String? _voiceKey;

  @override
  void onInit() {
    super.onInit();
    rate = StorageManager.getSetting<double>(SettingBoxKey.ttsRate) ?? 0.5;
    _voiceKey = StorageManager.getSetting<String>(SettingBoxKey.ttsVoiceKey);
    _init();
  }

  Future<void> _init() async {
    if (_inited) return;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(rate);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      if (_voiceKey != null) await _applyVoice(_voiceKey!);
      _inited = true;
    } catch (_) {}
  }

  Future<void> _applyVoice(String key) async {
    final parts = key.split('|');
    if (parts.length == 2) {
      await _tts.setVoice({'name': parts[0], 'locale': parts[1]});
    }
  }

  Future<List<Map<String, String>>> voices() async {
    await _init();
    final list = <Map<String, String>>[];
    try {
      final raw = await _tts.getVoices;
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            final m = {
              for (final e in item.entries) '${e.key}': '${e.value}',
            };
            list.add(m);
          }
        }
      }
    } catch (_) {}
    list.sort((a, b) {
      bool zh(Map<String, String> v) =>
          (v['locale'] ?? '').toLowerCase().startsWith('zh');
      if (zh(a) && !zh(b)) return -1;
      if (!zh(a) && zh(b)) return 1;
      return (a['name'] ?? '').compareTo(b['name'] ?? '');
    });
    return list;
  }

  String? get voiceKey => _voiceKey;

  Future<void> setVoice(String key) async {
    _voiceKey = key;
    await StorageManager.setSetting(SettingBoxKey.ttsVoiceKey, key);
    if (_inited) {
      try {
        await _applyVoice(key);
      } catch (_) {}
    }
  }

  Future<void> setRate(double r) async {
    rate = r;
    await StorageManager.setSetting(SettingBoxKey.ttsRate, r);
    if (_inited) {
      try {
        await _tts.setSpeechRate(r);
      } catch (_) {}
    }
  }

  Future<void> speakChunks(
    List<String> chunks, {
    required bool Function() isCancelled,
    void Function(int index)? onChunk,
  }) async {
    await _init();

    // 主动停止音乐播放，避免 TTS 与音乐同时播放
    await _stopMusicForTts();

    for (int i = 0; i < chunks.length; i++) {
      if (isCancelled()) break;
      onChunk?.call(i);
      try {
        await _tts.speak(chunks[i]);
      } catch (_) {
        break;
      }
    }
  }

  /// TTS 开始前停止音乐
  ///
  /// 跨平台通用：Android/iOS/桌面端都需要避免 TTS 与音乐混合。
  Future<void> _stopMusicForTts() async {
      // 1. 停止音乐播放器
      if (Get.isRegistered<MusicPlayerController>()) {
          try {
              final musicController = Get.find<MusicPlayerController>();
              if (musicController.isPlaying) {
                  await musicController.pause();
              }
          } catch (_) {}
      }
      // 2. 停止 iOS 静音保活引擎（Dart 封装已在非 iOS 平台 no-op）
      try {
          await SilenceKeeper.stop();
      } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}