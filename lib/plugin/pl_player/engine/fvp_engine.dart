// lib/plugin/pl_player/engine/fvp_engine.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart' hide VideoTrack, SubtitleTrack;
import 'package:fvp/fvp.dart' as fvp;
import 'package:fvp/mdk.dart' as mdk;
import 'package:battery_plus/battery_plus.dart';

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
import 'package:yuanying/utils/image_utils.dart';

/// FVP 播放器引擎实现
class FvpEngine implements IPlayerEngine {
  // ============================================================
  // 1. 私有成员
  // ============================================================
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _skipEndTriggered = false;
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

  // ============================================================
  // 1.1 FVP 高级特性（官方 0.38.0+ 扩展）
  // ============================================================

  /// 直播检测（FVP 扩展 `isLive()`）
  final RxBool isLive = false.obs;

  /// 媒体详细信息（FVP 扩展 `getMediaInfo()`，类型为 mdk.MediaInfo）
  final Rxn<dynamic> mediaInfo = Rxn<dynamic>();

  /// 当前字幕文本（FVP 扩展 `onSubtitleText()`）
  final Rxn<String> currentSubtitleText = Rxn<String>();

  /// 外部音频 URL（FVP 扩展 `setMedia(MediaType.audio)`）
  String? _externalAudioUrl;

  /// 截图用的 GlobalKey（包裹视频层 RepaintBoundary）
  final GlobalKey _screenshotKey = GlobalKey();

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
  @override
  bool get enableTapDm => PlayerPref.enableTapDm;

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

  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;

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
    initBatteryListener();
  }

  void initBatteryListener() {
    // 先取消旧的，避免重复 init 时叠加订阅
    _batterySubscription?.cancel();
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
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

    // 清理外部音频状态
    _externalAudioUrl = null;

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

    _skipEndTriggered = false;   // 重置跳过片尾标志

    _processing = true;
    _vodId = vodId;
    _width = width;
    _height = height;
    _playbackSpeed = speed;
    this.dataSource = dataSource;

    // 切换媒体前清理状态（避免 fvp Issue #85 外部音频 bug）
    _externalAudioUrl = null;
    mediaInfo.value = null;
    currentSubtitleText.value = null;
    isLive.value = false;

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

      // ============================================================
      // FVP 官方扩展初始化（必须在 initialize 之后调用）
      // ============================================================

      // 1) 缓冲范围（FVP 扩展 `setBufferRange`）
      try {
        final bufMin = PlayerPref.mdkBufferMin;
        final bufMax = PlayerPref.mdkBufferMax;
        _controller!.setBufferRange(min: bufMin, max: bufMax);
        debugPrint('[FvpEngine] setBufferRange: min=$bufMin, max=$bufMax');
      } catch (e) {
        debugPrint('[FvpEngine] setBufferRange 失败: $e');
      }

      // 2) 直播检测（FVP 扩展 `isLive()`）
      try {
        isLive.value = _controller!.isLive();
        debugPrint('[FvpEngine] isLive = ${isLive.value}');
      } catch (e) {
        debugPrint('[FvpEngine] isLive 失败: $e');
      }

      // 3) 媒体详情（FVP 扩展 `getMediaInfo()`）
      try {
        mediaInfo.value = _controller!.getMediaInfo();
        debugPrint('[FvpEngine] mediaInfo 已获取');
      } catch (e) {
        debugPrint('[FvpEngine] getMediaInfo 失败: $e');
      }

      // 4) 字幕文本回调（FVP 扩展 `onSubtitleText()`）
      try {
        _controller!.onSubtitleText((start, end, text) {
          currentSubtitleText.value = text.join('\n');
        });
        debugPrint('[FvpEngine] onSubtitleText 已注册');
      } catch (e) {
        debugPrint('[FvpEngine] onSubtitleText 注册失败: $e');
      }

      // ============================================================

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

    // 幂等性保护：如果已经在播放，直接返回
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
      await _controller!.seekTo(target);
    } catch (_) {
      await _controller!.seekTo(target);
    }

    // ============================================================
    // 参考：FVP 扩展方法 fastSeekTo 用法（默认不启用）
    // ============================================================
    // 官方文档：fast seek to a key frame
    // 特点：跳转更快，但结果位置可能与请求位置有偏差（不精确）
    // 适用场景：快速预览、长按倍速前进
    // 注意：会导致跳过片头片尾不准、拖拽进度条偏移
    //
    // 接入方式：
    //   try {
    //     await _controller!.fastSeekTo(target);
    //   } catch (_) {
    //     await _controller!.seekTo(target);
    //   }

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
        debugPrint('FvpEngine triggerFullScreen error: $e');
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
  // 8. 轨道控制
  // ============================================================

  /// 刷新轨道列表
  ///
  /// 关键点 1：`getActiveAudioTracks()` / `getActiveSubtitleTracks()`
  /// 返回的是"轨道在列表中的位置"（0-indexed），不是流的全局 index。
  /// 因此 track.id 后缀必须用列表位置 i。
  ///
  /// 关键点 2：MKV 压制常留下空占位字幕轨（只有 1 帧 / 几十字节），
  /// 切换这类轨道无任何视觉效果。需通过 metadata 里的
  /// NUMBER_OF_FRAMES / NUMBER_OF_BYTES 过滤掉它们，
  /// 与 MPV 内核的 _isValidSubtitleTrack 行为对齐。
  void _updateTracks() {
    if (_controller == null || !_isInitialized) return;

    try {
      availableAudioTracks.clear();
      availableVideoTracks.clear();
      availableSubtitleTracks.clear();

      final info = _controller!.getMediaInfo();

      if (info != null) {
        // ===== 音轨 =====
        final audioList = info.audio ?? [];
        for (int i = 0; i < audioList.length; i++) {
          final stream = audioList[i];
          String? title;
          String? lang;
          try {
            final m = stream.metadata;
            if (m is Map) {
              title = m['title']?.toString();
              lang = m['language']?.toString();
            }
          } catch (_) {}

          String codecName = '';
          final codecObj = stream.codec;
          if (codecObj != null) {
            try {
              codecName = (codecObj as dynamic).codec?.toString() ?? '';
            } catch (_) {}
          }

          final buf = StringBuffer();
          if (title != null && title.isNotEmpty) {
            buf.write(title);
          } else if (lang != null && lang.isNotEmpty) {
            buf.write('音轨 ${i + 1} ($lang)');
          } else {
            buf.write('音轨 ${i + 1}');
          }
          if (codecName.isNotEmpty) buf.write(' · ${codecName.toUpperCase()}');

          availableAudioTracks.add(
            AudioTrack('fvp_audio_$i', buf.toString(), lang ?? ''),
          );
        }

        // ===== 视轨 =====
        final videoList = info.video ?? [];
        for (int i = 0; i < videoList.length; i++) {
          final stream = videoList[i];
          String codecName = '';
          final codecObj = stream.codec;
          if (codecObj != null) {
            try {
              codecName = (codecObj as dynamic).codec?.toString() ?? '';
            } catch (_) {}
          }
          final rotation = stream.rotation;
          final buf = StringBuffer('视轨 ${i + 1}');
          if (codecName.isNotEmpty) buf.write(' · ${codecName.toUpperCase()}');
          if (rotation != null && rotation != 0) buf.write(' · ${rotation}°');

          availableVideoTracks.add(
            VideoTrack('fvp_video_$i', buf.toString(), ''),
          );
        }

        // ===== 字幕轨 =====
        final subtitleList = info.subtitle ?? [];
        for (int i = 0; i < subtitleList.length; i++) {
          final stream = subtitleList[i];

          // ---- 空占位字幕轨过滤 ----
          // MKV 压制常留下只有 1 帧/几十字节的空字幕轨，
          // 切换时无任何视觉效果，会造成"点了没反应"的困惑。
          int? frameCount;
          int? byteCount;
          try {
            final m = stream.metadata;
            if (m is Map) {
              frameCount = int.tryParse(m['NUMBER_OF_FRAMES']?.toString() ?? '');
              byteCount = int.tryParse(m['NUMBER_OF_BYTES']?.toString() ?? '');
            }
          } catch (_) {}

          final isEmptyTrack =
              (frameCount != null && frameCount < 2) ||
              (byteCount != null && byteCount < 100);

          if (isEmptyTrack) {
            debugPrint('[FvpEngine] 跳过空占位字幕轨 '
                'index=${stream.index} (frames=$frameCount, bytes=$byteCount)');
            continue;
          }

          String? title;
          String? lang;
          try {
            final m = stream.metadata;
            if (m is Map) {
              title = m['title']?.toString();
              lang = m['language']?.toString();
            }
          } catch (_) {}

          final buf = StringBuffer();
          if (title != null && title.isNotEmpty) {
            buf.write(title);
          } else if (lang != null && lang.isNotEmpty) {
            buf.write('字幕 ${i + 1} ($lang)');
          } else {
            buf.write('字幕 ${i + 1}');
          }

          // 用过滤后列表的长度作为 id 后缀，
          // 保证 id 连续（0,1,2...），与 setSubtitleTracks 的位置语义匹配。
          final pos = availableSubtitleTracks.length;
          availableSubtitleTracks.add(
            SubtitleTrack('fvp_subtitle_$pos', buf.toString(), lang ?? '', uri: false),
          );
        }
      }

      // ===== 降级：仅在 mediaInfo 完全读取失败时触发 =====
      // 关键：不能用"过滤后列表是否为空"作为降级条件，
      //      否则"所有字幕轨都被过滤掉"的正常情况会被降级路径重新填充假轨道。
      if (info == null) {
        if (availableAudioTracks.isEmpty) {
          final active = _controller!.getActiveAudioTracks() ?? [];
          for (int i = 0; i < active.length; i++) {
            availableAudioTracks.add(
              AudioTrack('fvp_audio_${active[i]}', '音轨 ${i + 1}', ''),
            );
          }
        }
        if (availableSubtitleTracks.isEmpty) {
          final active = _controller!.getActiveSubtitleTracks() ?? [];
          for (int i = 0; i < active.length; i++) {
            availableSubtitleTracks.add(
              SubtitleTrack('fvp_subtitle_${active[i]}', '字幕 ${i + 1}', '', uri: false),
            );
          }
        }
      }

      // ===== 同步当前激活 =====
      final activeAudio = _controller!.getActiveAudioTracks() ?? [];
      if (activeAudio.isNotEmpty) {
        final pos = activeAudio.first;
        if (pos >= 0 && pos < availableAudioTracks.length) {
          currentAudioTrack.value = availableAudioTracks[pos];
        } else {
          currentAudioTrack.value = null;
        }
      } else {
        currentAudioTrack.value = null;
      }

      final activeVideo = _controller!.getActiveVideoTracks() ?? [];
      if (activeVideo.isNotEmpty) {
        final pos = activeVideo.first;
        if (pos >= 0 && pos < availableVideoTracks.length) {
          currentVideoTrack.value = availableVideoTracks[pos];
        } else {
          currentVideoTrack.value = null;
        }
      } else {
        currentVideoTrack.value = null;
      }

      final activeSubtitle = _controller!.getActiveSubtitleTracks() ?? [];
      if (activeSubtitle.isNotEmpty) {
        final pos = activeSubtitle.first;
        if (pos >= 0 && pos < availableSubtitleTracks.length) {
          currentSubtitleTrack.value = availableSubtitleTracks[pos];
        } else {
          // 底层说有激活轨，但过滤后列表为空 → 视为"无字幕"
          currentSubtitleTrack.value = null;
        }
      } else {
        currentSubtitleTrack.value = null;
      }
    } catch (e, st) {
      debugPrint('[FvpEngine] _updateTracks error: $e\n$st');
    }
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    if (_controller == null || !_isInitialized) return;
    final id = track.id;

    // 关闭音轨
    if (id == 'no' || id.isEmpty) {
      try {
        _controller!.setAudioTracks([]);
      } catch (e) {
        debugPrint('[FvpEngine] 关闭音轨失败: $e');
      }
      currentAudioTrack.value = track;
      return;
    }

    // 自动选择
    if (id == 'auto') {
      try {
        _controller!.setAudioTracks([0]);
      } catch (e) {
        debugPrint('[FvpEngine] 自动选择失败: $e');
      }
      currentAudioTrack.value = track;
      return;
    }

    // 指定音轨
    if (!id.startsWith('fvp_audio_')) return;
    final position = int.tryParse(id.substring('fvp_audio_'.length));
    if (position == null) return;

    try {
      _controller!.setAudioTracks([position]);
      currentAudioTrack.value = track;
    } catch (e) {
      debugPrint('[FvpEngine] 音轨切换失败: $e');
    }
  }

  @override
  Future<void> setVideoTrack(VideoTrack track) async {
    // FVP 不支持运行时切换视频轨
    // 原因：FVPControllerExtensions 只提供 getActiveVideoTracks() 查询，
    //      没有对应的 setVideoTracks() 切换 API
    debugPrint('[FvpEngine] FVP 不支持切换视频轨，操作已忽略');
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    if (_controller == null || !_isInitialized) return;
    final id = track.id;

    // 关闭字幕
    if (id == 'no' || id.isEmpty) {
      try {
        _controller!.setSubtitleTracks([]);
      } catch (e) {
        debugPrint('[FvpEngine] 关闭字幕失败: $e');
      }
      currentSubtitleTrack.value = track;
      return;
    }

    // 自动选择
    if (id == 'auto') {
      try {
        _controller!.setSubtitleTracks([0]);
      } catch (e) {
        debugPrint('[FvpEngine] 自动选择字幕失败: $e');
      }
      currentSubtitleTrack.value = track;
      return;
    }

    // 内嵌字幕轨
    if (id.startsWith('fvp_subtitle_')) {
      final position = int.tryParse(id.substring('fvp_subtitle_'.length));
      if (position != null) {
        try {
          _controller!.setSubtitleTracks([position]);
          currentSubtitleTrack.value = track;
        } catch (e) {
          debugPrint('[FvpEngine] 切换内嵌字幕失败: $e');
        }
        return;
      }
    }

    // 外部字幕文件
    bool isExternal = track.uri ||
        id.startsWith('http') ||
        id.startsWith('file://') ||
        id.startsWith('/') ||
        (Platform.isWindows && (id.contains(':\\') || id.startsWith('\\\\')));

    if (isExternal) {
      try {
        String subtitleId = id;
        if (subtitleId.startsWith('file://')) {
          String pathPart = subtitleId.substring('file://'.length);
          if (Platform.isWindows && pathPart.startsWith('/')) {
            pathPart = pathPart.substring(1);
          }
          subtitleId = Uri.decodeComponent(pathPart);
        }
        _controller!.setExternalSubtitle(subtitleId);
        currentSubtitleTrack.value = track;

        // ===== 关键补充 =====
        // FVP 的 getMediaInfo() 不返回外挂字幕，需要手动加入可选列表，
        // 否则底部 CC 按钮因 availableSubtitleTracks 为空而隐藏，
        // 用户无法在多个外挂字幕（含 AI 翻译）之间切换。
        if (!availableSubtitleTracks.any((t) => t.id == track.id)) {
          availableSubtitleTracks.add(track);
        }
      } catch (e) {
        debugPrint('[FvpEngine] 加载外部字幕失败: $e');
      }
      return;
    }

    currentSubtitleTrack.value = track;
  }

  // ============================================================
  // 9. 截图
  // ============================================================

  @override
  Future<void> takeScreenshot() async {
    if (_isDisposed || _controller == null || !_isInitialized) {
      SmartDialog.showToast('播放器未就绪');
      return;
    }

    SmartDialog.showToast('截图中');

    try {
      final boundary = _screenshotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        SmartDialog.showToast('截图失败：界面未就绪');
        return;
      }

      // pixelRatio 决定分辨率，2.0 = 两倍图
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) {
        SmartDialog.showToast('截图失败');
        return;
      }

      final Uint8List imageBytes = byteData.buffer.asUint8List();

      SmartDialog.showToast('点击弹窗保存截图');
      showDialog(
        context: Get.context!,
        builder: (context) => GestureDetector(
          onTap: () async {
            try {
              await ImageUtils.saveByteImg(
                bytes: imageBytes,
                fileName: 'screenshot_${ImageUtils.time}',
              );
            } catch (e) {
              debugPrint('saveByteImg failed: $e');
            }
            if (Get.context != null) Get.back();
          },
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: min(MediaQuery.widthOf(context) / 3, 350),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      width: 5,
                      color: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Image.memory(imageBytes),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      SmartDialog.showToast('截图失败: $e');
    }
  }

  // ============================================================
  // 9.1 录制（FVP 扩展 `record`）
  // ============================================================
  //
  // 说明：
  //   - iOS 显式指定 h264_videotoolbox（Apple 硬件编码器）
  //   - Android 优先尝试 h264_mediacodec，失败则回退默认编码器
  //   - 其他平台（桌面端）保持默认编码器（已验证正常）
  //   - FVP API 不支持指定分辨率，录制跟随源视频分辨率
  //
  @override
  void record(String? path) {
    if (_controller == null || !_isInitialized) {
      debugPrint('[FvpEngine] record skipped: player not ready');
      return;
    }

    // 停止录制
    if (path == null || path.isEmpty) {
      try {
        _controller!.record(to: null);
        debugPrint('[FvpEngine] 录制停止');
      } catch (e) {
        debugPrint('[FvpEngine] 停止录制失败: $e');
      }
      return;
    }

    // 开始录制
    try {
      if (Platform.isIOS) {
        // iOS：显式指定 VideoToolbox 硬件编码器
        _controller!.record(to: path, format: 'h264_videotoolbox');
        debugPrint('[FvpEngine] 录制启动（iOS / h264_videotoolbox）: $path');
      } else if (Platform.isAndroid) {
        // Android：优先尝试 MediaCodec 硬件编码器，失败回退默认
        try {
          _controller!.record(to: path, format: 'h264_mediacodec');
          debugPrint('[FvpEngine] 录制启动（Android / h264_mediacodec）: $path');
        } catch (e) {
          debugPrint('[FvpEngine] h264_mediacodec 不可用，回退默认编码器: $e');
          _controller!.record(to: path);
          debugPrint('[FvpEngine] 录制启动（Android / 默认编码器）: $path');
        }
      } else {
        // 桌面端：使用默认编码器（已验证正常）
        _controller!.record(to: path);
        debugPrint('[FvpEngine] 录制启动（默认编码器）: $path');
      }
    } catch (e) {
      debugPrint('[FvpEngine] 录制启动失败: $e');
    }
  }

  // ============================================================
  // 9.2 外部音频（FVP 扩展，用于无音轨视频）
  // ============================================================
  //
  // 已知风险：fvp 官方 Issue #85 记录了外部音频的 bug，
  //   视频无音轨时加载外部音频后切换到普通视频可能卡顿/死锁。
  //   兜底策略：切换媒体源前清理外部音频（见 setDataSource 顶部）。
  //
  @override
  void setExternalAudio(String? url) {
    _externalAudioUrl = url;
    if (_controller == null || !_isInitialized) {
      debugPrint('[FvpEngine] setExternalAudio deferred: $url');
      return;
    }

    if (url == null || url.isEmpty) {
      debugPrint('[FvpEngine] 外部音频已清除');
      return;
    }

    try {
      final platform = (_controller as dynamic).platform;
      if (platform != null) {
        (platform as dynamic).setMedia(url, mdk.MediaType.audio);
        debugPrint('[FvpEngine] 外部音频已加载: $url');
      } else {
        debugPrint('[FvpEngine] 无法获取底层 Player');
      }
    } catch (e) {
      debugPrint('[FvpEngine] 外部音频加载异常: $e');
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
      // 防止在销毁后继续处理回调
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

      // ===== 轨道懒刷新：媒体完全加载后拉取 =====
      if (value.isInitialized &&
          availableAudioTracks.isEmpty &&
          availableSubtitleTracks.isEmpty) {
        _updateTracks();
      }

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

      // ===== 跳过片尾 =====
      // 关键：不能 pause，否则 completed 事件不会触发，自动切集会失效。
      // 改为 seek 到末尾前 500ms，让播放器自然播完，走正常切集流程。
      final endSkip = skipEndDuration.value;
      if (endSkip > 0 && !_skipEndTriggered) {
        final total = duration.value.inSeconds;
        if (total > 0 && value.position.inSeconds >= total - endSkip) {
          if (_isPlaying) {
            _skipEndTriggered = true;
            final nearEnd = Duration(seconds: total) -
                const Duration(milliseconds: 500);
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
    return RepaintBoundary(
      key: _screenshotKey,
      child: Obx(() {
        // 1. 强制依赖重建计数器
        final rebuild = _rebuildCounter.value;

        // 2. 显式读取播放器状态
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
      }),
    );
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