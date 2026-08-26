// lib/modules/live/controllers/live_controller.dart
import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:window_manager/window_manager.dart' hide WindowCaption;

import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/models/live/live_config.dart';
import 'package:yuanying/modules/live/models/live_channel.dart';
import 'package:yuanying/modules/live/services/live_parser_service.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/modules/live/widgets/live_player_view.dart';

class LiveController extends GetxController {
  static LiveController get to => Get.find<LiveController>(tag: 'live');

  // ===== 独立播放器实例 =====
  Player? _player;
  VideoController? _videoController;
  bool _isPlayerInitialized = false;

  // ===== 状态 =====
  final Rx<LiveConfig?> currentConfig = Rx(null);
  final RxList<LiveChannel> channels = <LiveChannel>[].obs;
  final RxList<String> groups = <String>[].obs;
  final RxString selectedGroup = ''.obs;
  final Rx<LiveChannel?> currentChannel = Rx(null);
  final RxBool isPlaying = false.obs;
  final RxBool isLoading = false.obs;
  final RxBool isBuffering = false.obs;

  // ===== 全屏状态 =====
  final RxBool isFullScreen = false.obs;

  // ===== 播放进度 =====
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;

  // ===== 画面比例 =====
  final Rx<BoxFit> videoFit = BoxFit.contain.obs;

  // ===== 控制条显隐 =====
  final RxBool controlsVisible = false.obs;
  Timer? _hideControlsTimer;

  // ===== 用户主动暂停标志 =====
  final RxBool userPaused = false.obs;

  // ===== 全屏 Overlay =====
  OverlayEntry? _fullScreenOverlay;

  // ===== 内部标志 =====
  bool _isFirstLoad = true;
  bool _isPlayingChannel = false;

  // ===== 全屏 MethodChannel =====
  static const MethodChannel _mediaKitChannel =
      MethodChannel('com.alexmercerind/media_kit_video');

  // ===== 缓存参数 =====
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

  // ============================================================
  // 初始化 & 生命周期
  // ============================================================

  @override
  void onInit() {
    super.onInit();
    if (!Get.isRegistered<LiveController>(tag: 'live')) {
      Get.put(this, tag: 'live', permanent: true);
    }
    _initPlayer();
    _loadConfigAndChannels();
  }

  void ensurePlayerInitialized() {
    if (!_isPlayerInitialized) _initPlayer();
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
      if (playing) {
        userPaused.value = false;
        _resetHideTimer();
      }
    });

    _player!.stream.buffering.listen((buffering) {
      isBuffering.value = buffering;
    });

    _player!.stream.error.listen((error) {
      SmartDialog.showToast('播放失败: $error');
    });

    _player!.stream.position.listen((pos) {
      position.value = pos;
    });

    _player!.stream.duration.listen((dur) {
      duration.value = dur;
    });
  }

  @override
  void onClose() {
    _hideControlsTimer?.cancel();
    _fullScreenOverlay?.remove();
    _fullScreenOverlay = null;
    super.onClose();
  }

  // ============================================================
  // 控制条显隐
  // ============================================================

  void showControls() {
    controlsVisible.value = true;
    _resetHideTimer();
  }

  void hideControls() {
    controlsVisible.value = false;
    _hideControlsTimer?.cancel();
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    if (isPlaying.value) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        hideControls();
      });
    }
  }

  // ============================================================
  // 播放控制
  // ============================================================

  void togglePlayPause() {
    if (!_isPlayerInitialized) _initPlayer();
    if (isPlaying.value) {
      userPaused.value = true;
      _player!.pause();
    } else {
      userPaused.value = false;
      _player!.play();
      showControls();
    }
  }

  void pause() {
    if (_player != null && isPlaying.value) {
      userPaused.value = true;
      _player!.pause();
    }
  }

  void play() {
    if (_player != null && !isPlaying.value) {
      userPaused.value = false;
      _player!.play();
      showControls();
    }
  }

  // ============================================================
  // 系统自动暂停/恢复（切换到其他 Tab 时调用）
  // ============================================================

  void pauseBySystem() {
    if (_player != null && isPlaying.value) {
      _player!.pause();
      // print('暂停播放了...');
    }
  }

  void resumeBySystem() {
    if (_player != null && !isPlaying.value && !userPaused.value && currentChannel.value != null) {
      _player!.play();
      showControls();
      // print('恢复播放了...');
    }
  }

  // ============================================================
  // 重置播放器
  // ============================================================

  void resetPlayer() {
    if (_player != null) {
      _player!.stop();
    }
    channels.clear();
    groups.clear();
    selectedGroup.value = '';
    currentChannel.value = null;
    isPlaying.value = false;
    isLoading.value = false;
    isBuffering.value = false;
    userPaused.value = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    _isFirstLoad = true;
  }

  // ============================================================
  // 加载配置和频道
  // ============================================================

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
        resetPlayer();
      }
    }
  }

  Future<void> _loadChannelsFromRemote(LiveConfig config) async {
    if (config.url.isEmpty) {
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

  // ============================================================
  // 频道播放
  // ============================================================

  void playChannel(LiveChannel channel) {
    if (!_isPlayerInitialized) _initPlayer();
    if (_isPlayingChannel) return;
    if (currentChannel.value?.url == channel.url && isPlaying.value) return;
    userPaused.value = false;
    _playChannelInternal(channel);
    showControls();
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
      userPaused.value = false;

    } catch (e) {
      SmartDialog.showToast('播放失败: $e');
    } finally {
      _isPlayingChannel = false;
      isLoading.value = false;
    }
  }

  // ============================================================
  // 全屏控制（Overlay 覆盖整个应用）
  // ============================================================

  Future<void> enterFullScreen(BuildContext context) async {
    if (isFullScreen.value) return;

    // 系统层全屏
    if (PlatformUtils.isDesktop) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setFullScreen(true);
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        await _mediaKitChannel.invokeMethod('Utils.EnterNativeFullscreen');
      } catch (_) {}
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    // 插入全屏 Overlay（覆盖整个应用，包括底部导航栏）
    _fullScreenOverlay = OverlayEntry(
      builder: (context) => _FullScreenOverlay(
        onExit: () => exitFullScreen(),
      ),
    );
    Overlay.of(context).insert(_fullScreenOverlay!);

    isFullScreen.value = true;
    showControls();
  }

  Future<void> exitFullScreen() async {
    if (!isFullScreen.value) return;

    // 移除 Overlay
    _fullScreenOverlay?.remove();
    _fullScreenOverlay = null;

    // 系统层退出全屏
    if (PlatformUtils.isDesktop) {
      try {
        await _mediaKitChannel.invokeMethod('Utils.ExitNativeFullscreen');
      } catch (_) {}
      await windowManager.setFullScreen(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    isFullScreen.value = false;
    showControls();
    // 不自动恢复播放，保持用户当前操作状态
  }

  Future<void> toggleFullScreen(BuildContext context) async {
    if (isFullScreen.value) {
      await exitFullScreen();
    } else {
      await enterFullScreen(context);
    }
  }

  // ============================================================
  // 画面比例切换
  // ============================================================

  void setVideoFit(BoxFit fit) {
    videoFit.value = fit;
  }

  String getFitName(BoxFit fit) {
    switch (fit) {
      case BoxFit.contain:
        return '适应';
      case BoxFit.cover:
        return '填充';
      case BoxFit.fill:
        return '拉伸';
      default:
        return '适应';
    }
  }

  // ============================================================
  // 工具
  // ============================================================

  String formatDuration(Duration duration) {
    if (duration.inMilliseconds <= 0) return '00:00';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// ============================================================
// 全屏 Overlay 组件
// ============================================================

class _FullScreenOverlay extends StatelessWidget {
  final VoidCallback onExit;

  const _FullScreenOverlay({required this.onExit});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<LiveController>(tag: 'live');

    // 全屏时使用 PopScope 拦截返回键
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // 返回键被拦截，退出全屏
        if (!didPop) {
          onExit();
        }
      },
      child: Material(
        color: Colors.black,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 全屏播放器（复用 LivePlayerView，isFullScreen = true）
              const LivePlayerView(isFullScreen: true),
              // 退出全屏按钮（右上角）
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 28),
                  onPressed: onExit,
                  tooltip: '退出全屏',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}