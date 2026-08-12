// lib/plugin/pl_player/engine/media_kit_engine.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show max, min;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart' show MPVLogLevel;
import 'package:hive_ce/hive.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:easy_debounce/easy_throttle.dart';

import 'package:yuanying/common/assets.dart';
import 'package:yuanying/common/widgets/gesture/player_gesture_recognizer.dart';
import 'package:yuanying/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:yuanying/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:yuanying/http/browser_ua.dart';
import 'package:yuanying/http/loading_state.dart';
import 'package:yuanying/plugin/pl_player/models/data_source.dart';
import 'package:yuanying/plugin/pl_player/models/data_status.dart';
import 'package:yuanying/plugin/pl_player/models/double_tap_type.dart';
import 'package:yuanying/plugin/pl_player/models/duration.dart';
import 'package:yuanying/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:yuanying/plugin/pl_player/models/play_repeat.dart';
import 'package:yuanying/plugin/pl_player/models/play_status.dart';
import 'package:yuanying/plugin/pl_player/models/video_fit_type.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/plugin/pl_player/utils/fullscreen.dart';
import 'package:yuanying/utils/device_utils.dart';
import 'package:yuanying/utils/duration_utils.dart';
import 'package:yuanying/utils/extension/box_ext.dart';
import 'package:yuanying/utils/extension/num_ext.dart';
import 'package:yuanying/utils/feed_back.dart';
import 'package:yuanying/utils/image_utils.dart';
import 'package:yuanying/utils/path_utils.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/utils/theme_utils.dart';
import 'package:yuanying/utils/utils.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/core/routes/app_pages.dart';

import 'package:canvas_danmaku/canvas_danmaku.dart';

import 'i_player_engine.dart';

typedef PlayCallback = Future<void>? Function();

/// media_kit 播放器引擎实现
class MediaKitEngine implements IPlayerEngine {
  // ============================================================
  // 1. 私有成员
  // ============================================================
  Player? _videoPlayerController;
  VideoController? _videoController;

  final playerStatus = PlPlayerStatus(PlayerStatus.playing);
  final Rx<DataStatus> dataStatus = Rx(DataStatus.none);

  Duration position = Duration.zero;
  final RxInt positionSeconds = 0.obs;

  Duration sliderPosition = Duration.zero;
  final RxInt sliderPositionSeconds = 0.obs;
  final Rx<Duration> sliderTempPosition = Rx(Duration.zero);

  final Rx<Duration> duration = Rx(Duration.zero);
  final Rx<Duration> buffered = Rx(Duration.zero);
  final RxInt bufferedSeconds = 0.obs;
  StreamSubscription<Duration>? _durationSubscription;

  bool _isDisposed = false;

  late double lastPlaybackSpeed = 1.0;
  final RxDouble _playbackSpeed = PlayerPref.playSpeedDefault.obs;
  late final RxDouble _longPressSpeed = PlayerPref.longPressSpeedDefault.obs;

  final RxDouble volume = RxDouble(
    PlatformUtils.isDesktop ? PlayerPref.desktopVolume : 1.0,
  );
  final setSystemBrightness = PlayerPref.setSystemBrightness;

  final RxDouble brightness = (-1.0).obs;
  final RxBool showControls = false.obs;
  final RxBool showBrightnessStatus = false.obs;
  final RxBool longPressStatus = false.obs;
  final RxBool controlsLock = false.obs;
  final RxBool isFullScreen = false.obs;

  bool _isVertical = false;
  final Rx<VideoFitType> videoFit = Rx(VideoFitType.contain);
  late final RxBool continuePlayInBackground = PlayerPref.continuePlayInBackground.obs;
  final RxBool isSliderMoving = false.obs;

  final RxBool onlyPlayAudio = false.obs;

  final RxInt skipStartDuration = 0.obs;
  final RxInt skipEndDuration = 0.obs;

  // ===== 轨道数据 =====
  final RxList<AudioTrack> availableAudioTracks = <AudioTrack>[].obs;
  final RxList<VideoTrack> availableVideoTracks = <VideoTrack>[].obs;
  final RxList<SubtitleTrack> availableSubtitleTracks = <SubtitleTrack>[].obs;

  final Rx<AudioTrack?> currentAudioTrack = Rx<AudioTrack?>(null);
  final Rx<VideoTrack?> currentVideoTrack = Rx<VideoTrack?>(null);
  final Rx<SubtitleTrack?> currentSubtitleTrack = Rx<SubtitleTrack?>(null);

  // ===== 电池电量 =====
  final RxString batteryLevel = '--'.obs;
  final Battery _battery = Battery();

  /// 初始化电池电量监听
  void initBatteryListener() {
    _battery.onBatteryStateChanged.listen((state) {
      _updateBatteryLevel();
    });
    _updateBatteryLevel();
  }

  /// 更新电池电量
  Future<void> _updateBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      batteryLevel.value = '$level%';
    } catch (_) {
      batteryLevel.value = '--%';
    }
  }

  bool _autoPlay = false;

  String? _vodId;
  String? get vodId => _vodId;

  int? _width;
  int? _height;

  // 新增响应式宽高
  final RxInt _videoWidth = 0.obs;
  final RxInt _videoHeight = 0.obs;

  // 下载速度
  final RxDouble _downloadSpeed = 0.0.obs;
  Timer? _speedTimer;
  Duration _lastBuffered = Duration.zero;
  DateTime _lastSpeedTime = DateTime.now();

  @override
  RxInt get videoWidth => _videoWidth;

  @override
  RxInt get videoHeight => _videoHeight;

  @override
  RxDouble get downloadSpeed => _downloadSpeed;

  late DataSource dataSource;

  Timer? _timer;
  StreamSubscription<Duration>? _subForSeek;
  StreamSubscription<Duration>? _durationSubscriptionForSkip;

  Box setting = Hive.box('app_settings');
  Box video = Hive.box('video_settings');

  Player? get videoPlayerController => _videoPlayerController;
  VideoController? get videoController => _videoController;

  double get playbackSpeed => _playbackSpeed.value;
  double get longPressSpeed => _longPressSpeed.value;
  bool get isVertical => _isVertical;
  bool get isFileSource => dataSource is FileSource;

  /// 静音状态
  bool _isMuted = false;

  final RxBool _isDesktopPip = false.obs;
  bool get isDesktopPip => _isDesktopPip.value;
  bool get showPreview => false;
  bool get enableBlock => false;
  bool get showViewPoints => false;
  bool get showDmChart => false;
  bool get isAnim => false;

  late Rect _lastWindowBounds;
  late final Map<String, ui.Image?> previewCache = {};
  late final RxBool _showPreview = false.obs;
  late final previewIndex = RxnInt();

  late final RxBool flipX = false.obs;
  late final RxBool flipY = false.obs;

  final RxBool isBuffering = true.obs;

  late final RxBool enableShowDanmaku = PlayerPref.enableShowDanmaku.obs;
  dynamic danmakuController;
  bool showDanmaku = true;
  late final RxDouble danmakuOpacity = PlayerPref.danmakuOpacity.obs;

  late final bool autoPiP = PlayerPref.autoPiP;
  bool get isPipMode => _isDesktopPip.value;

  late final showWindowTitleBar = PlayerPref.showWindowTitleBar;
  late final RxBool isAlwaysOnTop = false.obs;

  Future<void> setAlwaysOnTop(bool value) {
    isAlwaysOnTop.value = value;
    return windowManager.setAlwaysOnTop(value);
  }

  late final enableTapDm = false;

  // ===== 字幕 =====
  late double subtitleFontScale = PlayerPref.subtitleFontScale;
  late double subtitleFontScaleFS = PlayerPref.subtitleFontScaleFS;
  late int subtitlePaddingH = PlayerPref.subtitlePaddingH;
  late int subtitlePaddingB = PlayerPref.subtitlePaddingB;
  late double subtitleBgOpacity = PlayerPref.subtitleBgOpacity;
  late double subtitleStrokeWidth = PlayerPref.subtitleStrokeWidth;
  late int subtitleFontWeight = PlayerPref.subtitleFontWeight;

  late final Rx<SubtitleViewConfiguration> subtitleConfig = getSubConfig.obs;

  SubtitleViewConfiguration get getSubConfig {
    final subTitleStyle = this.subTitleStyle;
    return SubtitleViewConfiguration(
      style: subTitleStyle,
      padding: EdgeInsets.only(
        left: subtitlePaddingH.toDouble(),
        right: subtitlePaddingH.toDouble(),
        bottom: subtitlePaddingB.toDouble(),
      ),
    );
  }

  TextStyle get subTitleStyle => TextStyle(
    height: 1.5,
    fontSize: 30 * (isFullScreen.value ? subtitleFontScaleFS : subtitleFontScale),
    letterSpacing: 0.1,
    wordSpacing: 0.1,
    color: Colors.white,
    fontWeight: FontWeight.values[subtitleFontWeight],
    backgroundColor: subtitleBgOpacity == 0
        ? null
        : Colors.black.withValues(alpha: subtitleBgOpacity),
  );

  @override
  void updateSubtitleStyle() {
    subtitleConfig.value = getSubConfig;
  }

  void onUpdatePadding(EdgeInsets padding) {
    subtitlePaddingB = padding.bottom.round().clamp(0, 200);
    putSubtitleSettings();
  }

  // ===== 配置 =====
  late List<double> speedList = PlayerPref.speedList;
  late bool enableAutoLongPressSpeed = PlayerPref.enableAutoLongPressSpeed;
  late final showControlDuration = PlayerPref.enableLongShowControl
      ? const Duration(seconds: 30)
      : const Duration(seconds: 3);

  late final showFSActionItem = PlayerPref.showFSActionItem;
  late final enableShrinkVideoSize = PlayerPref.enableShrinkVideoSize;
  late final darkVideoPage = PlayerPref.darkVideoPage;
  late final enableSlideVolumeBrightness = PlayerPref.enableSlideVolumeBrightness;
  late final enableSlideFS = PlayerPref.enableSlideFS;
  late final enableDragSubtitle = PlayerPref.enableDragSubtitle;
  late final fastForBackwardDuration = Duration(
    seconds: PlayerPref.fastForBackwardDuration,
  );

  late final preInitPlayer = PlayerPref.preInitPlayer;
  late final showSeekPreview = PlayerPref.showSeekPreview;
  late final showFsScreenshotBtn = PlayerPref.showFsScreenshotBtn;
  late final showFsLockBtn = PlayerPref.showFsLockBtn;
  late final keyboardControl = PlayerPref.keyboardControl;
  late final uiScale = PlayerPref.uiScale;

  late final bool autoEnterFullScreen = PlayerPref.autoEnterFullScreen;
  late final bool autoExitFullscreen = PlayerPref.autoExitFullscreen;
  late final bool autoPlayEnable = PlayerPref.autoPlayEnable;
  late final bool enableVerticalExpand = PlayerPref.enableVerticalExpand;
  late final bool pipNoDanmaku = PlayerPref.pipNoDanmaku;
  late final bool tempPlayerConf = PlayerPref.tempPlayerConf;

  late final bool enableHeart = false;
  late final String? hwdec = PlayerPref.enableHA ? PlayerPref.hardwareDecoding : null;

  final RxInt progressType = PlayerPref.btmProgressBehavior.obs;
  late final bool enableQuickDouble = PlayerPref.enableQuickDouble;
  late final bool fullScreenGestureReverse = PlayerPref.fullScreenGestureReverse;

  late final bool isRelative = PlayerPref.useRelativeSlide;
  late final num offset = isRelative
      ? PlayerPref.sliderDuration / 100
      : PlayerPref.sliderDuration * 1000;

  num get sliderScale =>
      isRelative ? duration.value.inMilliseconds * offset : offset;

  late PlayRepeat playRepeat = PlayRepeat.values[PlayerPref.playRepeat];

  bool _processing = false;
  bool get processing => _processing;

  // ---- 音量指示器 ----
  final RxBool volumeIndicator = false.obs;
  Timer? volumeTimer;
  bool volumeInterceptEventStream = false;
  double get maxVolume => PlatformUtils.isDesktop ? PlayerPref.maxVolume : 1.0;

  // ---- 手势相关 ----
  bool? cancelSeek;
  bool? hasToast;

  // ---- 长按定时器 ----
  Timer? _longPressTimer;

  // ---- 其它 ----
  bool _isCloseAll = false;
  bool get isCloseAll => _isCloseAll;

  // ---- 方向监听 ----
  DeviceOrientation? _orientation;
  late final checkIsAutoRotate = Platform.isAndroid && mode != FullScreenMode.gravity;
  StreamSubscription<OrientationParams>? _orientationListener;
  bool visible = true;
  double screenRatio = 0.0;
  bool isManualFS = true;
  late final FullScreenMode mode = FullScreenMode.values[PlayerPref.fullScreenMode];
  late final horizontalScreen = PlayerPref.horizontalScreen;
  late final removeSafeArea = PlayerPref.removeSafeArea;

  // ---- 弹窗 ----
  final RxBool mountSeekBackwardButton = false.obs;
  final RxBool mountSeekForwardButton = false.obs;
  bool tripling = false;
  bool _fsProcessing = false;
  var _prefFit = VideoFitType.values[PlayerPref.cacheVideoFit];

  // ============================================================
  // 2. 构造函数 & init()
  // ============================================================
  MediaKitEngine();

  @override
  Future<void> init() async {
    _isDisposed = false;
    initBatteryListener();
    if (PlatformUtils.isMobile) {
      _orientationListener = NativeDeviceOrientationPlatform.instance
          .onOrientationChanged(
            checkIsAutoRotate: checkIsAutoRotate,
            angleDegrees: Platform.isAndroid ? PlayerPref.angleDegrees : null,
          )
          .listen(_onOrientationChanged);
    }
  }

  // ============================================================
  // 3. 原有私有方法
  // ============================================================
  void _stopOrientationListener() {
    _orientationListener?.cancel();
    _orientationListener = null;
  }

  void _onOrientationChanged(OrientationParams param) {
    // TODO: 暂不支持方向切换
    return;
  }

  Future<Player> _initPlayer() async {
    assert(_videoPlayerController == null);

    final player = Player(
      configuration: PlayerConfiguration(
        // logLevel: kDebugMode ? MPVLogLevel.warn : MPVLogLevel.error,
        logLevel: kDebugMode ? MPVLogLevel.error : MPVLogLevel.error,
        libass: false,
      ),
    );

    if (PlatformUtils.isMobile) {
      await player.setVolume(PlayerPref.playerVolume.toDouble());
    } else {
      await player.setVolume(volume.value * 100);
    }

    _videoController = VideoController(player as dynamic);
    _startListeners(player);
    return player;
  }

  Map<String, String>? _buffer;
  Map<String, String> get buffer => _buffer ??= _initBuffer();

  Map<String, String> _initBuffer() {
    final bufSec = PlayerPref.bufferSec * _playbackSpeed.value;
    final bufSiz = (PlayerPref.bufferSize * 0x100000).toStringAsFixed(0);
    return {
      'cache': 'yes',
      'cache-secs': bufSec.toStringAsFixed(3),
      'demuxer-hysteresis-secs': (bufSec / 1.5).toStringAsFixed(3),
      'demuxer-max-bytes': bufSiz,
      'demuxer-max-back-bytes': bufSiz,
    };
  }

  Future<void> _createVideoController(
    DataSource dataSource,
    Duration? seekTo,
  ) async {
    // 如果已经销毁，直接返回
    if (_isDisposed) return;

    isBuffering.value = false;
    buffered.value = Duration.zero;
    position = Duration.zero;
    danmakuController?.clear();

    var player = _videoPlayerController;

    if (player == null) {
      player = await _initPlayer();
      if (_isDisposed) {
        _removeListeners();
        player.dispose();
        player = null;
        _videoController = null;
        return;
      }
      _videoPlayerController = player;
    }

    final Map<String, String> extras = {};

    if (dataSource is FileSource) {
      extras['cache'] = 'no';
    } else {
      extras.addAll(buffer);
    }

    extras['video-sync'] = PlayerPref.videoSync;
    if (Platform.isAndroid) {
      extras['ao'] = PlayerPref.audioOutput;
    }
    final autosync = PlayerPref.autosync;
    if (autosync != '0') {
      extras['autosync'] = autosync;
    }
    if (hwdec != null) {
      extras['hwdec'] = hwdec!;
    }

    final Map<String, String> httpHeaders = Map.from(dataSource.headers ?? {});
    if (httpHeaders.isNotEmpty) {
      _cachedHeaders = Map.from(httpHeaders);
    }

    debugPrint('[media_kit] httpHeaders: $httpHeaders');
    debugPrint('[media_kit] videoSource: ${dataSource.videoSource}');

    await player.open(
      Media(
        dataSource.videoSource,
        start: seekTo,
        extras: extras,
        httpHeaders: httpHeaders,
      ),
      play: false,
    );
  }

  Map<String, String>? _cachedHeaders;

  void _initVideoFit() {
    if (_prefFit == VideoFitType.fill && _isVertical) {
      videoFit.value = VideoFitType.contain;
    } else {
      videoFit.value = _prefFit;
    }
  }

  void _setFullScreen(bool val) {
    isFullScreen.value = val;
    updateSubtitleStyle();
  }

  bool get _isCompleted =>
      videoPlayerController!.state.completed ||
      (duration.value - position).inMilliseconds <= 50;

  void _cancelSubForSeek() {
    if (_subForSeek != null) {
      _subForSeek!.cancel();
      _subForSeek = null;
    }
  }

  void _removeListeners() {
    _subscriptions?.forEach((e) => e.cancel());
    _subscriptions?.clear();
    _subscriptions = null;
  }

  void _updateTracks() {
    final player = _videoPlayerController;
    if (player == null) return;

    final newAudio = player.state.tracks.audio;
    final newVideo = player.state.tracks.video;
    final newSubtitle = player.state.tracks.subtitle
        .where((track) => _isValidSubtitleTrack(track))
        .toList();

    if (!_listEquals(availableAudioTracks, newAudio)) {
      availableAudioTracks.assignAll(newAudio);
    }
    if (!_listEquals(availableVideoTracks, newVideo)) {
      availableVideoTracks.assignAll(newVideo);
    }
    if (!_listEquals(availableSubtitleTracks, newSubtitle)) {
      availableSubtitleTracks.assignAll(newSubtitle);
    }

    currentAudioTrack.value = player.state.track.audio;
    currentVideoTrack.value = player.state.track.video;
    currentSubtitleTrack.value = player.state.track.subtitle;
  }

  void _updateVideoSize() {
    final state = _videoPlayerController?.state;
    if (state != null) {
      final w = state.width ?? 0;
      final h = state.height ?? 0;
      // 更新原有字段（兼容旧逻辑）
      _width = w;
      _height = h;
      // 更新响应式变量
      _videoWidth.value = w;
      _videoHeight.value = h;
    }
  }

  /// 启动网速监控（每秒估算一次）
  void _startSpeedMonitor() {
    _stopSpeedMonitor();
    _lastBuffered = buffered.value;
    _lastSpeedTime = DateTime.now();
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final deltaSec = now.difference(_lastSpeedTime).inSeconds;
      if (deltaSec > 0) {
        // 计算 buffer 增量（毫秒），粗略估算为字节数
        final deltaBytes = (buffered.value.inMilliseconds - _lastBuffered.inMilliseconds) * 1024 ~/ 8;
        _downloadSpeed.value = deltaBytes / deltaSec;
      }
      _lastBuffered = buffered.value;
      _lastSpeedTime = now;
    });
  }

  void _stopSpeedMonitor() {
    _speedTimer?.cancel();
    _speedTimer = null;
  }

  bool _isValidSubtitleTrack(SubtitleTrack track) {
    final id = track.id;
    if (id == null || id == '') return false;
    if (track.codec == 'unknown') return false;
    final title = track.title?.toLowerCase() ?? '';
    if (title.contains('hardcoded') || title.contains('burned')) return false;
    if (title.trim().isEmpty) return false;
    if (RegExp(r'^\d+$').hasMatch(title.trim())) return false;
    return true;
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void>? resetScreenRotation() {
    if (horizontalScreen) {
      return fullMode();
    } else {
      return portraitUpMode();
    }
  }

  Future<void>? changeOrientation({
    required bool isVertical,
    DeviceOrientation? orientation,
  }) {
    if (orientation == null && (mode == FullScreenMode.none || mode == FullScreenMode.gravity)) {
      return null;
    }
    if (orientation == null &&
        (mode == FullScreenMode.vertical ||
            (mode == FullScreenMode.auto && isVertical) ||
            (mode == FullScreenMode.ratio && (isVertical || screenRatio < kScreenRatio)))) {
      return portraitUpMode();
    } else {
      if (Platform.isAndroid) {
        if ((orientation ?? _orientation) == DeviceOrientation.landscapeRight) {
          return landscapeRightMode();
        } else {
          return landscapeLeftMode();
        }
      } else {
        if (orientation == DeviceOrientation.landscapeLeft) {
          return landscapeLeftMode();
        } else {
          return landscapeRightMode();
        }
      }
    }
  }

  void _startListeners(Player player) {
    assert(_subscriptions == null);
    final stream = player.stream;
    _subscriptions = [
      stream.playing.listen((event) {
        WakelockPlus.toggle(enable: event);
        if (event) {
          playerStatus.value = PlayerStatus.playing;
        } else {
          playerStatus.value = PlayerStatus.paused;
        }
        for (final element in _statusListeners) {
          element(event ? PlayerStatus.playing : PlayerStatus.paused);
        }
      }),
      stream.completed.listen((event) {
        if (event) {
          playerStatus.value = PlayerStatus.completed;
          for (final element in _statusListeners) {
            element(PlayerStatus.completed);
          }
          if (PlayerPref.autoExitFullscreen && isFullScreen.value) {
            triggerFullScreen(status: false);
          }
        }
      }),
      stream.position.listen((event) {
        position = event;
        updatePositionSecond();
        if (!isSliderMoving.value) {
          sliderPosition = event;
          updateSliderPositionSecond();
        }
        for (final element in _positionListeners) {
          element(event);
        }
        final endSkip = skipEndDuration.value;
        if (endSkip > 0) {
          final total = duration.value.inSeconds;
          if (total > 0 && event.inSeconds >= total - endSkip) {
            if (playerStatus.isPlaying) {
              pause();
              SmartDialog.showToast('已跳过片尾');
            }
          }
        }

        if (_videoWidth.value == 0 || _videoHeight.value == 0) {
          _updateVideoSize();
        }
      }),
      stream.duration.listen((Duration event) {
        duration.value = event;
      }),
      stream.buffer.listen((Duration event) {
        buffered.value = event;
        updateBufferedSecond();
      }),
      stream.buffering.listen((bool event) {
        isBuffering.value = event;
      }),
      if (kDebugMode)
        stream.log.listen(((PlayerLog log) {
          if (log.level == 'error' || log.level == 'fatal') {
            debugPrint('${log.level}: ${log.prefix}: ${log.text}');
          } else {
            debugPrint(log.toString());
          }
        })),
      stream.error.listen((String event) {
        if (dataSource is FileSource &&
            event.startsWith("Failed to open file")) {
          return;
        }
        if (event.startsWith("Failed to open https://") ||
            event.startsWith("Can not open external file https://") ||
            event.startsWith('tcp: ffurl_read returned ')) {
          EasyThrottle.throttle(
            'controllerStream.error.listen',
            const Duration(milliseconds: 10000),
            () {
              Future.delayed(const Duration(milliseconds: 3000), () {
                if (isBuffering.value && buffered.value == Duration.zero) {
                  SmartDialog.showToast(
                    '视频链接打开失败，重试中',
                    displayTime: const Duration(milliseconds: 500),
                  );
                  refreshPlayer();
                }
              });
            },
          );
        } else if (event.startsWith('Could not open codec')) {
          SmartDialog.showToast('无法加载解码器, $event，可能会切换至软解');
        } else if (event.startsWith("error running") ||
            event.startsWith("Failed to open .") ||
            event.startsWith("Cannot open") ||
            event.startsWith("Can not open")) {
          return;
        } else {
          debugPrint('Player error: $event');
        }
      }),
      stream.tracks.listen((_) {
        _updateTracks();
      }),
    ];
  }

  // ============================================================
  // 4. 公开方法实现
  // ============================================================

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
    // 如果已销毁，重新初始化
    if (_isDisposed) {
      await init();
    }

    try {
      _processing = true;
      this._width = width;
      this._height = height;
      this.dataSource = dataSource;
      _autoPlay = autoplay;
      _vodId = vodId;

      dataStatus.value = DataStatus.loading;
      _isVertical = isVertical ?? false;

      cancelLongPressTimer();
      if (_videoPlayerController != null &&
          _videoPlayerController!.state.playing) {
        await pause(notify: false);
      }

      await _createVideoController(dataSource, seekTo);

      if (_isDisposed) {
        _removeListeners();
        _videoPlayerController?.dispose();
        _videoPlayerController = null;
        _videoController = null;
        return;
      }

      this.duration.value = duration ?? _videoPlayerController!.state.duration ?? Duration.zero;
      position = buffered.value = sliderPosition = seekTo ?? Duration.zero;
      updatePositionSecond();
      updateSliderPositionSecond();
      updateBufferedSecond();

      dataStatus.value = DataStatus.loaded;

      _updateVideoSize();
      _startSpeedMonitor();

      if (autoFullScreenFlag && autoEnterFullScreen) {
        triggerFullScreen(status: true);
      }

      await _initializePlayer();
      onInit?.call();
    } catch (err, stackTrace) {
      dataStatus.value = DataStatus.error;
      if (kDebugMode) {
        debugPrint(stackTrace.toString());
        debugPrint('plPlayer err:  $err');
      }
    } finally {
      _processing = false;
    }
  }

  @override
  Future<void> refreshPlayer() async {
    if (dataSource is FileSource) return;

    final player = _videoPlayerController;
    if (player == null) return;

    SmartDialog.dismiss(force: true);

    dataStatus.value = DataStatus.loading;
    isBuffering.value = true;
    buffered.value = Duration.zero;

    try {
      final Map<String, String> extras = {};
      if (dataSource is FileSource) {
        extras['cache'] = 'no';
      } else {
        extras.addAll(buffer);
      }
      extras['video-sync'] = PlayerPref.videoSync;
      if (Platform.isAndroid) {
        extras['ao'] = PlayerPref.audioOutput;
      }
      final autosync = PlayerPref.autosync;
      if (autosync != '0') {
        extras['autosync'] = autosync;
      }
      if (hwdec != null) {
        extras['hwdec'] = hwdec!;
      }

      Map<String, String> httpHeaders;
      if (_cachedHeaders != null && _cachedHeaders!.isNotEmpty) {
        httpHeaders = Map.from(_cachedHeaders!);
        debugPrint('[media_kit] refreshPlayer 使用缓存的 headers: $httpHeaders');
      } else {
        httpHeaders = Map.from(dataSource.headers ?? {});
        debugPrint('[media_kit] refreshPlayer 使用 dataSource.headers: $httpHeaders');
      }

      await player.open(
        Media(
          dataSource.videoSource,
          start: position,
          extras: extras,
          httpHeaders: httpHeaders,
        ),
        play: true,
      );

      if (player.state.rate != _playbackSpeed.value) {
        await setPlaybackSpeed(_playbackSpeed.value);
      }

      dataStatus.value = DataStatus.loaded;
      isBuffering.value = false;

      if (_autoPlay) {
        play();
      }
    } catch (e) {
      dataStatus.value = DataStatus.error;
      isBuffering.value = false;
      if (kDebugMode) debugPrint('refreshPlayer error: $e');
    }
  }

  Future<void> _initializePlayer() async {
    if (_videoPlayerController?.state.rate != _playbackSpeed.value) {
      await setPlaybackSpeed(_playbackSpeed.value);
    }
    _initVideoFit();

    if (_autoPlay) {
      play();
    }
  }

  @override
  Future<void> play({bool repeat = false, bool hideControls = true}) async {
    controls = !hideControls;
    if (repeat) {
      await seekTo(Duration.zero, isSeek: false);
    }
    await _videoPlayerController?.play();
    playerStatus.value = PlayerStatus.playing;
  }

  @override
  Future<void> pause({bool notify = true, bool isInterrupt = false}) async {
    await _videoPlayerController?.pause();
    playerStatus.value = PlayerStatus.paused;
  }

  @override
  Future<void> seekTo(Duration position, {bool isSeek = true}) async {
    if (position < Duration.zero) {
      position = Duration.zero;
    }
    this.position = position;
    updatePositionSecond();

    Future<void> seek() async {
      if (isSeek) {
        await _videoPlayerController?.stream.buffer.first;
      }
      danmakuController?.clear();
      try {
        await _videoPlayerController?.seek(position);
      } catch (e) {
        if (kDebugMode) debugPrint('seek failed: $e');
      }
    }

    if (duration.value != Duration.zero) {
      seek();
    } else {
      _subForSeek?.cancel();
      _subForSeek = duration.listen((_) {
        seek();
        _cancelSubForSeek();
      });
    }
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    lastPlaybackSpeed = playbackSpeed;
    if (speed == _videoPlayerController?.state.rate) {
      return;
    }
    await _videoPlayerController?.setRate(speed);
    _playbackSpeed.value = speed;
  }

  double playSpeedDefault = PlayerPref.playSpeedDefault;
  @override
  Future<void> setDefaultSpeed() async {
    await _videoPlayerController?.setRate(playSpeedDefault);
    _playbackSpeed.value = playSpeedDefault;
  }

  @override
  void setLongPressStatus(bool val) async {
    if (controlsLock.value) {
      return;
    }
    if (longPressStatus.value == val) {
      return;
    }
    if (val) {
      if (playerStatus.isPlaying) {
        longPressStatus.value = val;
        HapticFeedback.lightImpact();
        await setPlaybackSpeed(
          enableAutoLongPressSpeed ? playbackSpeed * 2 : longPressSpeed,
        );
      }
    } else {
      longPressStatus.value = val;
      await setPlaybackSpeed(lastPlaybackSpeed);
    }
  }

  @override
  Future<void> setVolume(double volume, {bool showIndicator = true}) async {
    if (this.volume.value != volume) {
      this.volume.value = volume;
      try {
        if (PlatformUtils.isDesktop) {
          await _videoPlayerController!.setVolume(volume * 100);
        } else {
          FlutterVolumeController.updateShowSystemUI(false);
          await FlutterVolumeController.setVolume(volume);
        }
      } catch (err) {
        if (kDebugMode) debugPrint(err.toString());
      }
    }
    if (showIndicator) {
      volumeIndicator.value = true;
    }
    volumeInterceptEventStream = true;
    volumeTimer?.cancel();
    volumeTimer = Timer(const Duration(milliseconds: 200), () {
      volumeIndicator.value = false;
      volumeInterceptEventStream = false;
      if (PlatformUtils.isDesktop) {
        setting.put(SettingBoxKey.desktopVolume, volume.toPrecision(3));
      }
    });
  }

  @override
  Future<void> triggerFullScreen({
    bool status = true,
    bool inAppFullScreen = false,
    DeviceOrientation? orientation,
    bool isManualFS = true,
  }) async {
    if (isFullScreen.value == status) return;
    if (_fsProcessing) return;
    _fsProcessing = true;
    this.isManualFS = isManualFS;
    try {
      if (status) {
        if (PlatformUtils.isMobile) {
          hideSystemBar(); // 先隐藏系统栏
          await changeOrientation(
            isVertical: isVertical,
            orientation: orientation,
          );
        } else {
          await enterDesktopFullScreen(inAppFullScreen: inAppFullScreen);
        }
      } else {
        if (PlatformUtils.isMobile) {
          if (!removeSafeArea) {
            showSystemBar();
          }
          if (orientation == null && mode == FullScreenMode.none) {
            return;
          }
          await resetScreenRotation();
        } else {
          await exitDesktopFullScreen();
        }
      }
    } finally {
      _setFullScreen(status);
      _fsProcessing = false;
    }
  }

  @override
  Future<void> setOrientation(List<DeviceOrientation> orientations) async {
    if (!PlatformUtils.isMobile) return;
    await SystemChrome.setPreferredOrientations(orientations);
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    final player = _videoPlayerController;
    if (player == null) return;
    await player.setAudioTrack(track);
    currentAudioTrack.value = track;
    _updateTracks();
  }

  @override
  Future<void> setVideoTrack(VideoTrack track) async {
    final player = _videoPlayerController;
    if (player == null) return;
    await player.setVideoTrack(track);
    currentVideoTrack.value = track;
    _updateTracks();
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    final player = _videoPlayerController;
    if (player == null) return;
    await player.setSubtitleTrack(track);
    currentSubtitleTrack.value = track;
    _updateTracks();
  }

  @override
  void putSubtitleSettings() {
    setting.putAllNE({
      SettingBoxKey.subtitleFontScale: subtitleFontScale,
      SettingBoxKey.subtitleFontScaleFS: subtitleFontScaleFS,
      SettingBoxKey.subtitlePaddingH: subtitlePaddingH,
      SettingBoxKey.subtitlePaddingB: subtitlePaddingB,
      SettingBoxKey.subtitleBgOpacity: subtitleBgOpacity,
      SettingBoxKey.subtitleStrokeWidth: subtitleStrokeWidth,
      SettingBoxKey.subtitleFontWeight: subtitleFontWeight,
    });
  }

  @override
  void toggleDanmaku() {
    enableShowDanmaku.value = !enableShowDanmaku.value;
    if (!tempPlayerConf) {
      PlayerPref.enableShowDanmaku = enableShowDanmaku.value;
    }
  }

  @override
  void refreshDanmakuConfig() {
    // 如果弹幕控制器存在，刷新其配置
  }

  @override
  void setPlayRepeat(PlayRepeat type) {
    playRepeat = type;
    if (!tempPlayerConf) video.put(VideoBoxKey.playRepeat, type.index);
  }

  @override
  Future<void> takeScreenshot() async {
    SmartDialog.showToast('截图中');
    final imageBytes = await videoPlayerController?.screenshot();
    if (imageBytes != null) {
      SmartDialog.showToast('点击弹窗保存截图');
      showDialog(
        context: Get.context!,
        builder: (context) => GestureDetector(
          onTap: () async {
            ImageUtils.saveByteImg(
              bytes: imageBytes,
              fileName: 'screenshot_${ImageUtils.time}',
            );
            Get.back();
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
    } else {
      SmartDialog.showToast('截图失败');
    }
  }

  @override
  Future<void> enterDesktopPip() async {
    if (isFullScreen.value) return;
    if (_isDesktopPip.value) return;

    _isDesktopPip.value = true;
    _lastWindowBounds = await windowManager.getBounds();

    if (showWindowTitleBar) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }

    final state = videoPlayerController!.state;
    int width = state.width ?? 0;
    int height = state.height ?? 0;
    if (width == 0) {
      width = this._width ?? 16;
    }
    if (height == 0) {
      height = this._height ?? 9;
    }
    final Size size;
    if (height > width) {
      size = Size(280.0, 280.0 * height / width);
    } else {
      size = Size(280.0 * width / height, 280.0);
    }

    await windowManager.setMinimumSize(size);
    await setAlwaysOnTop(true);
    await windowManager.setSize(size);
    await windowManager.setAspectRatio(width / height);
  }

  Future<void> exitDesktopPip() async {
    if (!_isDesktopPip.value) return;
    // 先恢复窗口（全部 await 完成）
    if (showWindowTitleBar) {
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    }
    await windowManager.setMinimumSize(const Size(400, 700));
    await windowManager.setBounds(_lastWindowBounds);
    await setAlwaysOnTop(false);
    await windowManager.setAspectRatio(0);
    _lastWindowBounds = Rect.zero;
    // 窗口恢复完成后，最后才标记退出 PiP
    _isDesktopPip.value = false;
  }

  @override
  void toggleDesktopPip() {
    if (_isDesktopPip.value) {
      exitDesktopPip();
    } else {
      enterDesktopPip();
    }
  }

  @override
  void toggleFlipX() {
    flipX.value = !flipX.value;
  }

  @override
  void toggleFlipY() {
    flipY.value = !flipY.value;
  }

  @override
  void setOnlyPlayAudio() {
    // 仅音频模式，暂空实现
  }

  @override
  void setContinuePlayInBackground() {
    continuePlayInBackground.value = !continuePlayInBackground.value;
    if (!tempPlayerConf) {
      setting.put(
        SettingBoxKey.continuePlayInBackground,
        continuePlayInBackground.value,
      );
    }
  }

  @override
  void onLockControl(bool val) {
    feedBack();
    controlsLock.value = val;
    if (!val && showControls.value) {
      showControls.refresh();
    }
    controls = !val;
  }

  @override
  void onDoubleTapCenter() async {
    if (_isCompleted) {
      await videoPlayerController!.seek(Duration.zero);
      videoPlayerController!.play();
    } else {
      videoPlayerController!.playOrPause();
    }
  }

  @override
  void onForward(Duration duration) {
    onForwardBackward(position + duration);
  }

  @override
  void onBackward(Duration duration) {
    onForwardBackward(position - duration);
  }

  @override
  void onForwardBackward(Duration duration) {
    seekTo(
      duration.clamp(Duration.zero, videoPlayerController!.state.duration ?? Duration.zero),
      isSeek: false,
    ).whenComplete(play);
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

  // ============================================================
  // 5. getter/setter 实现
  // ============================================================

  @override
  set controls(bool visible) {
    showControls.value = visible;
    _timer?.cancel();
    if (visible) {
      hideTaskControls();
    }
  }

  @override
  void hideTaskControls() {
    _timer?.cancel();
    _timer = Timer(showControlDuration, () {
      if (!isSliderMoving.value && !tripling) {
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
      if (playerStatus.isPlaying) {
        pause();
      }
      return;
    }

    if (controlsLock.value) {
      onLockControl(false);
      return;
    }
    if (isPipMode && PlatformUtils.isDesktop) {
      exitDesktopPip();
      return;
    }
    if (isFullScreen.value) {
      triggerFullScreen(status: false);
      return;
    }
    Get.back();
  }

  @override
  void onCloseAll() {
    _isCloseAll = true;
    dispose();
    // 返回首页并清除所有路由
    Get.offAllNamed('/');
  }

  @override
  Duration get positionValue => position;

  @override
  int? get width => _width;
  @override
  int? get height => _height;

  @override
  Timer? get longPressTimer => _longPressTimer;
  @override
  set longPressTimer(Timer? timer) => _longPressTimer = timer;

  @override
  bool get isMuted => _isMuted;
  @override
  set isMuted(bool value) => _isMuted = value;

  // ---- 功能标志 ----
  @override
  bool get supportsAudioTrack => true;
  @override
  bool get supportsVideoTrack => true;
  @override
  bool get supportsEmbeddedSubtitle => true;
  @override
  bool get supportsHardwareAcceleration => true;
  @override
  bool get supportsScreenshot => true;
  @override
  bool get supportsPictureInPicture => true;
  @override
  bool get supportsBufferProgress => true;

  // ============================================================
  // 6. 附加方法
  // ============================================================
  @override
  void toggleVideoFit(VideoFitType value) {
    _prefFit = videoFit.value = value;
    video.put(VideoBoxKey.cacheVideoFit, value.index);
  }

  @override
  void doubleTapFuc(DoubleTapType type) {
    if (!enableQuickDouble) {
      onDoubleTapCenter();
      return;
    }
    switch (type) {
      case DoubleTapType.left:
        onDoubleTapSeekBackward();
        break;
      case DoubleTapType.center:
        onDoubleTapCenter();
        break;
      case DoubleTapType.right:
        onDoubleTapSeekForward();
        break;
    }
  }

  // ---- 内部辅助 ----
  void onDoubleTapSeekBackward() {
    mountSeekBackwardButton.value = true;
  }

  void onDoubleTapSeekForward() {
    mountSeekForwardButton.value = true;
  }

  void setBackgroundPlay(bool val) {
    if (!tempPlayerConf) {
      setting.put(SettingBoxKey.enableBackgroundPlay, val);
    }
  }

  // ============================================================
  // 7. 监听器管理
  // ============================================================
  final Set<ValueChanged<Duration>> _positionListeners = {};
  final Set<ValueChanged<PlayerStatus>> _statusListeners = {};
  List<StreamSubscription>? _subscriptions;

  @override
  void addPositionListener(ValueChanged<Duration> listener) {
    _positionListeners.add(listener);
  }

  @override
  void removePositionListener(ValueChanged<Duration> listener) =>
      _positionListeners.remove(listener);

  @override
  void addStatusLister(ValueChanged<PlayerStatus> listener) {
    _statusListeners.add(listener);
  }

  @override
  void removeStatusLister(ValueChanged<PlayerStatus> listener) =>
      _statusListeners.remove(listener);

  // ============================================================
  // 8. 渲染
  // ============================================================
  @override
  Widget buildVideoWidget({
    required BoxFit fit,
    required bool flipX,
    required bool flipY,
  }) {
    final controller = videoController;
    if (controller == null) {
      return const ColoredBox(color: Colors.black);
    }
    // 直接返回 Video，不包裹 Obx，不依赖任何 Rx 变量
    return Transform.flip(
      flipX: flipX,
      flipY: flipY,
      child: Video(
        controller: controller,
        fit: fit,
        controls: (_) => const SizedBox.shrink(),
        subtitleViewConfiguration: const SubtitleViewConfiguration(
          style: TextStyle(
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            fontSize: 0.1,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 9. 跳过片头片尾
  // ============================================================
  @override
  Future<void> applySkipStart() async {
    final start = skipStartDuration.value;
    if (start <= 0) return;

    if (duration.value.inSeconds > 0) {
      final total = duration.value.inSeconds;
      if (total > start) {
        await seekTo(Duration(seconds: start), isSeek: false);
      }
      return;
    }

    final completer = Completer<void>();
    _durationSubscription?.cancel();
    _durationSubscription = duration.listen((dur) {
      if (dur.inSeconds > 0 && !completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future;

    _durationSubscription?.cancel();
    _durationSubscription = null;

    final total = duration.value.inSeconds;
    if (total > start) {
      await seekTo(Duration(seconds: start), isSeek: false);
    }
  }

  // ============================================================
  // 10. 销毁
  // ============================================================
  @override
  void dispose() {
    // 防止重复销毁
    if (_isDisposed) return;
    _isDisposed = true;

    resetScreenRotation();
    cancelLongPressTimer();
    _cancelSubForSeek();

    if (removeSafeArea) {
      showSystemBar();
    }
    danmakuController = null;
    _stopOrientationListener();

    _timer?.cancel();

    if (PlatformUtils.isDesktop && isAlwaysOnTop.value) {
      windowManager.setAlwaysOnTop(false);
    }

    if (_isDesktopPip.value) {
      exitDesktopPip();
    }

    _removeListeners();
    _positionListeners.clear();
    _statusListeners.clear();
    if (playerStatus.isPlaying) {
      WakelockPlus.disable();
    }
    if (kDebugMode) {
      debugPrint('dispose player');
    }
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _videoController = null;
    _cachedHeaders = null;

    _durationSubscriptionForSkip?.cancel();
    _durationSubscriptionForSkip = null;

    _stopSpeedMonitor();
  }
}