// lib/plugin/pl_player/engine/fvp_engine.dart
// 基于 libmdk 原生接口（fvp/mdk.dart）实现的播放器引擎
// 不依赖 video_player / video_player_platform_interface

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

class FvpEngine implements IPlayerEngine {
  // ============================================================
  // 底层：mdk.Player
  // ============================================================
  mdk.Player? _player;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isPlaying = false;
  bool _skipEndTriggered = false;
  bool _completionReported = false;

  // ============================================================
  // 状态（对外接口保持与 media_kit 引擎一致）
  // ============================================================
  final playerStatus = PlPlayerStatus(PlayerStatus.paused);
  final Rx<DataStatus> dataStatus = Rx(DataStatus.none);
  final Rx<Duration> duration = Rx(Duration.zero);
  final Rx<Duration> buffered = Rx(Duration.zero);
  final RxInt bufferedSeconds = 0.obs;
  final RxBool isBuffering = false.obs;

  Duration position = Duration.zero;
  final RxInt positionSeconds = 0.obs;
  Duration sliderPosition = Duration.zero;
  final RxInt sliderPositionSeconds = 0.obs;
  final Rx<Duration> sliderTempPosition = Rx(Duration.zero);

  // ============================================================
  // 属性
  // ============================================================
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

  final RxInt _rebuildCounter = 0.obs;

  // ============================================================
  // 高级特性
  // ============================================================
  final RxBool isLive = false.obs;
  final Rxn<dynamic> mediaInfo = Rxn<dynamic>();
  final Rxn<String> currentSubtitleText = Rxn<String>();
  String? _externalAudioUrl;
  final GlobalKey _screenshotKey = GlobalKey();

  // 音量 / 亮度
  final RxDouble volume = 1.0.obs;
  final RxDouble brightness = (-1.0).obs;
  final RxBool volumeIndicator = false.obs;
  bool volumeInterceptEventStream = false;
  Timer? volumeTimer;

  // 轨道
  final RxList<AudioTrack> availableAudioTracks = <AudioTrack>[].obs;
  final RxList<VideoTrack> availableVideoTracks = <VideoTrack>[].obs;
  final RxList<SubtitleTrack> availableSubtitleTracks = <SubtitleTrack>[].obs;
  final Rx<AudioTrack?> currentAudioTrack = Rx<AudioTrack?>(null);
  final Rx<VideoTrack?> currentVideoTrack = Rx<VideoTrack?>(null);
  final Rx<SubtitleTrack?> currentSubtitleTrack = Rx<SubtitleTrack?>(null);

  // 字幕样式（仅占位，libmdk 内部由 libass 渲染）
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
  late final bool showFsScreenshotBtn = PlayerPref.showFsScreenshotBtn;
  @override
  late final bool showFsLockBtn = PlayerPref.showFsLockBtn;
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
  StreamSubscription<BatteryState>? _batterySubscription;

  // 监听器
  final Set<ValueChanged<Duration>> _positionListeners = {};
  final Set<ValueChanged<PlayerStatus>> _statusListeners = {};

  // 定时器
  Timer? _positionTimer;
  Timer? _timer;
  Timer? _longPressTimer;

  // Stream 订阅
  StreamSubscription? _stateSubscription;
  StreamSubscription? _mediaStatusSubscription;
  StreamSubscription? _eventSubscription;

  // 手势
  @override
  final RxBool mountSeekBackwardButton = false.obs;
  @override
  final RxBool mountSeekForwardButton = false.obs;
  @override
  bool? cancelSeek;
  @override
  bool? hasToast;
  @override
  double lastPlaybackSpeed = 1.0;

  // 分辨率 / 网速
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
  // getter（IPlayerEngine）
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
    _player?.mute = value;
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
  // 构造 & 生命周期
  // ============================================================
  FvpEngine();

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

    _externalAudioUrl = null;

    _removeListeners();
    _positionTimer?.cancel();
    _positionTimer = null;
    _timer?.cancel();
    _timer = null;
    _longPressTimer?.cancel();
    _longPressTimer = null;

    final p = _player;
    _player = null;
    _isInitialized = false;
    try {
      // mdk.Player.dispose() 声明为 `void dispose() async`，
      // 内部会 await updateTexture(-1) 释放纹理。
      // 此处不同步 await，交给 Dart 事件循环。
      p?.dispose();
    } catch (e) {
      debugPrint('[FvpEngine] dispose error: $e');
    }
  }

  @override
  void onCloseAll() {
    _isCloseAll = true;
    dispose();
    Get.until((route) => route.isFirst);
  }

  // ============================================================
  // 核心：setDataSource
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
    if (_isDisposed) await init();

    _skipEndTriggered = false;
    _completionReported = false;
    _processing = true;
    _vodId = vodId;
    _width = width;
    _height = height;
    _playbackSpeed = speed;
    this.dataSource = dataSource;

    // 状态清理
    _externalAudioUrl = null;
    mediaInfo.value = null;
    currentSubtitleText.value = null;
    isLive.value = false;
    availableAudioTracks.clear();
    availableVideoTracks.clear();
    availableSubtitleTracks.clear();
    currentAudioTrack.value = null;
    currentVideoTrack.value = null;
    currentSubtitleTrack.value = null;

    await _disposePlayer();

    dataStatus.value = DataStatus.loading;
    isBuffering.value = true;

    try {
      // 1) 创建 player
      final player = mdk.Player();
      _player = player;

      // 2) 基础属性
      player.volume = _volume;
      player.playbackRate = _playbackSpeed;
      player.mute = _isMuted;
      player.loop = _isLooping ? -1 : 0;

      // 3) buffer range
      try {
        player.setBufferRange(
          min: PlayerPref.mdkBufferMin,
          max: PlayerPref.mdkBufferMax,
        );
      } catch (e) {
        debugPrint('[FvpEngine] setBufferRange failed: $e');
      }

      // 4) HTTP headers
      final headers = dataSource.headers ?? const <String, String>{};
      if (headers.isNotEmpty) {
        final sb = StringBuffer();
        headers.forEach((k, v) => sb.write('$k: $v\r\n'));
        player.setProperty('avio.headers', sb.toString());
      }

      // 5) 设置媒体
      String mediaUrl = dataSource.videoSource;
      if (dataSource is FileSource) {
        // 本地文件：libmdk 支持绝对路径，也支持 file:// 前缀
        // 若传进来的已经带 scheme 就原样使用
        final uri = Uri.tryParse(mediaUrl);
        if (uri == null || !uri.hasScheme) {
          mediaUrl = Uri.file(mediaUrl).toString();
        }
      }
      player.media = mediaUrl;

      // 6) prepare
      final prepareResult =
          await player.prepare(position: seekTo?.inMilliseconds ?? 0);
      debugPrint('[FvpEngine] prepare result=$prepareResult');
      if (prepareResult < 0) {
        throw Exception('prepare failed: $prepareResult');
      }

      _isInitialized = true;
      _rebuildCounter.value++;

      // 7) 刷新媒体信息与轨道
      _refreshMediaInfo();

      // 8) 创建纹理
      final texId = await player.updateTexture(width: _width, height: _height);
      debugPrint('[FvpEngine] textureId=$texId');

      if (texId < 0) {
        _width = 0;
        _height = 0;
      } else {
        // 纹理创建后，用 mediaInfo 的真实尺寸刷新宽高
        _updateVideoSizeFromInfo();
        _width = _videoWidth.value > 0 ? _videoWidth.value : _width;
        _height = _videoHeight.value > 0 ? _videoHeight.value : _height;
      }

      // 9) 位置
      position = Duration(milliseconds: prepareResult);
      updatePositionSecond();
      sliderPosition = position;
      updateSliderPositionSecond();

      // 10) 注册监听
      _addListeners();

      dataStatus.value = DataStatus.loaded;
      isBuffering.value = false;

      // 11) 播放 / 暂停
      if (autoplay) {
        await play();
      } else {
        playerStatus.value = PlayerStatus.paused;
      }

      onInit?.call();

      if (autoFullScreenFlag && autoEnterFullScreen) {
        triggerFullScreen(status: true);
      }
    } catch (e, stack) {
      debugPrint('[FvpEngine] setDataSource error: $e\n$stack');
      dataStatus.value = DataStatus.error;
      isBuffering.value = false;
      final p = _player;
      _player = null;
      _isInitialized = false;
      try {
        p?.dispose();
      } catch (_) {}
    } finally {
      _processing = false;
    }
  }

  Future<void> _disposePlayer() async {
    _removeListeners();
    _positionTimer?.cancel();
    _positionTimer = null;
    _isInitialized = false;

    final old = _player;
    if (old != null) {
      try {
        old.dispose();
      } catch (e) {
        debugPrint('[FvpEngine] _disposePlayer error: $e');
      }
      // dispose 内部有 await，等待一小段时间让纹理释放完成
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (identical(_player, old)) _player = null;
    }
  }

  // ============================================================
  // 监听注册
  // ============================================================
  void _addListeners() {
    final p = _player;
    if (p == null) return;
    _removeListeners();

    _stateSubscription = p.onStateChanged.listen(_onStateChanged);
    _mediaStatusSubscription = p.onMediaStatus.listen(_onMediaStatus);
    _eventSubscription = p.onEvent.listen(_onEvent);

    try {
      p.onSubtitleText((start, end, texts) {
        currentSubtitleText.value = texts.join('\n');
      });
    } catch (e) {
      debugPrint('[FvpEngine] onSubtitleText register failed: $e');
    }
  }

  void _removeListeners() {
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _mediaStatusSubscription?.cancel();
    _mediaStatusSubscription = null;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      _player?.onSubtitleText(null);
    } catch (_) {}
  }

  // ============================================================
  // 事件处理
  // ============================================================
  void _onStateChanged(
      ({mdk.PlaybackState oldValue, mdk.PlaybackState newValue}) e) {
    if (_isDisposed) return;
    final newState = e.newValue;
    debugPrint('[FvpEngine] state: ${e.oldValue} -> $newState');

    switch (newState) {
      case mdk.PlaybackState.playing:
        if (!_isPlaying) {
          _isPlaying = true;
          playerStatus.value = PlayerStatus.playing;
          _startPositionTimer();
          _notifyStatusListeners(PlayerStatus.playing);
        }
        break;
      case mdk.PlaybackState.paused:
        if (_isPlaying) {
          _isPlaying = false;
          playerStatus.value = PlayerStatus.paused;
          _stopPositionTimer();
          _notifyStatusListeners(PlayerStatus.paused);
        } else if (playerStatus.value != PlayerStatus.completed) {
          playerStatus.value = PlayerStatus.paused;
        }
        break;
      case mdk.PlaybackState.stopped:
        _isPlaying = false;
        _stopPositionTimer();
        _reportCompleted();
        break;
      default:
        // notRunning / running 在本插件里不会出现（PlaybackState.from 只返回 3 种）
        break;
    }
  }

  void _onMediaStatus(
      ({mdk.MediaStatus oldValue, mdk.MediaStatus newValue}) e) {
    if (_isDisposed) return;
    final oldStatus = e.oldValue;
    final newStatus = e.newValue;

    // buffering 状态切换
    if (!oldStatus.test(mdk.MediaStatus.buffering) &&
        newStatus.test(mdk.MediaStatus.buffering)) {
      isBuffering.value = true;
    } else if (!oldStatus.test(mdk.MediaStatus.buffered) &&
        newStatus.test(mdk.MediaStatus.buffered)) {
      isBuffering.value = false;
    }

    // 首次 loaded → 刷新
    if (!oldStatus.test(mdk.MediaStatus.loaded) &&
        newStatus.test(mdk.MediaStatus.loaded)) {
      _refreshMediaInfo();
    }

    // 播放完成标志
    if (newStatus.test(mdk.MediaStatus.end)) {
      _reportCompleted();
    }
  }

  void _onEvent(mdk.MediaEvent event) {
    if (_isDisposed) return;
    if (event.error < 0) {
      debugPrint(
          '[FvpEngine] event error: ${event.category}/${event.detail} (${event.error})');
    }
  }

  void _notifyStatusListeners(PlayerStatus s) {
    for (final l in _statusListeners.toList()) {
      try {
        l(s);
      } catch (e) {
        debugPrint('[FvpEngine] status listener error: $e');
      }
    }
  }

  void _reportCompleted() {
    if (_completionReported) return;
    _completionReported = true;
    playerStatus.value = PlayerStatus.completed;
    _notifyStatusListeners(PlayerStatus.completed);
    if (autoExitFullscreen && isFullScreen.value) {
      triggerFullScreen(status: false);
    }
  }

  // ============================================================
  // Position 轮询
  // ============================================================
  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _pollPosition(),
    );
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _pollPosition() {
    final p = _player;
    if (p == null || _isDisposed || !_isInitialized) return;

    try {
      // player.position 是 int（毫秒）
      final newPos = Duration(milliseconds: p.position);
      if (newPos != position) {
        position = newPos;
        updatePositionSecond();
        if (!isSliderMoving.value) {
          sliderPosition = newPos;
          updateSliderPositionSecond();
        }
        for (final l in _positionListeners.toList()) {
          try {
            l(newPos);
          } catch (_) {}
        }
        _checkSkipEnd();
      }

      // player.buffered() 是 int（毫秒）
      final newBuf = Duration(milliseconds: p.buffered());
      if (buffered.value != newBuf) {
        buffered.value = newBuf;
        updateBufferedSecond();
      }
    } catch (e) {
      debugPrint('[FvpEngine] pollPosition error: $e');
    }
  }

  void _checkSkipEnd() {
    final endSkip = skipEndDuration.value;
    if (endSkip <= 0 || _skipEndTriggered) return;
    final total = duration.value.inSeconds;
    if (total <= 0) return;
    if (position.inSeconds >= total - endSkip) {
      if (playerStatus.value.isPlaying) {
        _skipEndTriggered = true;
        final nearEnd =
            Duration(seconds: total) - const Duration(milliseconds: 500);
        if (position < nearEnd) {
          seekTo(nearEnd, isSeek: false);
          SmartDialog.showToast('已跳过片尾');
        }
      }
    }
  }

  // ============================================================
  // 媒体信息 & 轨道
  // ============================================================
  void _refreshMediaInfo() {
    final p = _player;
    if (p == null) return;
    try {
      // mediaInfo 是同步 getter，每次访问会做一次 FFI 调用
      final info = p.mediaInfo;
      mediaInfo.value = info;
      isLive.value = p.isLive;

      if (info.duration > 0) {
        duration.value = Duration(milliseconds: info.duration);
      }

      _updateVideoSizeFromInfo();
      _updateTracks();
    } catch (e) {
      debugPrint('[FvpEngine] _refreshMediaInfo error: $e');
    }
  }

  void _updateVideoSizeFromInfo() {
    final info = mediaInfo.value;
    if (info == null) return;
    try {
      // info 是 mdk.MediaInfo；video 是 List<VideoStreamInfo>?
      final List<mdk.VideoStreamInfo>? videos = info.video;
      if (videos != null && videos.isNotEmpty) {
        final v = videos[0];
        // v.codec 是 VideoCodecParameters（非 null）
        final w = v.codec.width;
        final h = v.codec.height;
        final rotation = v.rotation;
        if (w > 0 && h > 0) {
          if (rotation % 180 == 90) {
            _videoWidth.value = h;
            _videoHeight.value = w;
          } else {
            _videoWidth.value = w;
            _videoHeight.value = h;
          }
        }
      }
    } catch (e) {
      debugPrint('[FvpEngine] _updateVideoSizeFromInfo error: $e');
    }
  }

  void _updateTracks() {
    final p = _player;
    if (p == null || !_isInitialized) return;

    try {
      availableAudioTracks.clear();
      availableVideoTracks.clear();
      availableSubtitleTracks.clear();

      final info = p.mediaInfo;

      // ---- 音轨 ----
      final audioList = info.audio ?? const <mdk.AudioStreamInfo>[];
      for (int i = 0; i < audioList.length; i++) {
        final stream = audioList[i];
        // stream.metadata 是 Map<String, String>
        final title = stream.metadata['title'];
        final lang = stream.metadata['language'];
        // stream.codec 是 AudioCodecParameters（非 null），.codec 是 String
        final codecName = stream.codec.codec;

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

      // ---- 视轨 ----
      final videoList = info.video ?? const <mdk.VideoStreamInfo>[];
      for (int i = 0; i < videoList.length; i++) {
        final stream = videoList[i];
        final codecName = stream.codec.codec;
        final rotation = stream.rotation;

        final buf = StringBuffer('视轨 ${i + 1}');
        if (codecName.isNotEmpty) buf.write(' · ${codecName.toUpperCase()}');
        if (rotation != 0) buf.write(' · $rotation°');

        availableVideoTracks.add(
          VideoTrack('fvp_video_$i', buf.toString(), ''),
        );
      }

      // ---- 字幕轨（过滤空占位轨） ----
      final subtitleList = info.subtitle ?? const <mdk.SubtitleStreamInfo>[];
      for (int i = 0; i < subtitleList.length; i++) {
        final stream = subtitleList[i];
        final meta = stream.metadata;

        int? frameCount;
        int? byteCount;
        final framesStr = meta['NUMBER_OF_FRAMES'];
        final bytesStr = meta['NUMBER_OF_BYTES'];
        if (framesStr != null) frameCount = int.tryParse(framesStr);
        if (bytesStr != null) byteCount = int.tryParse(bytesStr);

        final isEmpty = (frameCount != null && frameCount < 2) ||
            (byteCount != null && byteCount < 100);
        if (isEmpty) continue;

        final title = meta['title'];
        final lang = meta['language'];

        final buf = StringBuffer();
        if (title != null && title.isNotEmpty) {
          buf.write(title);
        } else if (lang != null && lang.isNotEmpty) {
          buf.write('字幕 ${i + 1} ($lang)');
        } else {
          buf.write('字幕 ${i + 1}');
        }

        final pos = availableSubtitleTracks.length;
        availableSubtitleTracks.add(
          SubtitleTrack('fvp_subtitle_$pos', buf.toString(), lang ?? '',
              uri: false),
        );
      }

      // ---- 同步当前激活轨道 ----
      // activeAudioTracks / activeVideoTracks / activeSubtitleTracks
      // 返回 List<int>（激活轨在对应列表中的索引）
      final activeAudio = p.activeAudioTracks;
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

      final activeVideo = p.activeVideoTracks;
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

      final activeSubtitle = p.activeSubtitleTracks;
      if (activeSubtitle.isNotEmpty) {
        final pos = activeSubtitle.first;
        if (pos >= 0 && pos < availableSubtitleTracks.length) {
          currentSubtitleTrack.value = availableSubtitleTracks[pos];
        } else {
          currentSubtitleTrack.value = null;
        }
      } else {
        currentSubtitleTrack.value = null;
      }
    } catch (e, st) {
      debugPrint('[FvpEngine] _updateTracks error: $e\n$st');
    }
  }

  // ============================================================
  // 播放控制
  // ============================================================
  @override
  Future<void> play({bool repeat = false, bool hideControls = true}) async {
    final p = _player;
    if (p == null || !_isInitialized) return;
    if (_isPlaying && playerStatus.value.isPlaying) return;

    controls = !hideControls;
    _completionReported = false;

    if (repeat) {
      try {
        await p.seek(position: 0);
      } catch (_) {}
    }
    p.state = mdk.PlaybackState.playing;
    // 状态由 onStateChanged 事件驱动
  }

  @override
  Future<void> pause({bool notify = true, bool isInterrupt = false}) async {
    final p = _player;
    if (p == null || !_isInitialized) return;
    p.state = mdk.PlaybackState.paused;
  }

  @override
  Future<void> seekTo(Duration position, {bool isSeek = true}) async {
    final p = _player;
    if (p == null || !_isInitialized) return;

    var target = position < Duration.zero ? Duration.zero : position;
    final dur = duration.value;
    if (dur != Duration.zero && target > dur) target = dur;

    try {
      // mdk.Player.seek 返回 Future<int>（实际位置毫秒，< 0 失败）
      final result = await p.seek(position: target.inMilliseconds);
      if (result >= 0) {
        this.position = Duration(milliseconds: result);
      } else {
        this.position = target;
      }
      updatePositionSecond();
      if (!isSliderMoving.value) {
        sliderPosition = this.position;
        updateSliderPositionSecond();
      }
    } catch (e) {
      debugPrint('[FvpEngine] seek error: $e');
    }
  }

  @override
  Future<void> refreshPlayer() async {
    if (dataSource == null) return;
    final currentPos = position;
    final wasPlaying = _isPlaying;
    await setDataSource(dataSource, autoplay: false, seekTo: currentPos);
    if (wasPlaying) await play();
  }

  // ============================================================
  // 音量 / 倍速
  // ============================================================
  @override
  double get maxVolume => 1.0;

  @override
  Future<void> setVolume(double volume, {bool showIndicator = true}) async {
    _volume = volume.clamp(0.0, 1.0);
    this.volume.value = _volume;
    _player?.volume = _volume;
    if (showIndicator) {
      volumeIndicator.value = true;
      volumeTimer?.cancel();
      volumeTimer = Timer(const Duration(milliseconds: 800), () {
        volumeIndicator.value = false;
      });
    }
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    lastPlaybackSpeed = _playbackSpeed;
    _playbackSpeed = speed;
    _player?.playbackRate = speed;
  }

  @override
  Future<void> setDefaultSpeed() async {
    await setPlaybackSpeed(1.0);
  }

  @override
  void setLongPressStatus(bool val) => longPressStatus.value = val;

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
        if (!removeSafeArea) showSystemBar();
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
        debugPrint('[FvpEngine] fullscreen error: $e');
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
  // 轨道切换
  // ============================================================
  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    final p = _player;
    if (p == null || !_isInitialized) return;
    final id = track.id;

    try {
      if (id == 'no' || id.isEmpty) {
        p.activeAudioTracks = <int>[];
      } else if (id == 'auto') {
        p.activeAudioTracks = <int>[0];
      } else if (id.startsWith('fvp_audio_')) {
        final pos = int.tryParse(id.substring('fvp_audio_'.length));
        if (pos != null) p.activeAudioTracks = <int>[pos];
      }
      currentAudioTrack.value = track;
    } catch (e) {
      debugPrint('[FvpEngine] setAudioTrack error: $e');
    }
  }

  @override
  Future<void> setVideoTrack(VideoTrack track) async {
    // libmdk 不提供运行时切换视频轨的 API
    debugPrint('[FvpEngine] 不支持切换视频轨');
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    final p = _player;
    if (p == null || !_isInitialized) return;
    final id = track.id;

    try {
      // ============================================================
      // 关闭字幕
      // ------------------------------------------------------------
      // 需要同时做两件事：
      //   1) 关闭主媒体源的内嵌字幕轨道
      //   2) unload 独立挂载的外挂字幕源
      // libmdk 通过 setMedia("", Subtitle) 实现 unload
      // ============================================================
      if (id == 'no' || id.isEmpty) {
        p.activeSubtitleTracks = <int>[];
        try {
          p.setMedia('', mdk.MediaType.subtitle);
        } catch (e) {
          debugPrint('[FvpEngine] unload external subtitle failed: $e');
        }
        currentSubtitleTrack.value = track;
        return;
      }

      // ============================================================
      // 自动选择：优先内嵌第一轨，同时清掉外挂
      // ============================================================
      if (id == 'auto') {
        try {
          p.setMedia('', mdk.MediaType.subtitle);
        } catch (_) {}
        p.activeSubtitleTracks = <int>[0];
        currentSubtitleTrack.value = track;
        return;
      }

      // ============================================================
      // 内嵌字幕：切换前先 unload 外挂，避免两路同时渲染
      // ============================================================
      if (id.startsWith('fvp_subtitle_')) {
        try {
          p.setMedia('', mdk.MediaType.subtitle);
        } catch (_) {}
        final pos = int.tryParse(id.substring('fvp_subtitle_'.length));
        if (pos != null) {
          p.activeSubtitleTracks = <int>[pos];
          currentSubtitleTrack.value = track;
        }
        return;
      }

      // ============================================================
      // 外挂字幕：先关闭内嵌，再挂载外挂源
      // ============================================================
      final isExternal = track.uri ||
          id.startsWith('http') ||
          id.startsWith('file://') ||
          id.startsWith('/') ||
          (Platform.isWindows && (id.contains(':\\') || id.startsWith('\\\\')));

      if (isExternal) {
        // 关闭内嵌字幕（否则可能会和外挂一起显示）
        p.activeSubtitleTracks = <int>[];

        String subPath = id;
        if (subPath.startsWith('file://')) {
          String pathPart = subPath.substring('file://'.length);
          if (Platform.isWindows && pathPart.startsWith('/')) {
            pathPart = pathPart.substring(1);
          }
          subPath = Uri.decodeComponent(pathPart);
        }
        // 重复调用 setMedia 会替换上一个外挂源，无需先 unload
        p.setMedia(subPath, mdk.MediaType.subtitle);
        currentSubtitleTrack.value = track;

        // mediaInfo.subtitle 不含外挂字幕，手动加入可选列表
        if (!availableSubtitleTracks.any((t) => t.id == track.id)) {
          availableSubtitleTracks.add(track);
        }
        return;
      }

      currentSubtitleTrack.value = track;
    } catch (e) {
      debugPrint('[FvpEngine] setSubtitleTrack error: $e');
    }
  }

  // ============================================================
  // 截图
  // ============================================================
  @override
  Future<void> takeScreenshot() async {
    if (_isDisposed || _player == null || !_isInitialized) {
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
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        SmartDialog.showToast('截图失败');
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      SmartDialog.showToast('点击弹窗保存截图');
      showDialog(
        context: Get.context!,
        builder: (context) => GestureDetector(
          onTap: () async {
            try {
              await ImageUtils.saveByteImg(
                bytes: bytes,
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
                    child: Image.memory(bytes),
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
  // 录制 / 外部音频
  // ============================================================
  @override
  void record(String? path) {
    final p = _player;
    if (p == null || !_isInitialized) return;
    try {
      if (path == null || path.isEmpty) {
        p.record(to: null);
        debugPrint('[FvpEngine] 录制停止');
      } else {
        p.record(to: path);
        debugPrint('[FvpEngine] 录制启动: $path');
      }
    } catch (e) {
      debugPrint('[FvpEngine] record error: $e');
    }
  }

  @override
  void setExternalAudio(String? url) {
    _externalAudioUrl = url;
    final p = _player;
    if (p == null || !_isInitialized) return;
    if (url == null || url.isEmpty) return;
    try {
      p.setMedia(url, mdk.MediaType.audio);
      debugPrint('[FvpEngine] 外部音频已加载: $url');
    } catch (e) {
      debugPrint('[FvpEngine] setExternalAudio error: $e');
    }
  }

  // ============================================================
  // 画中画 / 翻转 / 其他
  // ============================================================
  @override
  Future<void> enterDesktopPip() async {}
  @override
  Future<void> exitDesktopPip() async {}
  @override
  void toggleDesktopPip() {}

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
      _player?.loop = -1;
    } else {
      _isLooping = false;
      _player?.loop = 0;
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
  // 渲染：Texture
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
        // 依赖重建计数器
        final _ = _rebuildCounter.value;

        final p = _player;
        if (_isDisposed || p == null || !_isInitialized) {
          return const ColoredBox(color: Colors.black);
        }

        // mdk.Player.textureId 是 ValueNotifier<int?>
        return ValueListenableBuilder<int?>(
          valueListenable: p.textureId,
          builder: (context, texId, _) {
            if (texId == null || texId < 0) {
              return const ColoredBox(color: Colors.black);
            }
            Widget video = Texture(textureId: texId);

            if (flipX || flipY) {
              video = Transform(
                transform: Matrix4.identity()
                  ..setEntry(0, 0, flipX ? -1 : 1)
                  ..setEntry(1, 1, flipY ? -1 : 1),
                alignment: Alignment.center,
                child: video,
              );
            }

            final w = _videoWidth.value;
            final h = _videoHeight.value;
            if (w <= 0 || h <= 0) {
              return FittedBox(fit: fit, child: video);
            }
            return FittedBox(
              fit: fit,
              child: SizedBox(
                width: w.toDouble(),
                height: h.toDouble(),
                child: video,
              ),
            );
          },
        );
      }),
    );
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
  bool get supportsAudioTrack => true;
  @override
  bool get supportsVideoTrack => false;
  @override
  bool get supportsEmbeddedSubtitle => true;
  @override
  bool get supportsHardwareAcceleration => true;
  @override
  bool get supportsScreenshot => true;
  @override
  bool get supportsPictureInPicture => false;
  @override
  bool get supportsBufferProgress => true;

  @override
  bool get supportsRecording => true;

  @override
  bool get supportsExternalSubtitle => true;

  @override
  bool get supportsSubtitleExport => false;

  @override
  bool get supportsOnlyPlayAudio => false;

  @override
  bool get supportsHardwareDecodingSetting => false;

  @override
  bool get supportsExternalAudio => true;
}