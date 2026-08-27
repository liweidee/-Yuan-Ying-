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
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/models/live/live_config.dart';
import 'package:yuanying/modules/live/models/live_channel.dart';
import 'package:yuanying/modules/live/services/live_parser_service.dart';
import 'package:yuanying/modules/live/widgets/live_player_view.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/platform_utils.dart';

import 'package:yuanying/plugin/pl_player/models/video_fit_type.dart';
import 'package:yuanying/plugin/pl_player/utils/fullscreen.dart';

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

  // ===== 错误信息 =====
  final RxString errorMessage = ''.obs;

  // ===== 全屏状态 =====
  final RxBool isFullScreen = false.obs;

  // ===== 播放进度 =====
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;

  // ===== 画面比例 =====
  final Rx<VideoFitType> videoFit = VideoFitType.contain.obs;

  // ===== 控制条显隐 =====
  final RxBool controlsVisible = false.obs;
  Timer? _hideControlsTimer;

  // ===== 用户主动暂停标志 =====
  final RxBool userPaused = false.obs;

  // ===== 音量 & 亮度 =====
  final RxDouble volume = 1.0.obs;
  final RxDouble brightness = (-1.0).obs;

  // ===== 全屏 Overlay =====
  OverlayEntry? _fullScreenOverlay;

  // ===== 内部标志 =====
  bool _isFirstLoad = true;
  bool _isPlayingChannel = false;

  // ===== 记录当前加载的配置 key，用于检测是否切换了配置 =====
  String? _currentConfigKey;

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
    _loadConfigAndChannels(forceLoading: true);
    _initVolumeAndBrightness();
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

  void _initVolumeAndBrightness() async {
    try {
      final sysBrightness = await ScreenBrightnessPlatform.instance.system;
      brightness.value = sysBrightness;
    } catch (_) {}
    volume.value = 1.0;
  }

  @override
  void onClose() {
    _hideControlsTimer?.cancel();
    _fullScreenOverlay?.remove();
    _fullScreenOverlay = null;
    if (PlatformUtils.isMobile) {
      portraitUpMode();
    }
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
  // 系统自动暂停/恢复
  // ============================================================

  void pauseBySystem() {
    if (_player != null && isPlaying.value) {
      _player!.pause();
    }
  }

  void resumeBySystem() {
    if (_player != null && !isPlaying.value && !userPaused.value && currentChannel.value != null) {
      _player!.play();
      showControls();
    }
  }

  // ============================================================
  // 音量控制
  // ============================================================

  Future<void> setVolume(double value, {bool showIndicator = true}) async {
    final clamped = value.clamp(0.0, 2.0);
    volume.value = clamped;
    if (_player != null) {
      await _player!.setVolume(clamped * 100);
    }
  }

  // ============================================================
  // 亮度控制
  // ============================================================

  Future<void> setBrightness(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    brightness.value = clamped;
    try {
      await ScreenBrightnessPlatform.instance.setSystemScreenBrightness(clamped);
    } catch (_) {}
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

  /// [forceLoading] 是否强制显示全局 loading
  ///   - true: 强制显示 loading（切换配置时使用）
  ///   - false: 如果有数据则静默刷新（切换 Tab 时使用）
  Future<void> _loadConfigAndChannels({bool forceLoading = false}) async {
    // 检查当前配置是否变化
    final configKey = StorageManager.getSetting<String>(SettingBoxKey.liveCurrentKey);
    final configs = StorageManager.getSetting<List<dynamic>>(SettingBoxKey.liveConfigs) ?? [];

    // 获取当前实际使用的配置 key
    String? targetConfigKey;
    if (configKey != null && configKey.isNotEmpty) {
      // 检查 key 是否有效
      final found = configs.any((item) {
        final config = LiveConfig.fromJson(Map<String, dynamic>.from(item));
        return config.key == configKey;
      });
      if (found) {
        targetConfigKey = configKey;
      }
    }
    if (targetConfigKey == null && configs.isNotEmpty) {
      final first = LiveConfig.fromJson(Map<String, dynamic>.from(configs.first));
      targetConfigKey = first.key;
    }

    final bool configChanged = _currentConfigKey != targetConfigKey;

    // ===== 场景判断 =====
    // 1. 有数据 + 配置没变 + 无错误 + 不强制加载 → 静默刷新（不显示 loading）
    if (channels.isNotEmpty && 
        errorMessage.value.isEmpty && 
        !configChanged && 
        !forceLoading) {
      // 静默刷新：只刷新数据，不显示 loading
      _silentRefreshChannels();
      return;
    }

    // 2. 其他情况：显示 loading（首次加载、配置切换、强制加载、错误恢复）
    errorMessage.value = '';
    isLoading.value = true;
    _currentConfigKey = targetConfigKey;

    // 切换配置时，清空当前频道，以便加载完成后自动播放第一个
    if (forceLoading) {
      currentChannel.value = null;
      // 停止当前播放，避免旧流继续
      _player?.stop();
    }

    try {
      if (configs.isEmpty) {
        errorMessage.value = '暂无直播配置，请添加配置';
        isLoading.value = false;
        resetPlayer();
        return;
      }

      LiveConfig? found;
      if (targetConfigKey != null && targetConfigKey.isNotEmpty) {
        for (var item in configs) {
          final config = LiveConfig.fromJson(Map<String, dynamic>.from(item));
          if (config.key == targetConfigKey) {
            found = config;
            break;
          }
        }
      }

      if (found == null && configs.isNotEmpty) {
        found = LiveConfig.fromJson(Map<String, dynamic>.from(configs.first));
        _currentConfigKey = found.key;
      }

      if (found == null) {
        errorMessage.value = '暂无有效的直播配置';
        isLoading.value = false;
        resetPlayer();
        return;
      }

      currentConfig.value = found;
      await _loadChannelsFromRemote(found, showLoading: true);

    } catch (e) {
      errorMessage.value = '加载直播配置失败: $e';
      isLoading.value = false;
      resetPlayer();
    }
  }

  /// 静默刷新频道数据（不显示 loading）
  Future<void> _silentRefreshChannels() async {
    final config = currentConfig.value;
    if (config == null) return;

    // 保存当前播放状态
    final bool wasPlaying = isPlaying.value;
    final String? currentChannelUrl = currentChannel.value?.url;

    try {
      final response = await Dio().get(
        config.url,
        options: Options(
          headers: config.ua != null ? {'User-Agent': config.ua} : null,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final content = response.data is String ? response.data as String : response.data.toString();
      final parsed = LiveParserService.parse(content);

      if (parsed.isEmpty) {
        // 静默刷新失败，但保留旧数据
        return;
      }

      // 更新频道列表
      final oldChannels = List<LiveChannel>.from(channels);
      channels.assignAll(parsed);
      _updateGroups();

      // 尝试恢复当前频道
      if (currentChannelUrl != null) {
        final found = parsed.where((ch) => ch.url == currentChannelUrl).toList();
        if (found.isNotEmpty) {
          currentChannel.value = found.first;
          // 如果之前在播放，继续播放
          if (wasPlaying && !isPlaying.value && !userPaused.value) {
            _player?.play();
          }
        } else {
          // 当前频道不在新列表中，自动播放第一个
          if (parsed.isNotEmpty) {
            _playChannelInternal(parsed.first);
          }
        }
      } else if (parsed.isNotEmpty && currentChannel.value == null) {
        _playChannelInternal(parsed.first);
      }

    } catch (_) {
      // 静默刷新失败，不处理
    }
  }

  Future<void> _loadChannelsFromRemote(LiveConfig config, {bool showLoading = true}) async {
    if (config.url.isEmpty) {
      errorMessage.value = '直播源地址为空，请检查配置';
      if (showLoading) isLoading.value = false;
      resetPlayer();
      return;
    }

    try {
      final response = await Dio().get(
        config.url,
        options: Options(
          headers: config.ua != null ? {'User-Agent': config.ua} : null,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final content = response.data is String ? response.data as String : response.data.toString();
      final parsed = LiveParserService.parse(content);

      if (parsed.isEmpty) {
        errorMessage.value = '未解析到任何频道，请检查直播源';
        if (showLoading) isLoading.value = false;
        resetPlayer();
        return;
      }

      errorMessage.value = '';
      channels.assignAll(parsed);
      _updateGroups();

      if (channels.isNotEmpty && currentChannel.value == null) {
        _playChannelInternal(channels.first);
      }

    } catch (e) {
      errorMessage.value = '加载直播源失败: $e';
      resetPlayer();
    } finally {
      if (showLoading) isLoading.value = false;
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

  /// 刷新频道（用户手动触发）
  /// [showLoading] 是否显示 loading，默认 true
  Future<void> refreshChannels({bool showLoading = true}) async {
    await _loadConfigAndChannels(forceLoading: showLoading);
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
    }
  }

  // ============================================================
  // 全屏控制
  // ============================================================

  Future<void> enterFullScreen(BuildContext context) async {
    if (isFullScreen.value) return;

    if (PlatformUtils.isDesktop) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setFullScreen(true);
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        await _mediaKitChannel.invokeMethod('Utils.EnterNativeFullscreen');
      } catch (_) {}
    } else {
      try {
        await _mediaKitChannel.invokeMethod('Utils.EnterNativeFullscreen');
      } catch (_) {}
      await landscapeLeftMode();
    }

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

    _fullScreenOverlay?.remove();
    _fullScreenOverlay = null;

    if (PlatformUtils.isDesktop) {
      try {
        await _mediaKitChannel.invokeMethod('Utils.ExitNativeFullscreen');
      } catch (_) {}
      await windowManager.setFullScreen(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    } else {
      try {
        await _mediaKitChannel.invokeMethod('Utils.ExitNativeFullscreen');
      } catch (_) {}
      await portraitUpMode();
    }

    isFullScreen.value = false;
    showControls();
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

  void setVideoFit(VideoFitType fit) {
    videoFit.value = fit;
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
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
              const LivePlayerView(isFullScreen: true),
            ],
          ),
        ),
      ),
    );
  }
}