// lib/plugin/pl_player/engine/video_player_engine.dart
//
// 原生 video_player 引擎实现（仅 Android ExoPlayer / iOS AVPlayer）
//
// 与 FvpEngine 的关键差异：
//   1. 不调用任何 FVP 扩展方法：
//      - getActiveAudioTracks / getActiveVideoTracks / getActiveSubtitleTracks
//      - setAudioTracks([index])
//      - setExternalSubtitle(path)
//      - fastSeekTo(target)
//   2. 轨道相关操作仅记录状态，不调用底层
//   3. 内置字幕/音轨/视轨列表保持为空
//   4. 截图暂不支持（Toast 提示）
//   5. 移动端系统 PiP 需平台通道，暂为空实现
//   6. supportsEmbeddedSubtitle => false
//   7. supportsPictureInPicture => true（系统原生能力）
//   8. supportsScreenshot => false
//   9. 电池监听完整实现（与 MediaKitEngine 保持一致）

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

import '../models/data_source.dart';
import '../models/data_status.dart';
import '../models/play_status.dart';
import '../models/video_fit_type.dart';
import '../models/play_repeat.dart';
import '../models/fullscreen_mode.dart';
import '../models/double_tap_type.dart';
import '../player_pref.dart';
import '../../../utils/feed_back.dart';
import 'i_player_engine.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import '../utils/fullscreen.dart';
import '../../../utils/platform_utils.dart';

/// 原生 video_player 引擎
/// Android 使用 ExoPlayer，iOS 使用 AVPlayer
class VideoPlayerEngine implements IPlayerEngine {
  // ============================================================
  // 1. 私有成员
  // ============================================================
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isPlaying = false;

  // ---- 状态流（Rx） ----
  final playerStatus = PlPlayerStatus(PlayerStatus.paused);
  final Rx<DataStatus> dataStatus = Rx(DataStatus.none);
  final Rx<Duration> duration = Rx(Duration.zero);
  final Rx<Duration> buffered = Rx(Duration.zero);
  final RxInt bufferedSeconds = 0.obs;
  final RxBool isBuffering = false.obs;

  // ---- position / sliderPosition ----
  Duration position = Duration.zero;
  final RxInt positionSeconds = 0.obs;

  Duration sliderPosition = Duration.zero;
  final RxInt sliderPositionSeconds = 0.obs;
  final Rx<Duration> sliderTempPosition = Rx(Duration.zero);

  // ---- 播放器属性 ----
  double _playbackSpeed = 1.0;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isLooping = false;
  bool _isPipMode = false;
  bool _isFullscreen = false;

  final RxBool isFullScreen = false.obs;
  final RxBool controlsLock = false.obs;
  final RxBool showControls = false.obs;
  final RxBool longPressStatus = false.obs;
  final Rx<VideoFitType> videoFit = Rx(VideoFitType.contain);
  final RxBool continuePlayInBackground = false.obs;
  final RxBool isSliderMoving = false.obs;
  final RxBool onlyPlayAudio = false.obs;
  final RxBool flipX = false.obs;
  final RxBool flipY = false.obs;
  final RxBool enableShowDanmaku = true.obs;
  final RxDouble danmakuOpacity = 1.0.obs;

  final RxBool _initializedRx = false.obs;
  final RxInt _rebuildCounter = 0.obs;

  // ---- 音量/亮度 ----
  final RxDouble volume = 1.0.obs;
  final RxDouble brightness = (-1.0).obs;
  final RxBool volumeIndicator = false.obs;
  bool volumeInterceptEventStream = false;
  Timer? volumeTimer;

  // ---- 轨道（原生 video_player 无 API，保持空列表） ----
  final RxList<AudioTrack> availableAudioTracks = <AudioTrack>[].obs;
  final RxList<VideoTrack> availableVideoTracks = <VideoTrack>[].obs;
  final RxList<SubtitleTrack> availableSubtitleTracks = <SubtitleTrack>[].obs;

  final Rx<AudioTrack?> currentAudioTrack = Rx<AudioTrack?>(null);
  final Rx<VideoTrack?> currentVideoTrack = Rx<VideoTrack?>(null);
  final Rx<SubtitleTrack?> currentSubtitleTrack = Rx<SubtitleTrack?>(null);

  // ---- 字幕样式（供未来集成 Flutter 层 SubtitleView 使用） ----
  late double subtitleFontScale = PlayerPref.subtitleFontScale;
  late double subtitleFontScaleFS = PlayerPref.subtitleFontScaleFS;
  late int subtitlePaddingH = PlayerPref.subtitlePaddingH;
  late int subtitlePaddingB = PlayerPref.subtitlePaddingB;
  late double subtitleBgOpacity = PlayerPref.subtitleBgOpacity;
  late double subtitleStrokeWidth = PlayerPref.subtitleStrokeWidth;
  late int subtitleFontWeight = PlayerPref.subtitleFontWeight;

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
  void updateSubtitleStyle() {
    subtitleConfig.value = getSubConfig;
  }

  @override
  void putSubtitleSettings() {}

  // ---- 弹幕 ----
  dynamic danmakuController;

  @override
  void toggleDanmaku() {
    enableShowDanmaku.value = !enableShowDanmaku.value;
  }

  @override
  void refreshDanmakuConfig() {}

  // ---- 播放模式 ----
  PlayRepeat playRepeat = PlayRepeat.pause;

  // ---- 配置 ----
  late final showControlDuration = PlayerPref.enableLongShowControl
      ? const Duration(seconds: 30)
      : const Duration(seconds: 3);
  late final enableShrinkVideoSize = PlayerPref.enableShrinkVideoSize;
  late final enableSlideVolumeBrightness =
      PlayerPref.enableSlideVolumeBrightness;
  late final enableSlideFS = PlayerPref.enableSlideFS;
  late final fastForBackwardDuration = Duration(
    seconds: PlayerPref.fastForBackwardDuration,
  );
  late final showFsScreenshotBtn = PlayerPref.showFsScreenshotBtn;
  late final showFsLockBtn = PlayerPref.showFsLockBtn;
  late final fullScreenGestureReverse = PlayerPref.fullScreenGestureReverse;
  late final enableQuickDouble = PlayerPref.enableQuickDouble;
  late final FullScreenMode mode =
      FullScreenMode.values[PlayerPref.fullScreenMode];
  late final bool horizontalScreen = PlayerPref.horizontalScreen;
  late final bool removeSafeArea = PlayerPref.removeSafeArea;
  late final bool autoEnterFullScreen = PlayerPref.autoEnterFullScreen;
  late final bool autoExitFullscreen = PlayerPref.autoExitFullscreen;

  final RxInt progressType = PlayerPref.btmProgressBehavior.obs;
  final RxInt skipStartDuration = 0.obs;
  final RxInt skipEndDuration = 0.obs;

  // ---- 数据源 ----
  late DataSource dataSource;

  // ---- 工具 ----
  bool _processing = false;
  bool get processing => _processing;
  String? _vodId;
  String? get vodId => _vodId;
  int? _width;
  int? _height;
  int? get width => _width;
  int? get height => _height;
  bool _isCloseAll = false;
  bool get isCloseAll => _isCloseAll;
  bool get setSystemBrightness => false;

  // ---- 电池电量 ----
  final RxString batteryLevel = '--'.obs;
  final Battery _battery = Battery();
  StreamSubscription? _batterySubscription;

  // ---- 监听器 ----
  final Set<ValueChanged<Duration>> _positionListeners = {};
  final Set<ValueChanged<PlayerStatus>> _statusListeners = {};
  VoidCallback? _listenerCallback;

  // ---- 快进快退 ----
  final RxBool mountSeekBackwardButton = false.obs;
  final RxBool mountSeekForwardButton = false.obs;
  bool? cancelSeek;
  bool? hasToast;
  Timer? _longPressTimer;
  Timer? _timer;
  double lastPlaybackSpeed = 1.0;

  // ---- 分辨率 / 网速 ----
  final RxInt _videoWidth = 0.obs;
  final RxInt _videoHeight = 0.obs;
  final RxDouble _downloadSpeed = 0.0.obs;

  @override
  RxInt get videoWidth => _videoWidth;
  @override
  RxInt get videoHeight => _videoHeight;
  @override
  RxDouble get downloadSpeed => _downloadSpeed;

  // ============================================================
  // 2. getter / setter 实现
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
  // 3. 生命周期
  // ============================================================
  VideoPlayerEngine();

  @override
  Future<void> init() async {
    _isDisposed = false;
    // 初始化电池监听（与 MediaKitEngine 保持一致）
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
  // 4. 核心播放控制
  // ============================================================

  void _updateVideoSize() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    final size = controller.value.size;
    if (size != null) {
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
          httpHeaders: dataSource.headers ?? {},
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

      // 不调用 _updateTracks()（原生 video_player 无轨道 API）

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

      _width = _controller!.value.size?.width.toInt() ?? width;
      _height = _controller!.value.size?.height.toInt() ?? height;
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
    // 幂等保护
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
    final target = position < Duration.zero ? Duration.zero : position;
    if (target > duration.value) return;

    // 使用标准 seekTo（不使用 FVP 专有的 fastSeekTo）
    await _controller!.seekTo(target);
    this.position = target;
    updatePositionSecond();
  }

  @override
  Future<void> refreshPlayer() async {
    if (_controller == null || dataSource == null) return;
    final currentPosition = position;
    final wasPlaying = _isPlaying;

    await setDataSource(
      dataSource,
      autoplay: false,
      seekTo: currentPosition,
    );

    if (wasPlaying) {
      await play();
    }
  }

  // ============================================================
  // 5. 音量
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
  // 6. 倍速
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
  // 7. 全屏
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
        debugPrint('VideoPlayerEngine triggerFullScreen error: $e');
      }
    }

    _isFullscreen = status;
    isFullScreen.value = status;
  }

  @override
  Future<void> setOrientation(List<DeviceOrientation> orientations) async {
    if (!PlatformUtils.isMobile) return;
    await SystemChrome.setPreferredOrientations(orientations);
  }

  // ============================================================
  // 8. 轨道控制（全部改为仅记录状态）
  // ============================================================

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    // 原生 video_player 不支持运行时切音轨，仅记录状态
    currentAudioTrack.value = track;
  }

  @override
  Future<void> setVideoTrack(VideoTrack track) async {
    currentVideoTrack.value = track;
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    // 原生 video_player 不支持运行时挂载外挂字幕
    // 如需字幕，请在 Flutter 层用自定义 SubtitleView 渲染
    currentSubtitleTrack.value = track;
  }

  // ============================================================
  // 9. 截图（原生 video_player 无 API）
  // ============================================================

  @override
  Future<void> takeScreenshot() async {
    if (_controller == null || !_isInitialized) {
      SmartDialog.showToast('播放器未就绪');
      return;
    }
    // 原生 video_player 不提供 snapshot API
    // 如需实现，可用 RepaintBoundary + RenderRepaintBoundary.toImage()
    SmartDialog.showToast('当前内核暂不支持截图');
  }

  // ============================================================
  // 10. 画中画（移动端系统 PiP 需平台通道）
  // ============================================================

  @override
  Future<void> enterDesktopPip() async {
    // 移动端系统 PiP 需通过原生 platform channel 触发
    // 如需实现，可接入 pip_flutter 或自写 MethodChannel
  }

  @override
  Future<void> exitDesktopPip() async {}

  @override
  void toggleDesktopPip() {}

  // ============================================================
  // 11. 其他控制
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
    if (!val && showControls.value) {
      showControls.refresh();
    }
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
  void onForward(Duration duration) {
    final newPos = position + duration;
    seekTo(newPos);
  }

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
    if (value != null) {
      sliderTempPosition.value = value;
    }
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
    if (cancelSeek != true) {
      feedBack();
    }
    cancelSeek = null;
    hasToast = null;
    isSliderMoving.value = false;
    hideTaskControls();
  }

  @override
  void updateSliderPositionSecond() {
    int newSecond = sliderPosition.inSeconds;
    if (sliderPositionSeconds.value != newSecond) {
      sliderPositionSeconds.value = newSecond;
    }
  }

  @override
  void updatePositionSecond() {
    int newSecond = position.inSeconds;
    if (positionSeconds.value != newSecond) {
      positionSeconds.value = newSecond;
    }
  }

  @override
  void updateBufferedSecond() {
    int newSecond = buffered.value.inSeconds;
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
      if (!isSliderMoving.value) {
        controls = false;
      }
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
      if (_isPlaying) {
        pause();
      }
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
  void toggleVideoFit(VideoFitType value) {
    videoFit.value = value;
  }

  // ============================================================
  // 12. 监听器管理
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

      // 缓冲计算
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

      // 播放状态变化
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

      final endSkip = skipEndDuration.value;
      if (endSkip > 0) {
        final total = duration.value.inSeconds;
        if (total > 0 && value.position.inSeconds >= total - endSkip) {
          if (_isPlaying) {
            pause();
            SmartDialog.showToast('已跳过片尾');
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
  void addPositionListener(ValueChanged<Duration> listener) {
    _positionListeners.add(listener);
  }

  @override
  void removePositionListener(ValueChanged<Duration> listener) {
    _positionListeners.remove(listener);
  }

  @override
  void addStatusLister(ValueChanged<PlayerStatus> listener) {
    _statusListeners.add(listener);
  }

  @override
  void removeStatusLister(ValueChanged<PlayerStatus> listener) {
    _statusListeners.remove(listener);
  }

  // ============================================================
  // 13. 渲染
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
        final videoSize = controller.value.size;
        final double width = videoSize?.width ?? 640;
        final double height = videoSize?.height ?? 360;

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
  // 14. 跳过片头片尾
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
  // 15. 功能标志
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
}