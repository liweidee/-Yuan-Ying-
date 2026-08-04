// lib/plugin/pl_player/engine/i_player_engine.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/data_source.dart';
import '../models/data_status.dart';
import '../models/play_status.dart';
import '../models/video_fit_type.dart';
import '../models/play_repeat.dart';
import '../models/fullscreen_mode.dart';
import '../models/double_tap_type.dart';

/// 播放器引擎抽象接口
/// 完全镜像原 PlPlayerController 的所有公开成员
abstract class IPlayerEngine {
  // ============================================================
  // 1. 生命周期
  // ============================================================
  Future<void> init();
  void dispose();
  void onCloseAll();

  // ============================================================
  // 2. 核心播放控制
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
  });

  Future<void> play({bool repeat = false, bool hideControls = true});
  Future<void> pause({bool notify = true, bool isInterrupt = false});
  Future<void> seekTo(Duration position, {bool isSeek = true});
  Future<void> refreshPlayer();

  // ============================================================
  // 3. 状态流（Rx）
  // ============================================================
  Rx<PlayerStatus> get playerStatus;
  Rx<DataStatus> get dataStatus;
  Rx<Duration> get duration;
  Rx<Duration> get buffered;
  RxInt get bufferedSeconds;
  RxBool get isBuffering;
  Duration get position;
  RxInt get positionSeconds;
  Duration get sliderPosition;
  RxInt get sliderPositionSeconds;
  Rx<Duration> get sliderTempPosition;

  // ============================================================
  // 4. 播放器属性
  // ============================================================
  double get playbackSpeed;
  double get longPressSpeed;
  bool get isVertical;
  bool get isFileSource;
  bool get isMuted;
  set isMuted(bool value);
  bool get isPipMode;
  bool get isDesktopPip;
  bool get showPreview;
  bool get enableBlock;
  bool get showViewPoints;
  bool get showDmChart;
  bool get isAnim;

  RxBool get isFullScreen;
  RxBool get controlsLock;
  RxBool get showControls;
  RxBool get longPressStatus;
  Rx<VideoFitType> get videoFit;
  RxBool get continuePlayInBackground;
  RxBool get isSliderMoving;
  RxBool get onlyPlayAudio;
  RxBool get flipX;
  RxBool get flipY;
  RxBool get enableShowDanmaku;
  RxDouble get danmakuOpacity;

  // ============================================================
  // 5. 音量 / 亮度
  // ============================================================
  RxDouble get volume;
  RxDouble get brightness;
  double get maxVolume;
  Future<void> setVolume(double volume, {bool showIndicator = true});

  RxBool get volumeIndicator;
  bool get volumeInterceptEventStream;
  Timer? get volumeTimer;
  set volumeTimer(Timer? timer);

  // ============================================================
  // 6. 倍速
  // ============================================================
  Future<void> setPlaybackSpeed(double speed);
  Future<void> setDefaultSpeed();
  void setLongPressStatus(bool val);
  List<double> get speedList;
  bool get enableAutoLongPressSpeed;
  double get lastPlaybackSpeed;

  // ============================================================
  // 7. 全屏 / 方向
  // ============================================================
  FullScreenMode get mode;
  bool get horizontalScreen;
  bool get removeSafeArea;
  Future<void> triggerFullScreen({
    bool status = true,
    bool inAppFullScreen = false,
    DeviceOrientation? orientation,
    bool isManualFS = true,
  });

  // ============================================================
  // 8. 轨道
  // ============================================================
  RxList<AudioTrack> get availableAudioTracks;
  RxList<VideoTrack> get availableVideoTracks;
  RxList<SubtitleTrack> get availableSubtitleTracks;

  Rx<AudioTrack?> get currentAudioTrack;
  Rx<VideoTrack?> get currentVideoTrack;
  Rx<SubtitleTrack?> get currentSubtitleTrack;

  Future<void> setAudioTrack(AudioTrack track);
  Future<void> setVideoTrack(VideoTrack track);
  Future<void> setSubtitleTrack(SubtitleTrack track);

  // ============================================================
  // 9. 字幕样式
  // ============================================================
  double get subtitleFontScale;
  set subtitleFontScale(double value);
  double get subtitleFontScaleFS;
  set subtitleFontScaleFS(double value);
  int get subtitlePaddingH;
  set subtitlePaddingH(int value);
  int get subtitlePaddingB;
  set subtitlePaddingB(int value);
  double get subtitleBgOpacity;
  set subtitleBgOpacity(double value);
  double get subtitleStrokeWidth;
  set subtitleStrokeWidth(double value);
  int get subtitleFontWeight;
  set subtitleFontWeight(int value);

  Rx<SubtitleViewConfiguration> get subtitleConfig;
  void updateSubtitleStyle();
  void putSubtitleSettings();

  // ============================================================
  // 10. 弹幕
  // ============================================================
  void toggleDanmaku();
  void refreshDanmakuConfig();
  dynamic get danmakuController;
  set danmakuController(dynamic value);

  // ============================================================
  // 11. 播放模式
  // ============================================================
  PlayRepeat get playRepeat;
  set playRepeat(PlayRepeat value);
  void setPlayRepeat(PlayRepeat type);

  // ============================================================
  // 12. 截图
  // ============================================================
  Future<void> takeScreenshot();

  // ============================================================
  // 13. 画中画（桌面）
  // ============================================================
  Future<void> enterDesktopPip();
  Future<void> exitDesktopPip();
  void toggleDesktopPip();

  // ============================================================
  // 14. 翻转
  // ============================================================
  void toggleFlipX();
  void toggleFlipY();

  // ============================================================
  // 15. 音频模式 / 后台播放
  // ============================================================
  void setOnlyPlayAudio();
  void setContinuePlayInBackground();

  // ============================================================
  // 16. 控制栏 / 手势
  // ============================================================
  void onLockControl(bool val);
  void onDoubleTapCenter();
  void onForward(Duration duration);
  void onBackward(Duration duration);
  void onForwardBackward(Duration duration);
  void onChangedSlider(int v);
  void onChangedSliderStart([Duration? value]);
  void onUpdatedSliderProgress(Duration value);
  void onChangedSliderEnd();
  void updateSliderPositionSecond();
  void updatePositionSecond();
  void updateBufferedSecond();

  set controls(bool visible);
  RxInt get progressType;

  bool? get cancelSeek;
  set cancelSeek(bool? value);
  bool? get hasToast;
  set hasToast(bool? value);
  bool get fullScreenGestureReverse;
  num get sliderScale;

  Duration get fastForBackwardDuration;
  RxBool get mountSeekBackwardButton;
  RxBool get mountSeekForwardButton;

  bool get showFsLockBtn;
  bool get showFsScreenshotBtn;
  bool get enableShrinkVideoSize;
  bool get enableSlideVolumeBrightness;
  bool get enableSlideFS;

  Timer? get longPressTimer;
  set longPressTimer(Timer? timer);

  // ============================================================
  // 17. 监听器
  // ============================================================
  void addPositionListener(ValueChanged<Duration> listener);
  void removePositionListener(ValueChanged<Duration> listener);
  void addStatusLister(ValueChanged<PlayerStatus> listener);
  void removeStatusLister(ValueChanged<PlayerStatus> listener);

  // ============================================================
  // 18. 渲染
  // ============================================================
  Widget buildVideoWidget({
    required BoxFit fit,
    required bool flipX,
    required bool flipY,
  });

  // ============================================================
  // 19. 获取底层对象
  // ============================================================
  VideoController? get videoController;
  Player? get videoPlayerController;

  // ============================================================
  // 20. 跳过片头片尾
  // ============================================================
  RxInt get skipStartDuration;
  RxInt get skipEndDuration;
  Future<void> applySkipStart();

  // ============================================================
  // 21. 工具
  // ============================================================
  bool get processing;
  String? get vodId;
  Duration get positionValue;
  void hideTaskControls();
  void cancelLongPressTimer();
  void onPopInvokedWithResult(bool didPop, Object? result);

  bool get setSystemBrightness;
  int? get width;
  int? get height;
  bool get isCloseAll;
  RxString get batteryLevel;

  // ============================================================
  // 22. 功能标志
  // ============================================================
  bool get supportsAudioTrack;
  bool get supportsVideoTrack;
  bool get supportsEmbeddedSubtitle;
  bool get supportsHardwareAcceleration;
  bool get supportsScreenshot;
  bool get supportsPictureInPicture;
  bool get supportsBufferProgress;

  // ============================================================
  // 23. 切换画质 / 双击处理
  // ============================================================
  void toggleVideoFit(VideoFitType value);
  void doubleTapFuc(DoubleTapType type);

  // ============================================================
  // 分辨率 / 网速
  // ============================================================
  RxInt get videoWidth;
  RxInt get videoHeight;
  RxDouble get downloadSpeed;
}