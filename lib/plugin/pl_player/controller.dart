// lib/plugin/pl_player/controller.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'engine/i_player_engine.dart';
import 'engine/media_kit_engine.dart';
import 'engine/fvp_engine.dart';
import 'models/data_source.dart';
import 'models/data_status.dart';
import 'models/play_status.dart';
import 'models/video_fit_type.dart';
import 'models/play_repeat.dart';
import 'models/fullscreen_mode.dart';
import 'models/double_tap_type.dart';
import 'player_pref.dart';

typedef PlayCallback = Future<void>? Function();

/// 用于保存 setDataSource 参数的私有类（移出 PlPlayerController 顶层）
class _SetDataSourceParams {
  final DataSource dataSource;
  final bool autoplay;
  final Duration? seekTo;
  final double speed;
  final int? width;
  final int? height;
  final Duration? duration;
  final bool? isVertical;
  final String? vodId;
  final bool autoFullScreenFlag;

  const _SetDataSourceParams({
    required this.dataSource,
    required this.autoplay,
    this.seekTo,
    required this.speed,
    this.width,
    this.height,
    this.duration,
    this.isVertical,
    this.vodId,
    this.autoFullScreenFlag = false,
  });
}

/// 播放器门面（Facade）
/// 业务层唯一入口，内部根据配置委派给不同的引擎
class PlPlayerController {
  // ============================================================
  // 1. 单例管理
  // ============================================================
  static PlPlayerController? _instance;
  static bool instanceExists() => _instance != null;

  factory PlPlayerController.getInstance() {
    _instance ??= PlPlayerController._();
    return _instance!;
  }

  // ============================================================
  // 2. 内部引擎（改为可空，延迟初始化）
  // ============================================================
  IPlayerEngine? _engine;

  /// 确保引擎已初始化
  IPlayerEngine _ensureEngine() {
    if (_engine == null) {
      final type = PlayerPref.playerEngine;
      _engine = _createEngine(type);
      _engine!.init();
    }
    return _engine!;
  }

  IPlayerEngine _createEngine(PlayerEngineType type) {
    if (type == PlayerEngineType.fvp) {
      return FvpEngine();
    } else {
      return MediaKitEngine();
    }
  }

  // ============================================================
  // 3. 状态缓存（用于引擎切换时恢复）
  // ============================================================
  _SetDataSourceParams? _lastParams;
  PlayRepeat _currentPlayRepeat = PlayRepeat.pause;

  // ============================================================
  // 4. 构造
  // ============================================================
  PlPlayerController._() {
    // 引擎延迟到第一次使用时初始化
  }

  final RxDouble currentSpeed = 1.0.obs;

  // ============================================================
  // 5. 内核切换
  // ============================================================

  /// 切换播放器内核（运行时生效）
  Future<void> switchEngine(PlayerEngineType newType) async {
    // 如果当前引擎不存在，直接创建新引擎并更新配置
    if (_engine == null) {
      PlayerPref.playerEngine = newType;
      _engine = _createEngine(newType);
      await _engine!.init();
      return;
    }

    // 如果类型相同则跳过
    if (PlayerPref.playerEngine == newType) return;

    final oldEngine = _engine!;

    // 捕获当前状态
    final dataSource = _lastParams?.dataSource;
    final position = oldEngine.position;
    final isPlaying = oldEngine.playerStatus.value.isPlaying;
    final speed = oldEngine.playbackSpeed;
    final volume = oldEngine.volume.value;
    final repeat = _currentPlayRepeat;
    final params = _lastParams;

    // 释放旧引擎（dispose 是 void，不能 await）
    oldEngine.dispose();
    _engine = null;

    // 更新配置
    PlayerPref.playerEngine = newType;

    // 创建新引擎
    _engine = _createEngine(newType);
    await _engine!.init();

    // 如果有数据源，恢复状态
    if (dataSource != null && params != null) {
      // 恢复播放（不自动播放，之后手动控制）
      await _engine!.setDataSource(
        dataSource,
        autoplay: false,
        seekTo: position,
        speed: speed,
        width: params.width,
        height: params.height,
        duration: params.duration,
        isVertical: params.isVertical,
        vodId: params.vodId,
        onInit: null,
        autoFullScreenFlag: params.autoFullScreenFlag,
      );
      // 恢复音量
      await _engine!.setVolume(volume);
      // 恢复循环模式（setPlayRepeat 是 void，直接调用）
      _engine!.setPlayRepeat(repeat);
      // 恢复播放状态
      if (isPlaying) {
        await _engine!.play();
      }
    }
  }

  /// 重置数据状态（用于切换引擎时）
  void resetDataStatus() {
    _ensureEngine().dataStatus.value = DataStatus.none;
  }

  // ============================================================
  // 6. 静态辅助方法
  // ============================================================
  static PlayCallback? _playCallBack;
  static void setPlayCallBack(PlayCallback? callBack) {
    _playCallBack = callBack;
  }
  static Future<void>? playIfExists() {
    return _playCallBack?.call();
  }
  static PlayerStatus? getPlayerStatusIfExists() {
    return _instance?._ensureEngine().playerStatus.value;
  }
  static Future<void> pauseIfExists({
    bool notify = true,
    bool isInterrupt = false,
  }) async {
    if (_instance?._ensureEngine().playerStatus.isPlaying ?? false) {
      await _instance?._ensureEngine().pause(notify: notify, isInterrupt: isInterrupt);
    }
  }
  static Future<void> seekToIfExists(
    Duration position, {
    bool isSeek = true,
  }) async {
    await _instance?._ensureEngine().seekTo(position, isSeek: isSeek);
  }
  static double? getVolumeIfExists() {
    return _instance?._ensureEngine().volume.value;
  }
  static Future<void>? setVolumeIfExists(
    double volumeNew, {
    bool showIndicator = true,
  }) {
    return _instance?._ensureEngine().setVolume(volumeNew, showIndicator: showIndicator);
  }
  static void updatePlayCount() {
    // 空实现保持兼容
  }

  // ============================================================
  // 7. 透传：生命周期
  // ============================================================
  void dispose() => _engine?.dispose();
  void onCloseAll() => _engine?.onCloseAll();

  // ============================================================
  // 8. 透传：播放控制
  // ============================================================

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
    // 保存参数以便切换时恢复
    _lastParams = _SetDataSourceParams(
      dataSource: dataSource,
      autoplay: autoplay,
      seekTo: seekTo,
      speed: speed,
      width: width,
      height: height,
      duration: duration,
      isVertical: isVertical,
      vodId: vodId,
      autoFullScreenFlag: autoFullScreenFlag,
    );
    await _ensureEngine().setDataSource(
      dataSource,
      autoplay: autoplay,
      seekTo: seekTo,
      speed: speed,
      width: width,
      height: height,
      duration: duration,
      isVertical: isVertical,
      vodId: vodId,
      onInit: onInit,
      autoFullScreenFlag: autoFullScreenFlag,
    );
    currentSpeed.value = speed;
  }

  Future<void> play({bool repeat = false, bool hideControls = true}) =>
      _ensureEngine().play(repeat: repeat, hideControls: hideControls);
  Future<void> pause({bool notify = true, bool isInterrupt = false}) =>
      _ensureEngine().pause(notify: notify, isInterrupt: isInterrupt);
  Future<void> seekTo(Duration position, {bool isSeek = true}) =>
      _ensureEngine().seekTo(position, isSeek: isSeek);
  Future<void> refreshPlayer() => _ensureEngine().refreshPlayer();

  // ============================================================
  // 9. 透传：状态流
  // ============================================================
  Rx<PlayerStatus> get playerStatus => _ensureEngine().playerStatus;
  Rx<DataStatus> get dataStatus => _ensureEngine().dataStatus;
  Rx<Duration> get duration => _ensureEngine().duration;
  Rx<Duration> get buffered => _ensureEngine().buffered;
  RxBool get isBuffering => _ensureEngine().isBuffering;
  Duration get position => _ensureEngine().position;
  RxInt get positionSeconds => _ensureEngine().positionSeconds;
  Duration get sliderPosition => _ensureEngine().sliderPosition;
  RxInt get sliderPositionSeconds => _ensureEngine().sliderPositionSeconds;
  Rx<Duration> get sliderTempPosition => _ensureEngine().sliderTempPosition;

  // ============================================================
  // 10. 透传：属性
  // ============================================================
  double get playbackSpeed => _ensureEngine().playbackSpeed;
  double get longPressSpeed => _ensureEngine().longPressSpeed;
  bool get isVertical => _ensureEngine().isVertical;
  bool get isFileSource => _ensureEngine().isFileSource;
  bool get isMuted => _ensureEngine().isMuted;
  set isMuted(bool value) => _ensureEngine().isMuted = value;
  bool get isPipMode => _ensureEngine().isPipMode;
  bool get isDesktopPip => _ensureEngine().isDesktopPip;
  bool get showPreview => _ensureEngine().showPreview;
  bool get enableBlock => _ensureEngine().enableBlock;
  bool get showViewPoints => _ensureEngine().showViewPoints;
  bool get showDmChart => _ensureEngine().showDmChart;
  bool get isAnim => _ensureEngine().isAnim;

  RxBool get isFullScreen => _ensureEngine().isFullScreen;
  RxBool get controlsLock => _ensureEngine().controlsLock;
  RxBool get showControls => _ensureEngine().showControls;
  RxBool get longPressStatus => _ensureEngine().longPressStatus;
  Rx<VideoFitType> get videoFit => _ensureEngine().videoFit;
  RxBool get continuePlayInBackground => _ensureEngine().continuePlayInBackground;
  RxBool get isSliderMoving => _ensureEngine().isSliderMoving;
  RxBool get onlyPlayAudio => _ensureEngine().onlyPlayAudio;
  RxBool get flipX => _ensureEngine().flipX;
  RxBool get flipY => _ensureEngine().flipY;
  RxBool get enableShowDanmaku => _ensureEngine().enableShowDanmaku;
  RxDouble get danmakuOpacity => _ensureEngine().danmakuOpacity;

  // ============================================================
  // 11. 透传：音量 / 亮度
  // ============================================================
  RxDouble get volume => _ensureEngine().volume;
  RxDouble get brightness => _ensureEngine().brightness;
  double get maxVolume => _ensureEngine().maxVolume;
  Future<void> setVolume(double volume, {bool showIndicator = true}) =>
      _ensureEngine().setVolume(volume, showIndicator: showIndicator);

  RxBool get volumeIndicator => _ensureEngine().volumeIndicator;
  bool get volumeInterceptEventStream => _ensureEngine().volumeInterceptEventStream;
  Timer? get volumeTimer => _ensureEngine().volumeTimer;
  set volumeTimer(Timer? timer) => _ensureEngine().volumeTimer = timer;

  // ============================================================
  // 12. 透传：倍速
  // ============================================================
  Future<void> setPlaybackSpeed(double speed) async {
    await _ensureEngine().setPlaybackSpeed(speed);
    currentSpeed.value = speed;
  }
  Future<void> setDefaultSpeed() => _ensureEngine().setDefaultSpeed();
  void setLongPressStatus(bool val) => _ensureEngine().setLongPressStatus(val);
  List<double> get speedList => _ensureEngine().speedList;
  bool get enableAutoLongPressSpeed => _ensureEngine().enableAutoLongPressSpeed;
  double get lastPlaybackSpeed => _ensureEngine().lastPlaybackSpeed;

  // ============================================================
  // 13. 透传：全屏
  // ============================================================
  FullScreenMode get mode => _ensureEngine().mode;
  bool get horizontalScreen => _ensureEngine().horizontalScreen;
  bool get removeSafeArea => _ensureEngine().removeSafeArea;
  Future<void> triggerFullScreen({
    bool status = true,
    bool inAppFullScreen = false,
    DeviceOrientation? orientation,
    bool isManualFS = true,
  }) => _ensureEngine().triggerFullScreen(
    status: status,
    inAppFullScreen: inAppFullScreen,
    orientation: orientation,
    isManualFS: isManualFS,
  );

  // ============================================================
  // 14. 透传：轨道
  // ============================================================
  RxList<AudioTrack> get availableAudioTracks => _ensureEngine().availableAudioTracks;
  RxList<VideoTrack> get availableVideoTracks => _ensureEngine().availableVideoTracks;
  RxList<SubtitleTrack> get availableSubtitleTracks => _ensureEngine().availableSubtitleTracks;
  Rx<AudioTrack?> get currentAudioTrack => _ensureEngine().currentAudioTrack;
  Rx<VideoTrack?> get currentVideoTrack => _ensureEngine().currentVideoTrack;
  Rx<SubtitleTrack?> get currentSubtitleTrack => _ensureEngine().currentSubtitleTrack;
  Future<void> setAudioTrack(AudioTrack track) =>
      _ensureEngine().setAudioTrack(track);
  Future<void> setVideoTrack(VideoTrack track) =>
      _ensureEngine().setVideoTrack(track);
  Future<void> setSubtitleTrack(SubtitleTrack track) =>
      _ensureEngine().setSubtitleTrack(track);

  // ============================================================
  // 15. 透传：字幕样式
  // ============================================================
  double get subtitleFontScale => _ensureEngine().subtitleFontScale;
  set subtitleFontScale(double value) => _ensureEngine().subtitleFontScale = value;
  double get subtitleFontScaleFS => _ensureEngine().subtitleFontScaleFS;
  set subtitleFontScaleFS(double value) => _ensureEngine().subtitleFontScaleFS = value;
  int get subtitlePaddingH => _ensureEngine().subtitlePaddingH;
  set subtitlePaddingH(int value) => _ensureEngine().subtitlePaddingH = value;
  int get subtitlePaddingB => _ensureEngine().subtitlePaddingB;
  set subtitlePaddingB(int value) => _ensureEngine().subtitlePaddingB = value;
  double get subtitleBgOpacity => _ensureEngine().subtitleBgOpacity;
  set subtitleBgOpacity(double value) => _ensureEngine().subtitleBgOpacity = value;
  double get subtitleStrokeWidth => _ensureEngine().subtitleStrokeWidth;
  set subtitleStrokeWidth(double value) => _ensureEngine().subtitleStrokeWidth = value;
  int get subtitleFontWeight => _ensureEngine().subtitleFontWeight;
  set subtitleFontWeight(int value) => _ensureEngine().subtitleFontWeight = value;
  Rx<SubtitleViewConfiguration> get subtitleConfig => _ensureEngine().subtitleConfig;
  void updateSubtitleStyle() => _ensureEngine().updateSubtitleStyle();
  void putSubtitleSettings() => _ensureEngine().putSubtitleSettings();

  // ============================================================
  // 16. 透传：弹幕
  // ============================================================
  void toggleDanmaku() => _ensureEngine().toggleDanmaku();
  void refreshDanmakuConfig() => _ensureEngine().refreshDanmakuConfig();
  dynamic get danmakuController => _ensureEngine().danmakuController;
  set danmakuController(dynamic value) => _ensureEngine().danmakuController = value;

  // ============================================================
  // 17. 透传：播放模式
  // ============================================================
  PlayRepeat get playRepeat => _ensureEngine().playRepeat;
  set playRepeat(PlayRepeat value) => _ensureEngine().playRepeat = value;
  void setPlayRepeat(PlayRepeat type) {
    _currentPlayRepeat = type;
    _ensureEngine().setPlayRepeat(type);
  }

  // ============================================================
  // 18. 透传：截图 / 画中画 / 翻转
  // ============================================================
  Future<void> takeScreenshot() => _ensureEngine().takeScreenshot();
  Future<void> enterDesktopPip() => _ensureEngine().enterDesktopPip();
  Future<void> exitDesktopPip() => _ensureEngine().exitDesktopPip();
  void toggleDesktopPip() => _ensureEngine().toggleDesktopPip();
  void toggleFlipX() => _ensureEngine().toggleFlipX();
  void toggleFlipY() => _ensureEngine().toggleFlipY();

  // ============================================================
  // 19. 透传：音频模式
  // ============================================================
  void setOnlyPlayAudio() => _ensureEngine().setOnlyPlayAudio();
  void setContinuePlayInBackground() => _ensureEngine().setContinuePlayInBackground();

  // ============================================================
  // 20. 透传：控制栏 / 手势
  // ============================================================
  void onLockControl(bool val) => _ensureEngine().onLockControl(val);
  void onDoubleTapCenter() => _ensureEngine().onDoubleTapCenter();
  void onForward(Duration duration) => _ensureEngine().onForward(duration);
  void onBackward(Duration duration) => _ensureEngine().onBackward(duration);
  void onForwardBackward(Duration duration) => _ensureEngine().onForwardBackward(duration);
  void onChangedSlider(int v) => _ensureEngine().onChangedSlider(v);
  void onChangedSliderStart([Duration? value]) =>
      _ensureEngine().onChangedSliderStart(value);
  void onUpdatedSliderProgress(Duration value) =>
      _ensureEngine().onUpdatedSliderProgress(value);
  void onChangedSliderEnd() => _ensureEngine().onChangedSliderEnd();
  void updateSliderPositionSecond() => _ensureEngine().updateSliderPositionSecond();
  void updatePositionSecond() => _ensureEngine().updatePositionSecond();
  void updateBufferedSecond() => _ensureEngine().updateBufferedSecond();

  set controls(bool visible) => _ensureEngine().controls = visible;
  RxInt get progressType => _ensureEngine().progressType;

  bool? get cancelSeek => _ensureEngine().cancelSeek;
  set cancelSeek(bool? value) => _ensureEngine().cancelSeek = value;
  bool? get hasToast => _ensureEngine().hasToast;
  set hasToast(bool? value) => _ensureEngine().hasToast = value;
  bool get fullScreenGestureReverse => _ensureEngine().fullScreenGestureReverse;
  num get sliderScale => _ensureEngine().sliderScale;

  Duration get fastForBackwardDuration => _ensureEngine().fastForBackwardDuration;
  RxBool get mountSeekBackwardButton => _ensureEngine().mountSeekBackwardButton;
  RxBool get mountSeekForwardButton => _ensureEngine().mountSeekForwardButton;

  bool get showFsLockBtn => _ensureEngine().showFsLockBtn;
  bool get showFsScreenshotBtn => _ensureEngine().showFsScreenshotBtn;
  bool get enableShrinkVideoSize => _ensureEngine().enableShrinkVideoSize;
  bool get enableSlideVolumeBrightness => _ensureEngine().enableSlideVolumeBrightness;
  bool get enableSlideFS => _ensureEngine().enableSlideFS;

  Timer? get longPressTimer => _ensureEngine().longPressTimer;
  set longPressTimer(Timer? timer) => _ensureEngine().longPressTimer = timer;

  // ============================================================
  // 21. 透传：监听器
  // ============================================================
  void addPositionListener(ValueChanged<Duration> listener) =>
      _ensureEngine().addPositionListener(listener);
  void removePositionListener(ValueChanged<Duration> listener) =>
      _ensureEngine().removePositionListener(listener);
  void addStatusLister(ValueChanged<PlayerStatus> listener) =>
      _ensureEngine().addStatusLister(listener);
  void removeStatusLister(ValueChanged<PlayerStatus> listener) =>
      _ensureEngine().removeStatusLister(listener);

  // ============================================================
  // 22. 透传：渲染 / 底层对象
  // ============================================================
  Widget buildVideoWidget({
    required BoxFit fit,
    required bool flipX,
    required bool flipY,
  }) => _ensureEngine().buildVideoWidget(fit: fit, flipX: flipX, flipY: flipY);

  VideoController? get videoController => _engine?.videoController;
  Player? get videoPlayerController => _engine?.videoPlayerController;

  // ============================================================
  // 23. 透传：跳过片头片尾
  // ============================================================
  RxInt get skipStartDuration => _ensureEngine().skipStartDuration;
  RxInt get skipEndDuration => _ensureEngine().skipEndDuration;
  Future<void> applySkipStart() => _ensureEngine().applySkipStart();

  // ============================================================
  // 24. 透传：工具
  // ============================================================
  bool get processing => _ensureEngine().processing;
  String? get vodId => _ensureEngine().vodId;
  Duration get positionValue => _ensureEngine().positionValue;
  void hideTaskControls() => _ensureEngine().hideTaskControls();
  void cancelLongPressTimer() => _ensureEngine().cancelLongPressTimer();
  void onPopInvokedWithResult(bool didPop, Object? result) =>
      _ensureEngine().onPopInvokedWithResult(didPop, result);

  bool get setSystemBrightness => _ensureEngine().setSystemBrightness;
  int? get width => _ensureEngine().width;
  int? get height => _ensureEngine().height;
  bool get isCloseAll => _ensureEngine().isCloseAll;
  RxString get batteryLevel => _ensureEngine().batteryLevel;

  // ============================================================
  // 25. 透传：功能标志
  // ============================================================
  bool get supportsAudioTrack => _ensureEngine().supportsAudioTrack;
  bool get supportsVideoTrack => _ensureEngine().supportsVideoTrack;
  bool get supportsEmbeddedSubtitle => _ensureEngine().supportsEmbeddedSubtitle;
  bool get supportsHardwareAcceleration => _ensureEngine().supportsHardwareAcceleration;
  bool get supportsScreenshot => _ensureEngine().supportsScreenshot;
  bool get supportsPictureInPicture => _ensureEngine().supportsPictureInPicture;
  bool get supportsBufferProgress => _ensureEngine().supportsBufferProgress;

  // ============================================================
  // 26. 透传：额外方法
  // ============================================================
  void toggleVideoFit(VideoFitType value) => _ensureEngine().toggleVideoFit(value);
  void doubleTapFuc(DoubleTapType type) => _ensureEngine().doubleTapFuc(type);

  // ============================================================
  // 27. 透传：bufferedSeconds
  // ============================================================
  RxInt get bufferedSeconds => _ensureEngine().bufferedSeconds;

  // ============================================================
  // 分辨率 / 网速
  // ============================================================
  RxInt get videoWidth => _ensureEngine().videoWidth;
  RxInt get videoHeight => _ensureEngine().videoHeight;
  RxDouble get downloadSpeed => _ensureEngine().downloadSpeed;
}