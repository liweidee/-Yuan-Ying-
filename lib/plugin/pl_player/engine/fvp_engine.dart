// lib/plugin/pl_player/engine/fvp_engine.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';
import 'package:fvp/fvp.dart' as fvp;

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

/// FVP 播放器引擎实现
class FvpEngine implements IPlayerEngine {
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

  // ---- position 和 sliderPosition 作为公开字段 ----
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
  bool _controlsLock = false;

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

  // ---- 轨道数据 ----
  final RxList<AudioTrack> availableAudioTracks = <AudioTrack>[].obs;
  final RxList<VideoTrack> availableVideoTracks = <VideoTrack>[].obs;
  final RxList<SubtitleTrack> availableSubtitleTracks = <SubtitleTrack>[].obs;

  final Rx<AudioTrack?> currentAudioTrack = Rx<AudioTrack?>(null);
  final Rx<VideoTrack?> currentVideoTrack = Rx<VideoTrack?>(null);
  final Rx<SubtitleTrack?> currentSubtitleTrack = Rx<SubtitleTrack?>(null);

  // ---- 字幕 ----
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

  void updateSubtitleStyle() {
    subtitleConfig.value = getSubConfig;
  }

  void putSubtitleSettings() {}

  // ---- 弹幕 ----
  dynamic danmakuController;
  void toggleDanmaku() {
    enableShowDanmaku.value = !enableShowDanmaku.value;
  }
  void refreshDanmakuConfig() {}

  // ---- 播放模式 ----
  PlayRepeat playRepeat = PlayRepeat.pause;

  // ---- 配置 ----
  late final showControlDuration = PlayerPref.enableLongShowControl
      ? const Duration(seconds: 30)
      : const Duration(seconds: 3);
  late final enableShrinkVideoSize = PlayerPref.enableShrinkVideoSize;
  late final enableSlideVolumeBrightness = PlayerPref.enableSlideVolumeBrightness;
  late final enableSlideFS = PlayerPref.enableSlideFS;
  late final fastForBackwardDuration = Duration(
    seconds: PlayerPref.fastForBackwardDuration,
  );
  late final showFsScreenshotBtn = PlayerPref.showFsScreenshotBtn;
  late final showFsLockBtn = PlayerPref.showFsLockBtn;
  late final fullScreenGestureReverse = PlayerPref.fullScreenGestureReverse;
  late final enableQuickDouble = PlayerPref.enableQuickDouble;
  late final FullScreenMode mode = FullScreenMode.values[PlayerPref.fullScreenMode];
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
  final RxString batteryLevel = '--'.obs;

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

  // ============================================================
  // 2. getter 实现（IPlayerEngine 要求）
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
  bool get isDesktopPip => _isPipMode;
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
  FvpEngine();

  @override
  Future<void> init() async {
    _isDisposed = false;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    //（关闭 Rx 是导致 Null 异常的根源）
    // try { _initializedRx.close(); } catch (_) {}
    // try { _rebuildCounter.close(); } catch (_) {}

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

  /// 分辨率/网速
  final RxInt _videoWidth = 0.obs;
  final RxInt _videoHeight = 0.obs;
  final RxDouble _downloadSpeed = 0.0.obs;

  @override
  RxInt get videoWidth => _videoWidth;
  @override
  RxInt get videoHeight => _videoHeight;
  @override
  RxDouble get downloadSpeed => _downloadSpeed;

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
    debugPrint('[FvpEngine] setDataSource called, url=${dataSource.videoSource}');
    if (_isDisposed) {
      debugPrint('[FvpEngine] setDataSource: engine disposed, re-initializing');
      await init();
    }

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
      debugPrint('[FvpEngine] Creating controller...');
      if (dataSource is FileSource) {
        final filePath = dataSource.videoSource;
        _controller = VideoPlayerController.file(File(filePath));
      } else if (dataSource.videoSource.startsWith('http')) {
        final headers = dataSource.headers ?? {};
        debugPrint('[FvpEngine] Using headers: $headers');
        _controller = VideoPlayerController.network(
          dataSource.videoSource,
          httpHeaders: headers,
        );
      } else {
        _controller = VideoPlayerController.network(dataSource.videoSource);
      }

      if (_controller == null) {
        dataStatus.value = DataStatus.error;
        _processing = false;
        return;
      }

      debugPrint('[FvpEngine] Calling initialize...');
      if (_controller == null) {
        dataStatus.value = DataStatus.error;
        _processing = false;
        return;
      }
      await _controller!.initialize();
      debugPrint('[FvpEngine] Initialize completed');
      _isInitialized = true;
      _initializedRx.value = true;
      _rebuildCounter.value++;

      _isInitialized = true;
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
        _controller!.setLooping(true);
      }

      if (seekTo != null && seekTo.inSeconds > 0) {
        await _controller!.seekTo(seekTo);
        position = seekTo;
        updatePositionSecond();
      }

      _updateTracks();

      dataStatus.value = DataStatus.loaded;
      isBuffering.value = false;
      _updateVideoSize();

      _addListeners();

      if (autoplay) {
        debugPrint('[FvpEngine] Autoplay: playing');
        // 如果已经处于播放状态，先重置再播放（确保干净状态）
        if (_isPlaying) {
          _isPlaying = false;
        }
        await _controller!.play();
        _isPlaying = true;
        playerStatus.value = PlayerStatus.playing;
        this.duration.refresh();
        debugPrint('[FvpEngine] Autoplay: playing done, isPlaying=$_isPlaying');
      } else {
        debugPrint('[FvpEngine] Autoplay: paused');
        playerStatus.value = PlayerStatus.paused;
      }

      onInit?.call();

      if (autoFullScreenFlag && autoEnterFullScreen) {
        triggerFullScreen(status: true);
      }

      _width = _controller!.value.size?.width.toInt() ?? width;
      _height = _controller!.value.size?.height.toInt() ?? height;

      debugPrint('[FvpEngine] setDataSource completed successfully');

    } catch (e, stack) {
      debugPrint('[FvpEngine] setDataSource error: $e');
      debugPrint(stack.toString());
      dataStatus.value = DataStatus.error;
      isBuffering.value = false;
      _initializedRx.value = false;
      _controller?.dispose();
      _controller = null;
      if (kDebugMode) {
        debugPrint('FvpEngine.setDataSource error: $e');
      }
    } finally {
      _processing = false;
    }
  }

  @override
  Future<void> play({bool repeat = false, bool hideControls = true}) async {
    debugPrint('[FvpEngine] play() called, repeat=$repeat, current _isPlaying=$_isPlaying');
    if (_controller == null || !_isInitialized) {
      debugPrint('[FvpEngine] play() skipped: controller=$_controller, isInitialized=$_isInitialized');
      return;
    }
    
    // ===== 幂等性保护：如果已经在播放，直接返回，不触发内部状态机重置 =====
    if (_isPlaying && _controller!.value.isPlaying) {
      debugPrint('[FvpEngine] play() skipped: already playing, no-op');
      return;
    }
    
    controls = !hideControls;
    if (repeat) {
      await _controller!.seekTo(Duration.zero);
    }
    await _controller!.play();
    _isPlaying = true;
    playerStatus.value = PlayerStatus.playing;
    duration.refresh();
    debugPrint('[FvpEngine] play() completed, _isPlaying=$_isPlaying');
  }

  @override
  Future<void> pause({bool notify = true, bool isInterrupt = false}) async {
    debugPrint('[FvpEngine] pause() called');
    if (_controller == null || !_isInitialized) return;
    await _controller!.pause();
    _isPlaying = false;
    playerStatus.value = PlayerStatus.paused;
    debugPrint('[FvpEngine] pause() completed');
  }

  @override
  Future<void> seekTo(Duration position, {bool isSeek = true}) async {
    if (_controller == null || !_isInitialized) return;
    final target = position < Duration.zero ? Duration.zero : position;
    if (target > duration.value) {
      return;
    }
    try {
      await _controller!.fastSeekTo(target);
    } catch (_) {
      await _controller!.seekTo(target);
    }
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

    if (PlatformUtils.isDesktop) {
      try {
        if (status) {
          await enterDesktopFullScreen(inAppFullScreen: inAppFullScreen);
        } else {
          await exitDesktopFullScreen();
        }
      } catch (e) {
        debugPrint('FvpEngine triggerFullScreen error: $e');
      }
    }

    _isFullscreen = status;
    isFullScreen.value = status;
  }

  // ============================================================
  // 8. 轨道控制
  // ============================================================

  void _updateTracks() {
    if (_controller == null || !_isInitialized) return;

    try {
      final audioTracks = (_controller!.getActiveAudioTracks() ?? []) as List<dynamic>;
      final videoTracks = (_controller!.getActiveVideoTracks() ?? []) as List<dynamic>;
      final subtitleTracks = (_controller!.getActiveSubtitleTracks() ?? []) as List<dynamic>;

      availableAudioTracks.clear();
      availableVideoTracks.clear();
      availableSubtitleTracks.clear();

      for (final item in audioTracks) {
        final idx = item is int ? item : 0;
        availableAudioTracks.add(AudioTrack(
          'fvp_audio_$idx',
          '音轨 ${idx + 1}',
          '',
        ));
      }

      for (final item in videoTracks) {
        final idx = item is int ? item : 0;
        availableVideoTracks.add(VideoTrack(
          'fvp_video_$idx',
          '视轨 ${idx + 1}',
          '',
        ));
      }

      for (final item in subtitleTracks) {
        final idx = item is int ? item : 0;
        availableSubtitleTracks.add(SubtitleTrack(
          'fvp_subtitle_$idx',
          '字幕 ${idx + 1}',
          '',
          uri: false,
        ));
      }

      if (audioTracks.isNotEmpty) {
        final firstIdx = audioTracks[0] is int ? audioTracks[0] as int : 0;
        currentAudioTrack.value = AudioTrack(
          'fvp_audio_$firstIdx',
          '音轨 ${firstIdx + 1}',
          '',
        );
      }
      if (videoTracks.isNotEmpty) {
        final firstIdx = videoTracks[0] is int ? videoTracks[0] as int : 0;
        currentVideoTrack.value = VideoTrack(
          'fvp_video_$firstIdx',
          '视轨 ${firstIdx + 1}',
          '',
        );
      }
      if (subtitleTracks.isNotEmpty) {
        final firstIdx = subtitleTracks[0] is int ? subtitleTracks[0] as int : 0;
        currentSubtitleTrack.value = SubtitleTrack(
          'fvp_subtitle_$firstIdx',
          '字幕 ${firstIdx + 1}',
          '',
          uri: false,
        );
      }

    } catch (e) {
      if (kDebugMode) debugPrint('FvpEngine._updateTracks error: $e');
    }
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    if (_controller == null || !_isInitialized) return;
    final id = track.id;
    if (id.startsWith('fvp_audio_')) {
      final index = int.tryParse(id.substring('fvp_audio_'.length));
      if (index != null) {
        try {
          _controller!.setAudioTracks([index]);
          currentAudioTrack.value = track;
        } catch (e) {
          if (kDebugMode) debugPrint('setAudioTrack error: $e');
        }
      }
    }
  }

  @override
  Future<void> setVideoTrack(VideoTrack track) async {
    currentVideoTrack.value = track;
  }

  // fvp_engine.dart - setSubtitleTrack 方法（修改后）

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    if (_controller == null || !_isInitialized) return;
    final id = track.id;
    if (id.isEmpty) {
      currentSubtitleTrack.value = track;
      return;
    }

    // 判断是否为外部字幕（URI 或路径）
    bool isExternal = track.uri ||
        id.startsWith('http') ||
        id.startsWith('file://') ||
        id.startsWith('/') ||
        (Platform.isWindows && (id.contains(':\\') || id.startsWith('\\\\')));

    if (isExternal) {
      try {
        String subtitleId = id;
        // 核心转换：将 file:// URI 转为本地文件路径
        if (subtitleId.startsWith('file://')) {
          // 去掉 "file://" 前缀
          String pathPart = subtitleId.substring('file://'.length);
          // Windows 下路径形如 "/C:/..."，需要去掉前导 "/"
          if (Platform.isWindows && pathPart.startsWith('/')) {
            pathPart = pathPart.substring(1);
          }
          // 解码 URL 百分号编码（如中文、空格等）
          subtitleId = Uri.decodeComponent(pathPart);
        }

        // 调用底层加载（传入纯文件路径）
        _controller!.setExternalSubtitle(subtitleId);
        currentSubtitleTrack.value = track;
        if (kDebugMode) {
          debugPrint('FvpEngine: 设置外挂字幕文件: $subtitleId');
        }
        return;
      } catch (e) {
        if (kDebugMode) debugPrint('FvpEngine setExternalSubtitle error: $e');
        // 失败时仍记录状态，避免 UI 不一致
      }
    }
    // 非外部字幕只记录状态
    currentSubtitleTrack.value = track;
  }

  // ============================================================
  // 9. 截图
  // ============================================================

  @override
  Future<void> takeScreenshot() async {
    if (_controller == null || !_isInitialized) {
      SmartDialog.showToast('播放器未就绪');
      return;
    }
    try {
      final imageData = await _controller!.snapshot();
      if (imageData != null) {
        SmartDialog.showToast('截图成功');
      } else {
        SmartDialog.showToast('截图失败');
      }
    } catch (e) {
      SmartDialog.showToast('截图失败: $e');
    }
  }

  // ============================================================
  // 10. 画中画（FVP 不支持）
  // ============================================================

  @override
  Future<void> enterDesktopPip() async {}
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
    bufferedSeconds.value = 0;
  }

  set controls(bool visible) {
    showControls.value = visible;
    _timer?.cancel();
    if (visible) {
      // 强制复位
      isSliderMoving.value = false;
      hideTaskControls();
    }
  }

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
      // ===== 防止在销毁后继续处理回调 =====
      if (_isDisposed) return;
      final controller = _controller;
      if (controller == null || !_isInitialized) return;
      final value = controller.value;

      if (value.hasError) {
        debugPrint('[FvpEngine] 播放错误: ${value.errorDescription}');
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
        debugPrint('[FvpEngine] _listener: playing -> true');
        for (final listener in _statusListeners) {
          listener(PlayerStatus.playing);
        }
      } else if (!value.isPlaying && _isPlaying) {
        _isPlaying = false;
        playerStatus.value = PlayerStatus.paused;
        debugPrint('[FvpEngine] _listener: playing -> false');
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
      // 1. 强制依赖重建计数器（无论是否初始化，都会追踪）
      final rebuild = _rebuildCounter.value;
      
      // 2. 显式读取播放器状态（如果控制器存在）
      bool isInitialized = false;
      try {
        if (_controller != null) {
          isInitialized = _controller!.value.isInitialized;
        }
      } catch (_) {}

      // 3. 强制依赖 isInitialized（动态变化）
      // 虽然 isInitialized 不是 Rx，但通过 rebuild 触发重建
      
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
          key: ValueKey(rebuild), // 利用 rebuild 强制重建
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
  bool get supportsAudioTrack => true;
  @override
  bool get supportsVideoTrack => false;
  @override
  bool get supportsEmbeddedSubtitle => false;
  @override
  bool get supportsHardwareAcceleration => false;
  @override
  bool get supportsScreenshot => true;
  @override
  bool get supportsPictureInPicture => false;
  @override
  bool get supportsBufferProgress => true;
}