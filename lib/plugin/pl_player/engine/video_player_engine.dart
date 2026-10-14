// lib/plugin/pl_player/engine/video_player_engine.dart
//
// 原生 video_player 引擎（仅 Android ExoPlayer / iOS AVPlayer）
//
// 与 MediaKitEngine / FvpEngine 对齐 IPlayerEngine 的全部接口：
//   - 完整实现：播放/暂停/seek/倍速/音量/全屏/循环/跳过片头片尾/截图空实现
//   - 空实现（不调底层）：音轨切换、视轨切换、外挂字幕、录制、外部音频、PiP
//   - 保持与其它两个引擎一致的状态流、监听器、渲染接口

import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart'
    show VideoPlayer, VideoPlayerController;

import '../models/data_source.dart';
import '../models/data_status.dart';
import '../models/play_status.dart';
import '../models/video_fit_type.dart';
import '../models/play_repeat.dart';
import '../models/fullscreen_mode.dart';
import '../models/double_tap_type.dart';
import '../player_pref.dart';
import '../../../utils/feed_back.dart';
import '../../../utils/platform_utils.dart';
import 'i_player_engine.dart';
import '../utils/fullscreen.dart';

class VideoPlayerEngine implements IPlayerEngine {
  // ============================================================
  // 私有成员
  // ============================================================
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isPlaying = false;
  bool _skipEndTriggered = false;
  bool _isPipMode = false;

  // 状态流
  @override
  final playerStatus = PlPlayerStatus(PlayerStatus.paused);
  @override
  final Rx<DataStatus> dataStatus = Rx(DataStatus.none);
  @override
  final Rx<Duration> duration = Rx(Duration.zero);
  @override
  final Rx<Duration> buffered = Rx(Duration.zero);
  @override
  final RxInt bufferedSeconds = 0.obs;
  @override
  final RxBool isBuffering = false.obs;

  @override
  Duration position = Duration.zero;
  @override
  final RxInt positionSeconds = 0.obs;
  @override
  Duration sliderPosition = Duration.zero;
  @override
  final RxInt sliderPositionSeconds = 0.obs;
  @override
  final Rx<Duration> sliderTempPosition = Rx(Duration.zero);

  // 播放器属性
  double _playbackSpeed = 1.0;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isLooping = false;

  @override
  final RxBool isFullScreen = false.obs;
  @override
  final RxBool controlsLock = false.obs;
  @override
  final RxBool showControls = false.obs;
  @override
  final RxBool longPressStatus = false.obs;
  @override
  final Rx<VideoFitType> videoFit = Rx(VideoFitType.contain);
  @override
  final RxBool continuePlayInBackground = false.obs;
  @override
  final RxBool isSliderMoving = false.obs;
  @override
  final RxBool onlyPlayAudio = false.obs;
  @override
  final RxBool flipX = false.obs;
  @override
  final RxBool flipY = false.obs;
  @override
  final RxBool enableShowDanmaku = true.obs;
  @override
  final RxDouble danmakuOpacity = 1.0.obs;

  final RxBool _initializedRx = false.obs;
  final RxInt _rebuildCounter = 0.obs;

  // 音量/亮度
  @override
  final RxDouble volume = 1.0.obs;
  @override
  final RxDouble brightness = (-1.0).obs;
  @override
  final RxBool volumeIndicator = false.obs;
  @override
  bool volumeInterceptEventStream = false;
  @override
  Timer? volumeTimer;

  // 轨道（原生 video_player 无 API，全部保持空列表）
  @override
  final RxList<AudioTrack> availableAudioTracks = <AudioTrack>[].obs;
  @override
  final RxList<VideoTrack> availableVideoTracks = <VideoTrack>[].obs;
  @override
  final RxList<SubtitleTrack> availableSubtitleTracks = <SubtitleTrack>[].obs;

  @override
  final Rx<AudioTrack?> currentAudioTrack = Rx<AudioTrack?>(null);
  @override
  final Rx<VideoTrack?> currentVideoTrack = Rx<VideoTrack?>(null);
  @override
  final Rx<SubtitleTrack?> currentSubtitleTrack = Rx<SubtitleTrack?>(null);

  // 字幕样式（保留占位，供未来 Flutter 层 SubtitleView 使用）
  @override
  late double subtitleFontScale = PlayerPref.subtitleFontScale;
  @override
  late double subtitleFontScaleFS = PlayerPref.subtitleFontScaleFS;
  @override
  late int subtitlePaddingH = PlayerPref.subtitlePaddingH;
  @override
  late int subtitlePaddingB = PlayerPref.subtitlePaddingB;
  @override
  late double subtitleBgOpacity = PlayerPref.subtitleBgOpacity;
  @override
  late double subtitleStrokeWidth = PlayerPref.subtitleStrokeWidth;
  @override
  late int subtitleFontWeight = PlayerPref.subtitleFontWeight;

  @override
  late final Rx<SubtitleViewConfiguration> subtitleConfig = getSubConfig.obs;

  SubtitleViewConfiguration get getSubConfig {
    return SubtitleViewConfiguration(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w500,
      ),
      padding: EdgeInsets.only(
        left: subtitlePaddingH.toDouble(),
        right: subtitlePaddingH.toDouble(),
        bottom: subtitlePaddingB.toDouble(),
      ),
    );
  }

  @override
  void updateSubtitleStyle() => subtitleConfig.value = getSubConfig;
  @override
  void putSubtitleSettings() {}

  // 弹幕
  @override
  dynamic danmakuController;
  @override
  void toggleDanmaku() => enableShowDanmaku.value = !enableShowDanmaku.value;
  @override
  void refreshDanmakuConfig() {}

  // 播放模式
  @override
  PlayRepeat playRepeat = PlayRepeat.pause;

  // 配置
  late final showControlDuration = PlayerPref.enableLongShowControl
      ? const Duration(seconds: 30)
      : const Duration(seconds: 3);
  @override
  late final bool enableShrinkVideoSize = PlayerPref.enableShrinkVideoSize;
  @override
  late final bool enableSlideVolumeBrightness =
      PlayerPref.enableSlideVolumeBrightness;
  @override
  late final bool enableSlideFS = PlayerPref.enableSlideFS;
  @override
  late final Duration fastForBackwardDuration =
      Duration(seconds: PlayerPref.fastForBackwardDuration);
  @override
  late final bool showFsLockBtn = PlayerPref.showFsLockBtn;
  @override
  late final bool showFsScreenshotBtn = PlayerPref.showFsScreenshotBtn;
  @override
  late final bool fullScreenGestureReverse = PlayerPref.fullScreenGestureReverse;
  @override
  late final bool enableQuickDouble = PlayerPref.enableQuickDouble;
  @override
  late final FullScreenMode mode =
      FullScreenMode.values[PlayerPref.fullScreenMode];
  @override
  late final bool horizontalScreen = PlayerPref.horizontalScreen;
  @override
  late final bool removeSafeArea = PlayerPref.removeSafeArea;
  late final bool autoEnterFullScreen = PlayerPref.autoEnterFullScreen;
  late final bool autoExitFullscreen = PlayerPref.autoExitFullscreen;
  @override
  bool get enableTapDm => PlayerPref.enableTapDm;

  @override
  final RxInt progressType = PlayerPref.btmProgressBehavior.obs;
  @override
  final RxInt skipStartDuration = 0.obs;
  @override
  final RxInt skipEndDuration = 0.obs;

  // 数据源
  late DataSource dataSource;

  // 工具
  bool _processing = false;
  @override
  bool get processing => _processing;
  String? _vodId;
  @override
  String? get vodId => _vodId;
  int? _width;
  int? _height;
  @override
  int? get width => _width;
  @override
  int? get height => _height;
  bool _isCloseAll = false;
  @override
  bool get isCloseAll => _isCloseAll;
  @override
  bool get setSystemBrightness => false;

  @override
  final RxString batteryLevel = '--'.obs;
  final Battery _battery = Battery();
  StreamSubscription? _batterySubscription;

  // 监听器
  final Set<ValueChanged<Duration>> _positionListeners = {};
  final Set<ValueChanged<PlayerStatus>> _statusListeners = {};
  VoidCallback? _listenerCallback;

  // 快进快退
  @override
  final RxBool mountSeekBackwardButton = false.obs;
  @override
  final RxBool mountSeekForwardButton = false.obs;
  @override
  bool? cancelSeek;
  @override
  bool? hasToast;
  Timer? _longPressTimer;
  Timer? _timer;
  @override
  double lastPlaybackSpeed = 1.0;

  // 分辨率/网速
  final RxInt _videoWidth = 0.obs;
  final RxInt _videoHeight = 0.obs;
  final RxDouble _downloadSpeed = 0.0.obs;
  @override
  RxInt get videoWidth => _videoWidth;
  @override
  RxInt get videoHeight => _videoHeight;
  @override
  RxDouble get downloadSpeed => _downloadSpeed;

  // 高级特性：空实现
  @override
  final RxBool isLive = false.obs;
  @override
  final Rxn<dynamic> mediaInfo = Rxn<dynamic>();
  @override
  final Rxn<String> currentSubtitleText = Rxn<String>();

  @override
  void record(String? path) {
    debugPrint('[VideoPlayerEngine] record 不支持');
  }

  @override
  void setExternalAudio(String? url) {
    debugPrint('[VideoPlayerEngine] setExternalAudio 不支持');
  }

  // ============================================================
  // getter / setter
  // ============================================================
  @override
  double get playbackSpeed => _playbackSpeed;
  @override
  double get longPressSpeed => PlayerPref.longPressSpeedDefault;
  @override
  bool get isVertical => false;
  @override
  bool get isFileSource => dataSource is FileSource;
  @override
  bool get isMuted => _isMuted;
  @override
  set isMuted(bool value) {
    _isMuted = value;
    if (_controller != null && _isInitialized) {
      _controller!.setVolume(value ? 0 : _volume);
    }
  }
  @override
  bool get isPipMode => _isPipMode;
  @override
  bool get isDesktopPip => false;
  @override
  bool get showPreview => false;
  @override
  bool get enableBlock => false;
  @override
  bool get showViewPoints => false;
  @override
  bool get showDmChart => false;
  @override
  bool get isAnim => false;

  @override
  List<double> get speedList => PlayerPref.speedList;
  @override
  bool get enableAutoLongPressSpeed => PlayerPref.enableAutoLongPressSpeed;

  @override
  Timer? get longPressTimer => _longPressTimer;
  @override
  set longPressTimer(Timer? timer) => _longPressTimer = timer;

  @override
  num get sliderScale => duration.value.inMilliseconds * 0.001;
  @override
  Duration get positionValue => position;

  @override
  VideoController? get videoController => null;
  @override
  Player? get videoPlayerController => null;

  // ============================================================
  // 生命周期
  // ============================================================
  VideoPlayerEngine();

  @override
  Future<void> init() async {
    _isDisposed = false;
    _initBatteryListener();
  }

  void _initBatteryListener() {
    _batterySubscription?.cancel();
    _batterySubscription = _battery.onBatteryStateChanged.listen((_) {
      _updateBatteryLevel();
    });
    _updateBatteryLevel();
  }

  Future<void> _updateBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      batteryLevel.value = '$level%';
    } catch (_) {
      batteryLevel.value = '--%';
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _batterySubscription?.cancel();
    _batterySubscription = null;

    _removeListeners();
    _controller?.dispose();
    _controller = null;
    _timer?.cancel();
    _longPressTimer?.cancel();
  }

  @override
  void onCloseAll() {
    _isCloseAll = true;
    dispose();
    Get.until((route) => route.isFirst);
  }

  // ============================================================
  // 核心播放控制
  // ============================================================
  void _updateVideoSize() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    final size = controller.value.size;
    if (size.width > 0 && size.height > 0) {
      _videoWidth.value = size.width.toInt();
      _videoHeight.value = size.height.toInt();
    }
  }

  @override
  Future<void> setDataSource(
    DataSource dataSource, {
    bool autoplay = true,
    Duration? seekTo,
    double speed = 1.0,
    int? width,
    int? height,
    Duration? duration,
    bool? isVertical,
    String? vodId,
    VoidCallback? onInit,
    bool autoFullScreenFlag = false,
  }) async {
    debugPrint('[VideoPlayerEngine] setDataSource url=${dataSource.videoSource}');
    if (_isDisposed) await init();

    _skipEndTriggered = false;
    _processing = true;
    _vodId = vodId;
    _width = width;
    _height = height;
    _playbackSpeed = speed;
    this.dataSource = dataSource;

    _removeListeners();
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
    _initializedRx.value = false;

    dataStatus.value = DataStatus.loading;
    isBuffering.value = true;

    try {
      if (dataSource is FileSource) {
        _controller = VideoPlayerController.file(File(dataSource.videoSource));
      } else if (dataSource.videoSource.startsWith('http')) {
        _controller = VideoPlayerController.network(
          dataSource.videoSource,
          httpHeaders: dataSource.headers ?? const {},
        );
      } else {
        _controller = VideoPlayerController.network(dataSource.videoSource);
      }

      await _controller!.initialize();
      _isInitialized = true;
      _initializedRx.value = true;
      _rebuildCounter.value++;

      this.duration.value = _controller!.value.duration;
      position = _controller!.value.position;
      updatePositionSecond();

      if (speed != 1.0) {
        await _controller!.setPlaybackSpeed(speed);
      }
      if (_volume != 1.0) {
        await _controller!.setVolume(_volume);
      }
      if (_isLooping) {
        await _controller!.setLooping(true);
      }

      if (seekTo != null && seekTo.inSeconds > 0) {
        await _controller!.seekTo(seekTo);
        position = seekTo;
        updatePositionSecond();
      }

      dataStatus.value = DataStatus.loaded;
      isBuffering.value = false;
      _updateVideoSize();

      _addListeners();

      if (autoplay) {
        await _controller!.play();
        _isPlaying = true;
        playerStatus.value = PlayerStatus.playing;
        this.duration.refresh();
      } else {
        playerStatus.value = PlayerStatus.paused;
      }

      onInit?.call();

      if (autoFullScreenFlag && autoEnterFullScreen) {
        await triggerFullScreen(status: true);
      }

      _width = _controller!.value.size.width.toInt();
      _height = _controller!.value.size.height.toInt();
    } catch (e, stack) {
      debugPrint('[VideoPlayerEngine] setDataSource error: $e\n$stack');
      dataStatus.value = DataStatus.error;
      isBuffering.value = false;
      _initializedRx.value = false;
      _controller?.dispose();
      _controller = null;
    } finally {
      _processing = false;
    }
  }

  @override
  Future<void> play({bool repeat = false, bool hideControls = true}) async {
    if (_controller == null || !_isInitialized) return;
    if (_isPlaying && _controller!.value.isPlaying) return;

    controls = !hideControls;
    if (repeat) {
      await _controller!.seekTo(Duration.zero);
    }
    await _controller!.play();
    _isPlaying = true;
    playerStatus.value = PlayerStatus.playing;
    duration.refresh();
  }

  @override
  Future<void> pause({bool notify = true, bool isInterrupt = false}) async {
    if (_controller == null || !_isInitialized) return;
    await _controller!.pause();
    _isPlaying = false;
    playerStatus.value = PlayerStatus.paused;
  }

  @override
  Future<void> seekTo(Duration position, {bool isSeek = true}) async {
    if (_controller == null || !_isInitialized) return;
    var target = position < Duration.zero ? Duration.zero : position;
    final dur = duration.value;
    if (dur != Duration.zero && target > dur) target = dur;

    try {
      await _controller!.seekTo(target);
    } catch (e) {
      debugPrint('[VideoPlayerEngine] seek error: $e');
    }
    this.position = target;
    updatePositionSecond();
  }

  @override
  Future<void> refreshPlayer() async {
    if (dataSource == null) return;
    final currentPosition = position;
    final wasPlaying = _isPlaying;

    await setDataSource(
      dataSource,
      autoplay: false,
      seekTo: currentPosition,
    );

    if (wasPlaying) await play();
  }

  // ============================================================
  // 音量
  // ============================================================
  @override
  double get maxVolume => 1.0;

  @override
  Future<void> setVolume(double volume, {bool showIndicator = true}) async {
    _volume = volume.clamp(0.0, 1.0);
    this.volume.value = _volume;
    if (_controller != null && _isInitialized) {
      await _controller!.setVolume(_volume);
    }
    if (showIndicator) {
      volumeIndicator.value = true;
      volumeTimer?.cancel();
      volumeTimer = Timer(const Duration(milliseconds: 800), () {
        volumeIndicator.value = false;
      });
    }
  }

  // ============================================================
  // 倍速
  // ============================================================
  @override
  Future<void> setPlaybackSpeed(double speed) async {
    lastPlaybackSpeed = _playbackSpeed;
    _playbackSpeed = speed;
    if (_controller != null && _isInitialized) {
      await _controller!.setPlaybackSpeed(speed);
    }
  }

  @override
  Future<void> setDefaultSpeed() async {
    await setPlaybackSpeed(1.0);
  }

  @override
  void setLongPressStatus(bool val) {
    longPressStatus.value = val;
  }

  // ============================================================
  // 全屏
  // ============================================================
  @override
  Future<void> triggerFullScreen({
    bool status = true,
    bool inAppFullScreen = false,
    DeviceOrientation? orientation,
    bool isManualFS = true,
  }) async {
    if (isFullScreen.value == status) return;

    if (PlatformUtils.isMobile) {
      if (status) {
        hideSystemBar();
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        if (!removeSafeArea) {
          showSystemBar();
        }
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    } else if (PlatformUtils.isDesktop) {
      try {
        if (status) {
          await enterDesktopFullScreen(inAppFullScreen: inAppFullScreen);
        } else {
          await exitDesktopFullScreen();
        }
      } catch (e) {
        debugPrint('[VideoPlayerEngine] fullscreen error: $e');
      }
    }

    isFullScreen.value = status;
  }

  @override
  Future<void> setOrientation(List<DeviceOrientation> orientations) async {
    if (!PlatformUtils.isMobile) return;
    await SystemChrome.setPreferredOrientations(orientations);
  }

  // ============================================================
  // 轨道：空实现（只记录状态）
  // ============================================================
  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    currentAudioTrack.value = track;
  }

  @override
  Future<void> setVideoTrack(VideoTrack track) async {
    currentVideoTrack.value = track;
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    currentSubtitleTrack.value = track;
  }

  // ============================================================
  // 截图 / PiP：空实现
  // ============================================================
  @override
  Future<void> takeScreenshot() async {
    if (_controller == null || !_isInitialized) {
      SmartDialog.showToast('播放器未就绪');
      return;
    }
    SmartDialog.showToast('当前内核暂不支持截图');
  }

  @override
  Future<void> enterDesktopPip() async {}
  @override
  Future<void> exitDesktopPip() async {}
  @override
  void toggleDesktopPip() {}

  // ============================================================
  // 其他控制
  // ============================================================
  @override
  void toggleFlipX() => flipX.value = !flipX.value;
  @override
  void toggleFlipY() => flipY.value = !flipY.value;
  @override
  void setOnlyPlayAudio() {}
  @override
  void setContinuePlayInBackground() {}

  @override
  void onLockControl(bool val) {
    controlsLock.value = val;
    if (!val && showControls.value) showControls.refresh();
    controls = !val;
  }

  @override
  void onDoubleTapCenter() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  @override
  void onForward(Duration duration) => seekTo(position + duration);
  @override
  void onBackward(Duration duration) {
    final newPos = position - duration;
    seekTo(newPos < Duration.zero ? Duration.zero : newPos);
  }
  @override
  void onForwardBackward(Duration duration) {
    final target = duration < Duration.zero
        ? Duration.zero
        : (duration > this.duration.value ? this.duration.value : duration);
    seekTo(target);
  }

  @override
  void onChangedSlider(int v) {
    sliderPosition = Duration(seconds: v);
    updateSliderPositionSecond();
  }

  @override
  void onChangedSliderStart([Duration? value]) {
    if (value != null) sliderTempPosition.value = value;
    isSliderMoving.value = true;
  }

  @override
  void onUpdatedSliderProgress(Duration value) {
    sliderTempPosition.value = value;
    sliderPosition = value;
    updateSliderPositionSecond();
  }

  @override
  void onChangedSliderEnd() {
    if (cancelSeek != true) feedBack();
    cancelSeek = null;
    hasToast = null;
    isSliderMoving.value = false;
    hideTaskControls();
  }

  @override
  void updateSliderPositionSecond() {
    final newSecond = sliderPosition.inSeconds;
    if (sliderPositionSeconds.value != newSecond) {
      sliderPositionSeconds.value = newSecond;
    }
  }

  @override
  void updatePositionSecond() {
    final newSecond = position.inSeconds;
    if (positionSeconds.value != newSecond) {
      positionSeconds.value = newSecond;
    }
  }

  @override
  void updateBufferedSecond() {
    final newSecond = buffered.value.inSeconds;
    if (bufferedSeconds.value != newSecond) {
      bufferedSeconds.value = newSecond;
    }
  }

  @override
  set controls(bool visible) {
    showControls.value = visible;
    _timer?.cancel();
    if (visible) {
      isSliderMoving.value = false;
      hideTaskControls();
    }
  }

  @override
  void hideTaskControls() {
    _timer?.cancel();
    if (isSliderMoving.value) return;
    _timer = Timer(showControlDuration, () {
      if (!isSliderMoving.value) controls = false;
      _timer = null;
    });
  }

  @override
  void cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop) {
      if (_isPlaying) pause();
      return;
    }
    if (controlsLock.value) {
      onLockControl(false);
      return;
    }
    if (isFullScreen.value) {
      triggerFullScreen(status: false);
      return;
    }
    Get.back();
  }

  @override
  void setPlayRepeat(PlayRepeat type) {
    playRepeat = type;
    if (type == PlayRepeat.singleCycle) {
      _isLooping = true;
      _controller?.setLooping(true);
    } else {
      _isLooping = false;
      _controller?.setLooping(false);
    }
  }

  @override
  void doubleTapFuc(DoubleTapType type) {
    if (!enableQuickDouble) {
      onDoubleTapCenter();
      return;
    }
    switch (type) {
      case DoubleTapType.left:
        onBackward(fastForBackwardDuration);
        break;
      case DoubleTapType.center:
        onDoubleTapCenter();
        break;
      case DoubleTapType.right:
        onForward(fastForBackwardDuration);
        break;
    }
  }

  @override
  void toggleVideoFit(VideoFitType value) => videoFit.value = value;

  // ============================================================
  // 监听器
  // ============================================================
  void _addListeners() {
    if (_controller == null) return;
    _listenerCallback = () {
      if (_isDisposed) return;
      final controller = _controller;
      if (controller == null || !_isInitialized) return;
      final value = controller.value;

      if (value.hasError) {
        debugPrint('[VideoPlayerEngine] 播放错误: ${value.errorDescription}');
      }

      if (position != value.position) {
        position = value.position;
        updatePositionSecond();
        if (!isSliderMoving.value) {
          sliderPosition = value.position;
          updateSliderPositionSecond();
        }
        for (final listener in _positionListeners) {
          listener(value.position);
        }
      }

      if (duration.value != value.duration) {
        duration.value = value.duration;
        if (_videoWidth.value == 0 || _videoHeight.value == 0) {
          _updateVideoSize();
        }
      }

      if (value.buffered.isNotEmpty) {
        Duration totalBuffered = Duration.zero;
        for (final range in value.buffered) {
          totalBuffered += range.end - range.start;
        }
        if (buffered.value != totalBuffered) {
          buffered.value = totalBuffered;
          updateBufferedSecond();
        }
      }

      isBuffering.value = value.isBuffering;

      if (value.isPlaying && !_isPlaying) {
        _isPlaying = true;
        playerStatus.value = PlayerStatus.playing;
        for (final listener in _statusListeners) {
          listener(PlayerStatus.playing);
        }
      } else if (!value.isPlaying && _isPlaying) {
        _isPlaying = false;
        playerStatus.value = PlayerStatus.paused;
        for (final listener in _statusListeners) {
          listener(PlayerStatus.paused);
        }
      }

      if (value.isCompleted) {
        playerStatus.value = PlayerStatus.completed;
        for (final listener in _statusListeners) {
          listener(PlayerStatus.completed);
        }
        if (autoExitFullscreen && isFullScreen.value) {
          triggerFullScreen(status: false);
        }
      }

      // 跳过片尾
      final endSkip = skipEndDuration.value;
      if (endSkip > 0 && !_skipEndTriggered) {
        final total = duration.value.inSeconds;
        if (total > 0 && value.position.inSeconds >= total - endSkip) {
          if (_isPlaying) {
            _skipEndTriggered = true;
            final nearEnd =
                Duration(seconds: total) - const Duration(milliseconds: 500);
            if (value.position < nearEnd) {
              seekTo(nearEnd, isSeek: false);
              SmartDialog.showToast('已跳过片尾');
            }
          }
        }
      }
    };

    _controller!.addListener(_listenerCallback!);
  }

  void _removeListeners() {
    if (_controller != null && _listenerCallback != null) {
      _controller!.removeListener(_listenerCallback!);
      _listenerCallback = null;
    }
    _positionListeners.clear();
    _statusListeners.clear();
  }

  @override
  void addPositionListener(ValueChanged<Duration> listener) =>
      _positionListeners.add(listener);
  @override
  void removePositionListener(ValueChanged<Duration> listener) =>
      _positionListeners.remove(listener);
  @override
  void addStatusLister(ValueChanged<PlayerStatus> listener) =>
      _statusListeners.add(listener);
  @override
  void removeStatusLister(ValueChanged<PlayerStatus> listener) =>
      _statusListeners.remove(listener);

  // ============================================================
  // 渲染
  // ============================================================
  @override
  Widget buildVideoWidget({
    required BoxFit fit,
    required bool flipX,
    required bool flipY,
  }) {
    return Obx(() {
      final rebuild = _rebuildCounter.value;

      bool isInitialized = false;
      try {
        if (_controller != null) {
          isInitialized = _controller!.value.isInitialized;
        }
      } catch (_) {}

      if (_isDisposed || _controller == null || !isInitialized) {
        return const ColoredBox(color: Colors.black);
      }

      try {
        final controller = _controller!;
        final size = controller.value.size;
        final double width = size.width > 0 ? size.width : 640;
        final double height = size.height > 0 ? size.height : 360;

        Widget video = VideoPlayer(
          controller,
          key: ValueKey(rebuild),
        );

        if (flipX || flipY) {
          video = Transform(
            transform: Matrix4.identity()
              ..setEntry(0, 0, flipX ? -1 : 1)
              ..setEntry(1, 1, flipY ? -1 : 1),
            alignment: Alignment.center,
            child: video,
          );
        }

        return FittedBox(
          fit: fit,
          child: SizedBox(width: width, height: height, child: video),
        );
      } catch (e) {
        return const ColoredBox(color: Colors.black);
      }
    });
  }

  // ============================================================
  // 跳过片头
  // ============================================================
  @override
  Future<void> applySkipStart() async {
    final start = skipStartDuration.value;
    if (start <= 0) return;
    if (duration.value.inSeconds > start) {
      await seekTo(Duration(seconds: start), isSeek: false);
    }
  }

  // ============================================================
  // 功能标志
  // ============================================================
  @override
  bool get supportsAudioTrack => false;
  @override
  bool get supportsVideoTrack => false;
  @override
  bool get supportsEmbeddedSubtitle => false;
  @override
  bool get supportsHardwareAcceleration => true;
  @override
  bool get supportsScreenshot => false;
  @override
  bool get supportsPictureInPicture => true;
  @override
  bool get supportsBufferProgress => true;

  @override
  bool get supportsRecording => false;

  @override
  bool get supportsExternalSubtitle => false;

  @override
  bool get supportsSubtitleExport => false;

  @override
  bool get supportsOnlyPlayAudio => false;

  @override
  bool get supportsHardwareDecodingSetting => false;

  @override
  bool get supportsExternalAudio => false;
}