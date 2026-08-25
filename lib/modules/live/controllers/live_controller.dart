// lib/modules/live/controllers/live_controller.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:window_manager/window_manager.dart';

import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/models/live/live_config.dart';
import 'package:yuanying/modules/live/models/live_channel.dart';
import 'package:yuanying/modules/live/services/live_parser_service.dart';
import 'package:yuanying/modules/live/widgets/full_screen_live_player.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/platform_utils.dart';

class LiveController extends GetxController {
  Player? _player;
  VideoController? _videoController;
  bool _isPlayerInitialized = false;

  final Rx<LiveConfig?> currentConfig = Rx(null);
  final RxList<LiveChannel> channels = <LiveChannel>[].obs;
  final RxList<String> groups = <String>[].obs;
  final RxString selectedGroup = ''.obs;
  final Rx<LiveChannel?> currentChannel = Rx(null);
  final RxBool isPlaying = false.obs;
  final RxBool isLoading = false.obs;
  final RxBool isBuffering = false.obs;
  final RxBool isFullScreen = false.obs;
  final RxBool userPaused = false.obs; // 用户主动暂停标志

  OverlayEntry? _fullScreenOverlay;
  bool _isFirstLoad = true;
  bool _isPlayingChannel = false;
  bool _wasPlayingBeforeFullScreen = false;

  Map<String, String> get _buffer {
    final bufSec = 120.0;
    final bufSiz = (64 * 0x100000).toStringAsFixed(0);
    return {
      'cache': 'yes',
      'cache-secs': bufSec.toStringAsFixed(3),
      'demuxer-hysteresis-secs': (bufSec / 1.5).toStringAsFixed(3),
      'demuxer-max-bytes': bufSiz,
      'demuxer-max-back-bytes': bufSiz,
      'demuxer-readahead-secs': '30',
    };
  }

  VideoController? get videoController => _videoController;

  void ensurePlayerInitialized() {
    if (!_isPlayerInitialized) _initPlayer();
  }

  @override
  void onInit() {
    super.onInit();
    _initPlayer();
    _loadConfigAndChannels();
  }

  void _initPlayer() {
    if (_isPlayerInitialized) return;
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
        protocolWhitelist: const [
          'file', 'http', 'https', 'tcp', 'tls',
          'crypto', 'hls', 'applehttp', 'udp', 'rtp', 'data'
        ],
        logLevel: MPVLogLevel.error,
      ),
    );
    _videoController = VideoController(_player!);
    _isPlayerInitialized = true;

    _player!.stream.playing.listen((playing) {
      isPlaying.value = playing;
      if (playing) userPaused.value = false;
    });
    _player!.stream.buffering.listen((buffering) => isBuffering.value = buffering);
    _player!.stream.error.listen((error) {
      SmartDialog.showToast('播放失败: $error');
    });
    _player!.stream.completed.listen((_) {});
  }

  /// 暂停播放
  /// [markUserPaused] 是否标记为用户主动暂停，默认为 true（用户点击暂停时使用）
  void pause({bool markUserPaused = true}) {
    if (_player != null && isPlaying.value) {
      if (markUserPaused) {
        userPaused.value = true;
      }
      _player!.pause();
    }
  }

  /// 恢复播放（只恢复，不重新打开媒体）
  void resumeIfNeeded() {
    if (_player != null && !isPlaying.value && !userPaused.value && currentChannel.value != null) {
      _player!.play();
    }
  }

  /// 重置播放器（配置切换且新列表为空时调用，销毁并重建）
  void resetPlayer() {
    if (_player != null) {
      _player!.stop();
      _player!.dispose();
      _player = null;
      _videoController = null;
      _isPlayerInitialized = false;
      currentChannel.value = null;
      isPlaying.value = false;
      userPaused.value = false;
      isLoading.value = false;
      isBuffering.value = false;
      groups.clear();
      channels.clear();
      selectedGroup.value = '';
      _initPlayer();
    }
  }

  Future<void> _loadConfigAndChannels() async {
    final configKey = StorageManager.getSetting<String>(SettingBoxKey.liveCurrentKey);
    if (configKey == null || configKey.isEmpty) {
      final configs = StorageManager.getSetting<List<dynamic>>(SettingBoxKey.liveConfigs) ?? [];
      if (configs.isNotEmpty) {
        final first = LiveConfig.fromJson(Map<String, dynamic>.from(configs.first));
        currentConfig.value = first;
        await _loadChannelsFromRemote(first);
      } else {
        currentConfig.value = null;
        channels.clear();
        groups.clear();
        selectedGroup.value = '';
        _isFirstLoad = true;
        resetPlayer();
      }
    } else {
      final configs = StorageManager.getSetting<List<dynamic>>(SettingBoxKey.liveConfigs) ?? [];
      LiveConfig? found;
      for (var item in configs) {
        final config = LiveConfig.fromJson(Map<String, dynamic>.from(item));
        if (config.key == configKey) {
          found = config;
          break;
        }
      }
      if (found != null) {
        currentConfig.value = found;
        await _loadChannelsFromRemote(found);
      } else {
        currentConfig.value = null;
        channels.clear();
        groups.clear();
        selectedGroup.value = '';
        _isFirstLoad = true;
        resetPlayer();
      }
    }
  }

  Future<void> _loadChannelsFromRemote(LiveConfig config) async {
    if (config.url.isEmpty) {
      channels.clear();
      groups.clear();
      selectedGroup.value = '';
      _isFirstLoad = true;
      resetPlayer();
      return;
    }

    isLoading.value = true;
    try {
      final response = await Dio().get(
        config.url,
        options: Options(
          headers: config.ua != null ? {'User-Agent': config.ua} : null,
        ),
      );
      final content = response.data is String ? response.data as String : response.data.toString();
      final parsed = LiveParserService.parse(content);
      if (parsed.isEmpty) {
        SmartDialog.showToast('未解析到任何频道，请检查直播源');
        channels.clear();
        groups.clear();
        selectedGroup.value = '';
        resetPlayer();
        return;
      }
      channels.assignAll(parsed);
      _updateGroups();

      if (channels.isNotEmpty && currentChannel.value == null) {
        _playChannelInternal(channels.first);
      }
    } catch (e) {
      SmartDialog.showToast('加载直播源失败: $e');
      channels.clear();
      groups.clear();
      selectedGroup.value = '';
      _isFirstLoad = true;
      resetPlayer();
    } finally {
      isLoading.value = false;
    }
  }

  void _updateGroups() {
    final groupSet = <String>{};
    for (var ch in channels) {
      groupSet.add(ch.group);
    }
    final groupList = groupSet.toList();
    groups.assignAll(groupList);

    final currentSelected = selectedGroup.value;

    if (groups.isEmpty) {
      selectedGroup.value = '';
      _isFirstLoad = true;
      return;
    }

    if (groups.contains(currentSelected) && currentSelected.isNotEmpty) {
      return;
    }

    selectedGroup.value = groups.first;
    _isFirstLoad = false;
  }

  List<LiveChannel> get currentGroupChannels {
    if (selectedGroup.value.isEmpty) return [];
    return channels.where((ch) => ch.group == selectedGroup.value).toList();
  }

  Future<void> refreshChannels() async {
    await _loadConfigAndChannels();
  }

  void playChannel(LiveChannel channel) {
    if (!_isPlayerInitialized) _initPlayer();
    if (_isPlayingChannel) return;
    if (currentChannel.value?.url == channel.url && isPlaying.value) return;
    userPaused.value = false;
    _playChannelInternal(channel);
  }

  Future<void> _playChannelInternal(LiveChannel channel) async {
    if (!_isPlayerInitialized) _initPlayer();
    if (_isPlayingChannel) return;
    _isPlayingChannel = true;
    currentChannel.value = channel;
    isLoading.value = true;

    try {
      await _player!.stop();

      final config = currentConfig.value;
      final httpHeaders = <String, String>{};
      if (config?.ua != null && config!.ua!.isNotEmpty) {
        httpHeaders['User-Agent'] = config.ua!;
      }

      final Map<String, String> extras = {};
      extras.addAll(_buffer);
      extras['video-sync'] = PlayerPref.videoSync;
      extras['hwdec'] = PlayerPref.hardwareDecoding;
      if (Platform.isAndroid) {
        extras['ao'] = PlayerPref.audioOutput;
      }
      final autosync = PlayerPref.autosync;
      if (autosync != '0') {
        extras['autosync'] = autosync;
      }

      await _player!.open(
        Media(
          channel.url,
          httpHeaders: httpHeaders,
          extras: extras,
        ),
        play: false,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      _player!.play();

    } catch (e) {
      SmartDialog.showToast('播放失败: $e');
    } finally {
      _isPlayingChannel = false;
      isLoading.value = false;
    }
  }

  void togglePlayPause() {
    if (!_isPlayerInitialized) _initPlayer();
    if (isPlaying.value) {
      userPaused.value = true;
      _player!.pause();
    } else {
      userPaused.value = false;
      _player!.play();
    }
  }

  // 全屏控制：移除内部恢复逻辑，完全依赖 LivePage 的 postFrameCallback 处理恢复
  Future<void> enterFullScreen(BuildContext context) async {
    if (isFullScreen.value) return;
    if (PlatformUtils.isDesktop) {
      await windowManager.setFullScreen(true);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    isFullScreen.value = true;
    _fullScreenOverlay = OverlayEntry(
      builder: (context) => FullScreenLivePlayer(
        onExit: () => exitFullScreen(),
      ),
    );
    Overlay.of(context).insert(_fullScreenOverlay!);
  }

  Future<void> exitFullScreen() async {
    if (!isFullScreen.value) return;
    if (PlatformUtils.isDesktop) {
      await windowManager.setFullScreen(false);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    isFullScreen.value = false;
    _fullScreenOverlay?.remove();
    _fullScreenOverlay = null;
  }

  Future<void> toggleFullScreen(BuildContext context) async {
    if (isFullScreen.value) {
      await exitFullScreen();
    } else {
      await enterFullScreen(context);
    }
  }

  @override
  void onClose() {
    _player?.dispose();
    _player = null;
    _videoController = null;
    _isPlayerInitialized = false;
    super.onClose();
  }
}