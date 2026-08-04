// lib/plugin/pl_player/view.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox, SemanticsConfiguration;
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';

import 'package:yuanying/common/assets.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/common/widgets/cropped_image.dart';
import 'package:yuanying/common/widgets/custom_icon.dart';
import 'package:yuanying/common/widgets/disabled_icon.dart';
import 'package:yuanying/common/widgets/gesture/immediate_tap_gesture_recognizer.dart';
import 'package:yuanying/common/widgets/gesture/mouse_interactive_viewer.dart';
import 'package:yuanying/common/widgets/gesture/player_gesture_recognizer.dart';
import 'package:yuanying/common/widgets/loading_widget/loading_widget.dart';
import 'package:yuanying/common/widgets/pair.dart';
import 'package:yuanying/common/widgets/player_bar.dart';
import 'package:yuanying/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:yuanying/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:yuanying/common/widgets/view_safe_area.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/plugin/pl_player/models/bottom_control_type.dart';
import 'package:yuanying/plugin/pl_player/models/data_status.dart';
import 'package:yuanying/plugin/pl_player/models/double_tap_type.dart';
import 'package:yuanying/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:yuanying/plugin/pl_player/models/gesture_type.dart';
import 'package:yuanying/plugin/pl_player/models/play_status.dart';
import 'package:yuanying/plugin/pl_player/models/video_fit_type.dart';
import 'package:yuanying/plugin/pl_player/widgets/app_bar_ani.dart';
import 'package:yuanying/plugin/pl_player/widgets/backward_seek.dart';
import 'package:yuanying/plugin/pl_player/widgets/bottom_control.dart';
import 'package:yuanying/plugin/pl_player/widgets/common_btn.dart';
import 'package:yuanying/plugin/pl_player/widgets/forward_seek.dart';
import 'package:yuanying/plugin/pl_player/widgets/play_pause_btn.dart';
import 'package:yuanying/utils/cache_manager.dart';
import 'package:yuanying/utils/duration_utils.dart';
import 'package:yuanying/utils/extension/num_ext.dart';
import 'package:yuanying/utils/extension/theme_ext.dart';
import 'package:yuanying/utils/image_utils.dart';
import 'package:yuanying/utils/mobile_observer.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/utils/theme_utils.dart';
import 'package:yuanying/utils/utils.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:fl_chart/fl_chart.dart';

/// 视频播放器主界面
class PLVideoPlayer extends StatefulWidget {
  const PLVideoPlayer({
    required this.maxWidth,
    required this.maxHeight,
    required this.plPlayerController,
    required this.headerControl,
    this.controllerTag = '',
    this.bottomControl,
    this.danmuWidget,
    this.fill = Colors.black,
    this.alignment = Alignment.center,
    super.key,
  });

  final double maxWidth;
  final double maxHeight;
  final PlPlayerController plPlayerController;
  final Widget headerControl;
  final String controllerTag; // ===== 新增 =====
  final Widget? bottomControl;
  final Widget? danmuWidget;
  final Color fill;
  final Alignment alignment;

  @override
  State<PLVideoPlayer> createState() => _PLVideoPlayerState(); // ===== 修复：补回 createState =====
}

/// 剧集导航按钮类型
enum _EpisodeNavType { prev, next }

/// 剧集导航按钮（上一集/下一集）
class _EpisodeNavButton extends StatelessWidget {
  const _EpisodeNavButton({
    required this.type,
    required this.widgetWidth,
    required this.controllerTag,
    required this.plPlayerController,
  });

  final _EpisodeNavType type;
  final double widgetWidth;
  final String controllerTag;
  final PlPlayerController plPlayerController;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      try {
        final detailController = controllerTag.isNotEmpty
            ? Get.find<DetailController>(tag: controllerTag)
            : Get.find<DetailController>();

        final episodes = detailController.introController.displayEpisodes;
        final total = episodes.length;
        if (total <= 1) {
          return const SizedBox.shrink();
        }
        final currentIdx = detailController.introController.currentEpisodeIndex.value;
        final bool canAction = type == _EpisodeNavType.prev
            ? currentIdx > 0
            : currentIdx < total - 1;

        final String tooltip = type == _EpisodeNavType.prev
            ? (canAction ? '上一集' : '已是第一集')
            : (canAction ? '下一集' : '已是最后一集');

        final IconData icon = type == _EpisodeNavType.prev
            ? Icons.skip_previous
            : Icons.skip_next;

        return ComBtn(
          width: widgetWidth,
          height: 30,
          tooltip: tooltip,
          icon: Icon(
            icon,
            size: 22,
            color: canAction ? Colors.white : Colors.white54,
          ),
          onTap: canAction
              ? () {
                  if (type == _EpisodeNavType.prev) {
                    detailController.playPrev();
                  } else {
                    detailController.playNext();
                  }
                }
              : null,
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    });
  }
}

class _PLVideoPlayerState extends State<PLVideoPlayer>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late AnimationController _animationController;
  VideoController? videoController;

  final _playerKey = GlobalKey();
  final _videoKey = GlobalKey();

  final RxDouble _brightnessValue = 0.0.obs;
  final RxBool _brightnessIndicator = false.obs;
  Timer? _brightnessTimer;

  late FullScreenMode mode;

  late final RxBool showRestoreScaleBtn = false.obs;

  GestureType? _gestureType;
  Offset? _initialFocalPoint;

  bool _pauseDueToPauseUponEnteringBackgroundMode = false;

  StreamSubscription? _brightnessListener;

  void _onBrightnessChanged(double value) {
    if (mounted && _gestureType != GestureType.left) {
      _brightnessValue.value = value;
    }
  }

  void _getSystemBrightness() {
    ScreenBrightnessPlatform.instance.system.then((res) {
      if (mounted) {
        _brightnessValue.value = res;
      }
    });
  }

  void _getAppBrightness() {
    ScreenBrightnessPlatform.instance.application.then((res) {
      if (mounted) {
        _brightnessValue.value = res;
      }
    });
  }

  void _onVolumeChanged(double value) {
    if (mounted && !plPlayerController.volumeInterceptEventStream) {
      plPlayerController.volume.value = value;
      if (Platform.isIOS && !FlutterVolumeController.showSystemUI) {
        plPlayerController
          ..volumeIndicator.value = true
          ..volumeTimer?.cancel()
          ..volumeTimer = Timer(
            const Duration(milliseconds: 800),
            () {
              if (mounted) {
                plPlayerController.volumeIndicator.value = false;
              }
            },
          );
      }
    }
  }

  void _getCurrVolume() {
    FlutterVolumeController.getVolume().then((res) {
      if (mounted) {
        plPlayerController.volume.value = res!;
      }
    });
  }

  StreamSubscription? _controlsListener;
  StreamSubscription? _controlsLockListener;

  void _onControlChanged(bool val) {
    final visible = val && !plPlayerController.controlsLock.value;

    if (visible) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    addObserverMobile(this);

    _controlsListener = plPlayerController.showControls.listen(
      _onControlChanged,
    );

    _controlsLockListener = plPlayerController.controlsLock.listen(
      (_) => _onControlChanged(plPlayerController.showControls.value),
    );

    _transformationController = TransformationController();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    videoController = plPlayerController.videoController;

    if (PlatformUtils.isMobile) {
      Future.microtask(() {
        try {
          FlutterVolumeController.updateShowSystemUI(true);
          _getCurrVolume();
          FlutterVolumeController.addListener(
            _onVolumeChanged,
            emitOnStart: false,
          );
        } catch (_) {}

        try {
          if (Platform.isIOS || plPlayerController.setSystemBrightness) {
            _getSystemBrightness();
            _brightnessListener = ScreenBrightnessPlatform
                .instance
                .onSystemScreenBrightnessChanged
                .listen(_onBrightnessChanged);
          } else {
            _getAppBrightness();
            _brightnessListener = ScreenBrightnessPlatform
                .instance
                .onApplicationScreenBrightnessChanged
                .listen(_onBrightnessChanged);
          }
        } catch (_) {}
      });
    }

    _tapGestureRecognizer = ImmediateTapGestureRecognizer(onTapUp: _onTapUp);

    _doubleTapGestureRecognizer = DoubleTapGestureRecognizer()
      ..onDoubleTapDown = _onDoubleTapDown;

    _scaleGestureRecognizer = PlayerScaleGestureRecognizer(
      debugOwner: this,
      dragStartBehavior: DragStartBehavior.start,
      allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
      trackpadScrollToScaleFactor: const Offset(
        0,
        -1 / kDefaultMouseScrollToScaleFactor,
      ),
      trackpadScrollCausesScale: false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!plPlayerController.continuePlayInBackground.value) {
      late final player = plPlayerController.videoPlayerController;
      if (const <AppLifecycleState>[AppLifecycleState.paused, AppLifecycleState.detached]
          .contains(state)) {
        if (player != null && player.state.playing) {
          _pauseDueToPauseUponEnteringBackgroundMode = true;
          player.pause();
        }
      } else {
        if (_pauseDueToPauseUponEnteringBackgroundMode) {
          _pauseDueToPauseUponEnteringBackgroundMode = false;
          player?.play();
        }
      }
    }
  }

  Future<void> setBrightness(double value) async {
    _brightnessValue.value = value;
    try {
      if (Platform.isIOS || plPlayerController.setSystemBrightness) {
        await ScreenBrightnessPlatform.instance.setSystemScreenBrightness(
          value,
        );
      } else {
        await ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(
          value,
        );
      }
    } catch (_) {}
    _brightnessIndicator.value = true;
    _brightnessTimer?.cancel();
    _brightnessTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        _brightnessIndicator.value = false;
      }
    });
    plPlayerController.brightness.value = value;
  }

  @override
  void dispose() {
    removeObserverMobile(this);
    _tapGestureRecognizer.dispose();
    _longPressRecognizer?.dispose();
    _doubleTapGestureRecognizer.dispose();
    _scaleGestureRecognizer.dispose();
    _brightnessListener?.cancel();
    _controlsListener?.cancel();
    _controlsLockListener?.cancel();
    _animationController.dispose();
    _transformationController.dispose();
    if (PlatformUtils.isMobile) {
      FlutterVolumeController.removeListener();
    }
    super.dispose();
  }

  // ===== 底部控制条构建 =====
  Widget buildBottomControl(bool isLandscape) {
    final isFullScreen = this.isFullScreen;
    final double widgetWidth = isLandscape && isFullScreen ? 42 : 35;
    final String controllerTag = widget.controllerTag;
    final bool isFvpEngine = PlayerPref.playerEngine == PlayerEngineType.fvp;

    Widget progressWidget(BottomControlType type) => switch (type) {
      BottomControlType.playOrPause => PlayOrPauseButton(plPlayerController: plPlayerController),
      BottomControlType.time => Obx(
        () => _VideoTime(
          position: DurationUtils.formatDuration(
            plPlayerController.positionSeconds.value,
          ),
          duration: DurationUtils.formatDuration(
            plPlayerController.duration.value.inSeconds,
          ),
        ),
      ),
      BottomControlType.prev => Padding(
        padding: const EdgeInsets.only(left: 10),
        child: _EpisodeNavButton(
          type: _EpisodeNavType.prev,
          widgetWidth: widgetWidth,
          controllerTag: controllerTag,
          plPlayerController: plPlayerController,
        ),
      ),
      BottomControlType.next => _EpisodeNavButton(
        type: _EpisodeNavType.next,
        widgetWidth: widgetWidth,
        controllerTag: controllerTag,
        plPlayerController: plPlayerController,
      ),
      BottomControlType.parser => Obx(() {
        try {
          final detailController = controllerTag.isNotEmpty
              ? Get.find<DetailController>(tag: controllerTag)
              : Get.find<DetailController>();
          if (!detailController.showParserButton.value) {
            return const SizedBox.shrink();
          }
        } catch (_) {
          return const SizedBox.shrink();
        }
        return ComBtn(
          width: widgetWidth,
          height: 30,
          tooltip: '解析',
          icon: const Icon(
            Icons.auto_awesome,
            size: 18,
            color: Colors.white,
          ),
          onTap: () {
            try {
              final detailController = controllerTag.isNotEmpty
                  ? Get.find<DetailController>(tag: controllerTag)
                  : Get.find<DetailController>();
              detailController.showParserMenu();
            } catch (_) {}
          },
        );
      }),
      BottomControlType.episode => ComBtn(
        width: widgetWidth,
        height: 30,
        tooltip: '全部选集',
        icon: const Icon(
          Icons.playlist_play,
          size: 24,
          color: Colors.white,
        ),
        onTap: () {
          try {
            final detailController = controllerTag.isNotEmpty
                ? Get.find<DetailController>(tag: controllerTag)
                : Get.find<DetailController>();
            detailController.showEpisodePanel();
          } catch (_) {}
        },
      ),
      BottomControlType.fit => Obx(
        () {
          final fit = plPlayerController.videoFit.value;
          return PopupMenuButton<VideoFitType>(
            tooltip: '画面比例',
            requestFocus: false,
            initialValue: fit,
            color: Colors.black.withValues(alpha: 0.8),
            itemBuilder: (context) {
              return VideoFitType.values
                  .map(
                    (boxFit) => PopupMenuItem<VideoFitType>(
                      height: 35,
                      padding: const EdgeInsets.only(left: 30),
                      value: boxFit,
                      onTap: () => plPlayerController.toggleVideoFit(boxFit),
                      child: Text(
                        boxFit.desc,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                  .toList();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                fit.desc,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          );
        },
      ),
      BottomControlType.speed => Obx(
        () {
          final speed = plPlayerController.currentSpeed.value;
          return PopupMenuButton<double>(
            tooltip: '倍速',
            requestFocus: false,
            initialValue: speed,
            color: Colors.black.withValues(alpha: 0.8),
            itemBuilder: (context) {
              return plPlayerController.speedList
                  .map(
                    (double s) => PopupMenuItem<double>(
                      height: 35,
                      padding: const EdgeInsets.only(left: 30),
                      value: s,
                      onTap: () => plPlayerController.setPlaybackSpeed(s),
                      child: Text(
                        "${s}X",
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        semanticsLabel: "$s倍速",
                      ),
                    ),
                  )
                  .toList();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                "${speed}X",
                style: const TextStyle(color: Colors.white, fontSize: 13),
                semanticsLabel: "${speed}倍速",
              ),
            ),
          );
        },
      ),
      BottomControlType.subtitle => Obx(() {
        final tracks = widget.plPlayerController.availableSubtitleTracks;
        if (tracks.isEmpty) {
          return const SizedBox.shrink();
        }
        final currentTrack = widget.plPlayerController.currentSubtitleTrack.value;
        Object initialValue;
        if (currentTrack == null || currentTrack.id == 'no' || currentTrack.id == '') {
          initialValue = '_no';
        } else if (currentTrack.id == 'auto') {
          initialValue = '_auto';
        } else {
          initialValue = currentTrack.id;
        }
        return PopupMenuButton<Object>(
          tooltip: '字幕',
          requestFocus: false,
          initialValue: initialValue,
          color: Colors.black.withValues(alpha: 0.8),
          itemBuilder: (context) {
            final items = <PopupMenuItem<Object>>[];
            items.add(
              PopupMenuItem<Object>(
                value: '_no',
                height: 35,
                onTap: () {
                  widget.plPlayerController.setSubtitleTrack(SubtitleTrack.no());
                },
                child: const Text(
                  '关闭字幕',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            );
            items.add(
              PopupMenuItem<Object>(
                value: '_auto',
                height: 35,
                onTap: () {
                  widget.plPlayerController.setSubtitleTrack(SubtitleTrack.auto());
                },
                child: const Text(
                  '自动选择',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            );
            for (final track in tracks) {
              items.add(
                PopupMenuItem<Object>(
                  value: track.id,
                  height: 35,
                  onTap: () {
                    widget.plPlayerController.setSubtitleTrack(track);
                  },
                  child: Text(
                    track.title ?? '字幕 ${tracks.indexOf(track) + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              );
            }
            return items;
          },
          child: SizedBox(
            width: widgetWidth,
            height: 30,
            child: Obx(() {
              final current = widget.plPlayerController.currentSubtitleTrack.value;
              final hasActiveSubtitle = current != null && current.id != 'no';
              return Icon(
                Icons.closed_caption_off,
                size: 22,
                color: hasActiveSubtitle ? Colors.white : Colors.white54,
              );
            }),
          ),
        );
      }),
      BottomControlType.fullscreen => ComBtn(
        width: widgetWidth,
        height: 30,
        tooltip: isFullScreen ? '退出全屏' : '全屏',
        icon: isFullScreen
            ? const Icon(Icons.fullscreen_exit, size: 24, color: Colors.white)
            : const Icon(Icons.fullscreen, size: 24, color: Colors.white),
        onTap: () => plPlayerController.triggerFullScreen(status: !isFullScreen),
        onSecondaryTap: () => plPlayerController.triggerFullScreen(
          status: !isFullScreen,
          inAppFullScreen: true,
        ),
      ),
      BottomControlType.pip => ComBtn(
        width: widgetWidth,
        height: 30,
        tooltip: plPlayerController.isDesktopPip ? '退出画中画' : '画中画',
        icon: plPlayerController.isDesktopPip
            ? const Icon(
                Icons.picture_in_picture_alt,
                size: 22,
                color: Colors.white,
              )
            : const Icon(
                Icons.picture_in_picture_outlined,
                size: 22,
                color: Colors.white,
              ),
        onTap: plPlayerController.toggleDesktopPip,
      ),
      _ => const SizedBox.shrink(),
    };

    List<BottomControlType> leftItems = [
      BottomControlType.playOrPause,
      BottomControlType.time,
      BottomControlType.prev,
      BottomControlType.next,
    ];

    List<BottomControlType> rightItems;
    if (isFvpEngine) {
      rightItems = [
        BottomControlType.parser,
        BottomControlType.episode,
        BottomControlType.fit,
        BottomControlType.speed,
        if (!plPlayerController.isDesktopPip) BottomControlType.fullscreen,
      ];
    } else {
      rightItems = [
        BottomControlType.parser,
        BottomControlType.episode,
        BottomControlType.fit,
        BottomControlType.subtitle,
        BottomControlType.speed,
        if (!plPlayerController.isDesktopPip) BottomControlType.fullscreen,
      ];
    }

    return PlayerBar(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: leftItems.map(progressWidget).toList(),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: rightItems.map(progressWidget).toList(),
        ),
      ],
    );
  }

  PlPlayerController get plPlayerController => widget.plPlayerController;

  bool get isFullScreen => plPlayerController.isFullScreen.value;

  late final TransformationController _transformationController;

  late ColorScheme colorScheme;
  late double maxWidth;
  late double maxHeight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorScheme = ColorScheme.of(context);
  }

  // ===== 手势处理 =====
  void _onPanStart(ScaleStartDetails details) {
    _gestureType = null;
    _initialFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(double scale) {
    showRestoreScaleBtn.value = scale != 1.0;
  }

  void _onPanUpdate(ScaleUpdateDetails details) {
    if (_gestureType == null) {
      final cumulativeDelta = details.localFocalPoint - _initialFocalPoint!;
      if (cumulativeDelta.distanceSquared < 1) return;
      final dx = cumulativeDelta.dx.abs();
      final dy = cumulativeDelta.dy.abs();
      if (dx > 3 * dy) {
        _gestureType = GestureType.horizontal;
      } else if (dy > 3 * dx) {
        if (!plPlayerController.enableSlideVolumeBrightness &&
            !plPlayerController.enableSlideFS) {
          return;
        }

        final double tapPosition = details.localFocalPoint.dx;
        final double sectionWidth = maxWidth / 3;
        if (tapPosition < sectionWidth) {
          if (!plPlayerController.enableSlideVolumeBrightness) {
            return;
          }
          if (PlatformUtils.isDesktop) {
            _gestureType = GestureType.right;
          } else {
            _gestureType = GestureType.left;
          }
        } else if (tapPosition < sectionWidth * 2) {
          if (!plPlayerController.enableSlideFS) {
            return;
          }
          _gestureType = GestureType.center;
        } else {
          if (!plPlayerController.enableSlideVolumeBrightness) {
            return;
          }
          _gestureType = GestureType.right;
        }
      }
      return;
    }

    Offset delta = details.focalPointDelta;

    if (_gestureType == GestureType.horizontal) {
      final int curSliderPosition =
          plPlayerController.sliderPosition.inMilliseconds;
      final int newPos =
          (curSliderPosition +
                  (plPlayerController.sliderScale * delta.dx / maxWidth)
                      .round())
              .clamp(0, plPlayerController.duration.value.inMilliseconds);
      final Duration result = Duration(milliseconds: newPos);
      final height = maxHeight * 0.125;
      if (details.localFocalPoint.dy <= height &&
          (details.localFocalPoint.dx >= maxWidth * 0.875 ||
              details.localFocalPoint.dx <= maxWidth * 0.125)) {
        plPlayerController.cancelSeek = true;
        if (plPlayerController.hasToast != true) {
          plPlayerController.hasToast = true;
          SmartDialog.showAttach(
            targetContext: context,
            alignment: Alignment.center,
            animationTime: const Duration(milliseconds: 200),
            animationType: SmartAnimationType.fade,
            displayTime: const Duration(milliseconds: 1500),
            maskColor: Colors.transparent,
            builder: (context) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(
                  Radius.circular(6),
                ),
                color: colorScheme.secondaryContainer,
              ),
              child: Text(
                '松开手指，取消进退',
                style: TextStyle(
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          );
        }
      } else {
        if (plPlayerController.cancelSeek == true) {
          plPlayerController
            ..cancelSeek = null
            ..hasToast = null;
        }
      }
      plPlayerController
        ..onUpdatedSliderProgress(result)
        ..onChangedSliderStart();
    } else if (_gestureType == GestureType.left) {
      final double level = maxHeight * 3;
      final double brightness = (_brightnessValue.value - delta.dy / level)
          .clamp(0.0, 1.0);
      setBrightness(brightness);
    } else if (_gestureType == GestureType.center) {
      const double threshold = 2.5;
      double cumulativeDy = details.localFocalPoint.dy - _initialFocalPoint!.dy;

      void fullScreenTrigger(bool status) {
        plPlayerController.triggerFullScreen(status: status);
      }

      if (cumulativeDy > threshold) {
        _gestureType = GestureType.center_down;
        if (isFullScreen ^ plPlayerController.fullScreenGestureReverse) {
          fullScreenTrigger(
            plPlayerController.fullScreenGestureReverse,
          );
        }
      } else if (cumulativeDy < -threshold) {
        _gestureType = GestureType.center_up;
        if (!isFullScreen ^ plPlayerController.fullScreenGestureReverse) {
          fullScreenTrigger(
            !plPlayerController.fullScreenGestureReverse,
          );
        }
      }
    } else if (_gestureType == GestureType.right) {
      final double level = maxHeight * 0.5;
      EasyThrottle.throttle(
        'setVolume',
        const Duration(milliseconds: 20),
        () {
          final double volume = clampDouble(
            plPlayerController.volume.value - delta.dy / level,
            0.0,
            plPlayerController.maxVolume,
          );
          plPlayerController.setVolume(volume);
        },
      );
    }
  }

  void _onPanEnd(ScaleEndDetails details) {
    if (plPlayerController.isSliderMoving.value) {
      if (plPlayerController.cancelSeek == true) {
        plPlayerController.onUpdatedSliderProgress(
          plPlayerController.position,
        );
      } else {
        plPlayerController.seekTo(
          plPlayerController.sliderPosition,
          isSeek: false,
        );
      }
      plPlayerController.onChangedSliderEnd();
    }
    _initialFocalPoint = null;
    _gestureType = null;
  }

  void onDoubleTapDownMobile(TapDownDetails details) {
    if (plPlayerController.controlsLock.value) {
      return;
    }
    final double tapPosition = details.localPosition.dx;
    final double sectionWidth = maxWidth / 4;
    DoubleTapType type;
    if (tapPosition < sectionWidth) {
      type = DoubleTapType.left;
    } else if (tapPosition < sectionWidth * 3) {
      type = DoubleTapType.center;
    } else {
      type = DoubleTapType.right;
    }
    plPlayerController.doubleTapFuc(type);
  }

  void _onTapUp(TapUpDetails details) {
    switch (details.kind) {
      case PointerDeviceKind.mouse when PlatformUtils.isDesktop:
        plPlayerController.onDoubleTapCenter();
      default:
        plPlayerController.controls = !plPlayerController.showControls.value;
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    switch (details.kind) {
      case PointerDeviceKind.mouse when PlatformUtils.isDesktop:
        plPlayerController.triggerFullScreen(status: !isFullScreen);
      default:
        onDoubleTapDownMobile(details);
    }
  }

  LongPressGestureRecognizer? _longPressRecognizer;
  LongPressGestureRecognizer get longPressRecognizer => _longPressRecognizer ??=
      LongPressGestureRecognizer()
        ..onLongPressStart = ((_) =>
            plPlayerController.setLongPressStatus(true))
        ..onLongPressEnd = ((_) => plPlayerController.setLongPressStatus(false))
        ..onLongPressCancel = (() =>
            plPlayerController.setLongPressStatus(false));

  late final ImmediateTapGestureRecognizer _tapGestureRecognizer;
  late final DoubleTapGestureRecognizer _doubleTapGestureRecognizer;
  late final PlayerScaleGestureRecognizer _scaleGestureRecognizer;

  static const _kOffsetThreshold = 25.0;

  bool _isPositionAllowed(Offset offset) {
    if (offset.dx < _kOffsetThreshold ||
        offset.dy < _kOffsetThreshold ||
        offset.dx > maxWidth - _kOffsetThreshold ||
        offset.dy > maxHeight - _kOffsetThreshold) {
      return false;
    }
    return true;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (PlatformUtils.isDesktop) {
      final buttons = event.buttons;
      final isSecondaryBtn = buttons == kSecondaryMouseButton;
      if (isSecondaryBtn || buttons == kMiddleMouseButton) {
        final isFullScreen = this.isFullScreen;
        if (isFullScreen && plPlayerController.controlsLock.value) {
          plPlayerController
            ..controlsLock.value = false
            ..showControls.value = false;
        }
        plPlayerController.triggerFullScreen(
          status: !isFullScreen,
          inAppFullScreen: isSecondaryBtn,
        );
        return;
      }
    }

    final controlsUnlock = !plPlayerController.controlsLock.value;
    if (PlatformUtils.isMobile) {
      _tapGestureRecognizer.addPointer(event);
      if (controlsUnlock) {
        _doubleTapGestureRecognizer.addPointer(event);
        longPressRecognizer.addPointer(event);
        _scaleGestureRecognizer
          ..isPosAllowed = _isPositionAllowed(event.localPosition)
          ..addPointer(event);
      }
    } else if (controlsUnlock) {
      _tapGestureRecognizer.addPointer(event);
      _doubleTapGestureRecognizer.addPointer(event);
      longPressRecognizer.addPointer(event);
      _scaleGestureRecognizer.addPointer(event);
    }
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (plPlayerController.controlsLock.value) return;
    if (_gestureType == null) {
      final pan = event.pan;
      if (pan.distanceSquared < 1) return;
      final dx = pan.dx.abs();
      final dy = pan.dy.abs();
      if (dx > 3 * dy) {
        _gestureType = GestureType.horizontal;
      } else if (dy > 3 * dx) {
        _gestureType = GestureType.right;
      }
      return;
    }

    if (_gestureType == GestureType.horizontal) {
      final delta = event.localPanDelta;
      final int curSliderPosition =
          plPlayerController.sliderPosition.inMilliseconds;
      final int newPos =
          (curSliderPosition +
                  (plPlayerController.sliderScale * delta.dx / maxWidth)
                      .round())
              .clamp(0, plPlayerController.duration.value.inMilliseconds);
      final Duration result = Duration(milliseconds: newPos);
      if (plPlayerController.cancelSeek == true) {
        plPlayerController
          ..cancelSeek = null
          ..hasToast = null;
      }
      plPlayerController
        ..onUpdatedSliderProgress(result)
        ..onChangedSliderStart();
    } else if (_gestureType == GestureType.right) {
      if (!plPlayerController.enableSlideVolumeBrightness) {
        return;
      }

      final double level = maxHeight * 0.5;
      EasyThrottle.throttle(
        'setVolume',
        const Duration(milliseconds: 20),
        () {
          final double volume = clampDouble(
            plPlayerController.volume.value - event.localPanDelta.dy / level,
            0.0,
            plPlayerController.maxVolume,
          );
          plPlayerController.setVolume(volume);
        },
      );
    }
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    if (plPlayerController.isSliderMoving.value) {
      plPlayerController
        ..seekTo(plPlayerController.sliderPosition, isSeek: false)
        ..onChangedSliderEnd();
    }
    _gestureType = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final offset = -event.scrollDelta.dy / 4000;
      final volume = clampDouble(
        plPlayerController.volume.value + offset,
        0.0,
        plPlayerController.maxVolume,
      );
      plPlayerController.setVolume(volume);
    }
  }

  // ===== 主构建方法 =====
  @override
  Widget build(BuildContext context) {
    debugPrint('[PLVideoPlayer] build called, engine=${PlayerPref.playerEngine}');
    maxWidth = widget.maxWidth;
    maxHeight = widget.maxHeight;
    final isFullScreen = this.isFullScreen;
    final bool isFvpEngine = PlayerPref.playerEngine == PlayerEngineType.fvp;
    final primary = isFullScreen && colorScheme.brightness == Brightness.light
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    late final thumbGlowColor = primary.withAlpha(80);
    late final bufferedBarColor = primary.withValues(alpha: 0.4);
    const TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
    );

    final child = Stack(
      fit: StackFit.passthrough,
      key: _playerKey,
      children: <Widget>[
        // ----- 视频层 -----
        _videoWidget,

        // ----- 弹幕层 -----
        if (widget.danmuWidget case final danmaku?)
          Positioned.fill(top: 4, child: danmaku),

        // ----- 字幕层 -----
        if (!isFvpEngine && videoController != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Obx(
                () => SubtitleView(
                  controller: videoController!,
                  configuration: plPlayerController.subtitleConfig.value,
                ),
              ),
            ),
          ),

        // ----- 长按倍速 Toast -----
        IgnorePointer(
          ignoring: true,
          child: Align(
            alignment: Alignment.topCenter,
            child: FractionalTranslation(
              translation: isFullScreen
                  ? const Offset(0.0, 1.2)
                  : const Offset(0.0, 0.8),
              child: Obx(
                () => AnimatedOpacity(
                  curve: Curves.easeInOut,
                  opacity: plPlayerController.longPressStatus.value
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0x88000000),
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Obx(
                      () {
                        // 强制依赖，即使不用
                        final _ = plPlayerController.longPressStatus.value;
                        return Text(
                          '${plPlayerController.enableAutoLongPressSpeed ? (plPlayerController.longPressStatus.value ? plPlayerController.lastPlaybackSpeed : plPlayerController.playbackSpeed) * 2 : plPlayerController.longPressSpeed}倍速中',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ----- 时间进度 Toast -----
        IgnorePointer(
          ignoring: true,
          child: Align(
            alignment: Alignment.topCenter,
            child: FractionalTranslation(
              translation: isFullScreen
                  ? const Offset(0.0, 1.2)
                  : const Offset(0.0, 0.8),
              child: Obx(
                () => AnimatedOpacity(
                  curve: Curves.easeInOut,
                  opacity: plPlayerController.isSliderMoving.value
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0x88000000),
                      borderRadius: BorderRadius.all(Radius.circular(64)),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      spacing: 2,
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Obx(() {
                          return Text(
                            DurationUtils.formatDuration(
                              plPlayerController
                                  .sliderTempPosition
                                  .value
                                  .inSeconds,
                            ),
                            style: textStyle,
                          );
                        }),
                        const Text('/', style: textStyle),
                        Obx(
                          () {
                            return Text(
                              DurationUtils.formatDuration(
                                plPlayerController.duration.value.inSeconds,
                              ),
                              style: textStyle,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ----- 音量控制条 -----
        IgnorePointer(
          ignoring: true,
          child: Align(
            alignment: Alignment.center,
            child: Obx(
              () {
                final volume = plPlayerController.volume.value;
                return AnimatedOpacity(
                  curve: Curves.easeInOut,
                  opacity: plPlayerController.volumeIndicator.value ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0x88000000),
                      borderRadius: BorderRadius.all(Radius.circular(64)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          volume == 0.0
                              ? Icons.volume_off
                              : volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                          color: Colors.white,
                          size: 20.0,
                        ),
                        const SizedBox(width: 2.0),
                        Text(
                          '${(volume * 100.0).round()}%',
                          style: const TextStyle(
                            fontSize: 13.0,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // ----- 亮度控制条 -----
        IgnorePointer(
          ignoring: true,
          child: Align(
            alignment: Alignment.center,
            child: Obx(
              () => AnimatedOpacity(
                curve: Curves.easeInOut,
                opacity: _brightnessIndicator.value ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0x88000000),
                    borderRadius: BorderRadius.all(Radius.circular(64)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        _brightnessValue.value < 1.0 / 3.0
                            ? Icons.brightness_low
                            : _brightnessValue.value < 2.0 / 3.0
                            ? Icons.brightness_medium
                            : Icons.brightness_high,
                        color: Colors.white,
                        size: 18.0,
                      ),
                      const SizedBox(width: 2.0),
                      Text(
                        '${(_brightnessValue.value * 100.0).round()}%',
                        style: const TextStyle(
                          fontSize: 13.0,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ============================================================
        // ===== 控制栏 =====
        if (isFvpEngine) ...[
          Positioned.fill(
            top: -1,
            bottom: -1,
            child: ClipRect(
              child: RepaintBoundary(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AppBarAni(
                      isTop: true,
                      controller: _animationController,
                      isFullScreen: isFullScreen,
                      removeSafeArea: plPlayerController.removeSafeArea,
                      child: plPlayerController.isDesktopPip
                          ? GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onPanStart: (_) => windowManager.startDragging(),
                              child: widget.headerControl,
                            )
                          : widget.headerControl,
                    ),
                    if (!plPlayerController.isDesktopPip)
                      AppBarAni(
                        isTop: false,
                        controller: _animationController,
                        isFullScreen: isFullScreen,
                        removeSafeArea: plPlayerController.removeSafeArea,
                        child: widget.bottomControl ??
                            BottomControl(
                              maxWidth: maxWidth,
                              isFullScreen: isFullScreen,
                              controller: plPlayerController,
                              buildBottomControl: () => buildBottomControl(maxWidth > maxHeight),
                            ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ] else ...[
          Positioned.fill(
            top: -1,
            bottom: -1,
            child: ClipRect(
              child: RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AppBarAni(
                      isTop: true,
                      controller: _animationController,
                      isFullScreen: isFullScreen,
                      removeSafeArea: plPlayerController.removeSafeArea,
                      child: plPlayerController.isDesktopPip
                          ? GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onPanStart: (_) => windowManager.startDragging(),
                              child: widget.headerControl,
                            )
                          : widget.headerControl,
                    ),
                    AppBarAni(
                      isTop: false,
                      controller: _animationController,
                      isFullScreen: isFullScreen,
                      removeSafeArea: plPlayerController.removeSafeArea,
                      child: widget.bottomControl ??
                          BottomControl(
                            maxWidth: maxWidth,
                            isFullScreen: isFullScreen,
                            controller: plPlayerController,
                            buildBottomControl: () => buildBottomControl(maxWidth > maxHeight),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        // ----- 还原屏幕按钮 -----
        Obx(
          () =>
              showRestoreScaleBtn.value && plPlayerController.showControls.value
              ? Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 95),
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: colorScheme.secondaryContainer
                            .withValues(alpha: 0.8),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(15),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(6),
                          ),
                        ),
                      ),
                      onPressed: () async {
                        showRestoreScaleBtn.value = false;
                        final animController = AnimationController(
                          vsync: this,
                          duration: const Duration(milliseconds: 255),
                        );
                        final anim = animController.drive(
                          Matrix4Tween(
                            begin: _transformationController.value,
                            end: Matrix4.identity(),
                          ).chain(CurveTween(curve: Curves.easeOut)),
                        );
                        void listener() {
                          _transformationController.value = anim.value;
                        }

                        animController.addListener(listener);
                        await animController.forward(from: 0);
                        animController
                          ..removeListener(listener)
                          ..dispose();
                      },
                      child: const Text('还原屏幕'),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ----- 进度条 -----
        // if (!plPlayerController.isDesktopPip)
        Positioned(
          bottom: -2.2,
          left: 0,
          right: 0,
          child: Obx(
            () {
              final showControls = plPlayerController.showControls.value;
              final bool offstage;
              switch (plPlayerController.progressType) {
                case 0:
                  offstage = showControls;
                case 1:
                  if (!plPlayerController.isSliderMoving.value) {
                    return const SizedBox.shrink();
                  }
                  offstage = showControls;
                case 2:
                  offstage =
                      showControls ||
                      (!isFullScreen &&
                          !plPlayerController.isSliderMoving.value);
                case 3:
                  offstage =
                      showControls ||
                      (isFullScreen &&
                          !plPlayerController.isSliderMoving.value);
                default:
                  offstage = showControls;
              }
              return Offstage(
                offstage: offstage,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Obx(() {
                      final int value =
                          plPlayerController.sliderPositionSeconds.value;
                      final int max =
                          plPlayerController.duration.value.inSeconds;
                      final int buffer =
                          plPlayerController.bufferedSeconds.value;
                      return ProgressBar(
                        progress: Duration(seconds: value),
                        buffered: Duration(seconds: buffer),
                        total: Duration(seconds: max),
                        progressBarColor: primary,
                        baseBarColor: const Color(0x33FFFFFF),
                        bufferedBarColor: bufferedBarColor,
                        thumbColor: primary,
                        thumbGlowColor: thumbGlowColor,
                        barHeight: 3.5,
                        thumbRadius: 2.5,
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),

        // ----- 全屏锁和截图按钮 -----
        if (isFullScreen || plPlayerController.isDesktopPip) ...[
          if (plPlayerController.showFsLockBtn)
            ViewSafeArea(
              right: false,
              left: !plPlayerController.removeSafeArea,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionalTranslation(
                  translation: const Offset(1, -0.4),
                  child: Obx(
                    () => Offstage(
                      offstage: !plPlayerController.showControls.value,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0x45000000),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Obx(() {
                          final controlsLock =
                              plPlayerController.controlsLock.value;
                          return ComBtn(
                            tooltip: controlsLock ? '解锁' : '锁定',
                            icon: controlsLock
                                ? const Icon(
                                    FontAwesomeIcons.lock,
                                    size: 15,
                                    color: Colors.white,
                                  )
                                : const Icon(
                                    FontAwesomeIcons.lockOpen,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                            onTap: () =>
                                plPlayerController.onLockControl(!controlsLock),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (isFullScreen && PlayerPref.showBatteryLevel)
            ViewSafeArea(
              left: false,
              right: !plPlayerController.removeSafeArea,
              child: Align(
                alignment: Alignment.topRight,
                child: FractionalTranslation(
                  translation: const Offset(-0.1, 0.1),
                  child: Obx(() {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.battery_4_bar,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            plPlayerController.batteryLevel.value,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),

          if (plPlayerController.showFsScreenshotBtn)
            ViewSafeArea(
              left: false,
              right: !plPlayerController.removeSafeArea,
              child: Obx(
                () => Align(
                  alignment: Alignment.centerRight,
                  child: FractionalTranslation(
                    translation: const Offset(-1, -0.4),
                    child: Offstage(
                      offstage: !plPlayerController.showControls.value,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0x45000000),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: ComBtn(
                          tooltip: '截图',
                          icon: const Icon(
                            Icons.photo_camera,
                            size: 20,
                            color: Colors.white,
                          ),
                          onTap: plPlayerController.takeScreenshot,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],

        // ----- 加载中 -----
        Obx(() {
          final isDataLoading = plPlayerController.dataStatus.value == DataStatus.loading;
          final isPlayerPlaying = plPlayerController.playerStatus.value.isPlaying;
          if (isDataLoading ||
              (plPlayerController.isBuffering.value && isPlayerPlaying)) {
            return Center(
              child: GestureDetector(
                onTap: plPlayerController.refreshPlayer,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Colors.black26, Colors.transparent],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        Assets.buffering,
                        height: 25,
                        cacheHeight: 25.cacheSize(context),
                        semanticLabel: "加载中",
                        color: Colors.white,
                      ),
                      if (plPlayerController.isBuffering.value)
                        Obx(() {
                          if (plPlayerController.bufferedSeconds.value == 0) {
                            return const Text(
                              '加载中...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            );
                          }
                          String bufferStr = plPlayerController.buffered
                              .toString();
                          return Text(
                            bufferStr.substring(0, bufferStr.length - 3),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            );
          } else {
            return const SizedBox.shrink();
          }
        }),

        // ----- 快进/快退 -----
        Obx(() {
          final mountSeekBackwardButton =
              plPlayerController.mountSeekBackwardButton.value;
          final mountSeekForwardButton =
              plPlayerController.mountSeekForwardButton.value;
          return mountSeekBackwardButton || mountSeekForwardButton
              ? Positioned.fill(
                  child: Row(
                    children: [
                      if (mountSeekBackwardButton)
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 500),
                            builder: (context, value, child) => Opacity(
                              opacity: value,
                              child: child,
                            ),
                            child: BackwardSeekIndicator(
                              duration:
                                  plPlayerController.fastForBackwardDuration,
                              onSubmitted: (Duration value) {
                                plPlayerController
                                  ..mountSeekBackwardButton.value = false
                                  ..onBackward(value);
                              },
                            ),
                          ),
                        ),
                      const Spacer(flex: 2),
                      if (mountSeekForwardButton)
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 500),
                            builder: (context, value, child) => Opacity(
                              opacity: value,
                              child: child,
                            ),
                            child: ForwardSeekIndicator(
                              duration:
                                  plPlayerController.fastForBackwardDuration,
                              onSubmitted: (Duration value) {
                                plPlayerController
                                  ..mountSeekForwardButton.value = false
                                  ..onForward(value);
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink();
        }),
      ],
    );

    if (PlatformUtils.isDesktop) {
      return Obx(
        () {
          final showControls = plPlayerController.showControls.value;
          final fullScreen = plPlayerController.isFullScreen.value;
          return MouseRegion(
            cursor: !showControls && fullScreen
                ? SystemMouseCursors.none
                : MouseCursor.defer,
            onEnter: (_) => plPlayerController.controls = true,
            onHover: (_) => plPlayerController.controls = true,
            onExit: (_) => plPlayerController.controls = false,
            child: child,
          );
        },
      );
    }
    return child;
  }

  Widget get _videoWidget {
    return Container(
      width: widget.maxWidth,
      height: widget.maxHeight,
      clipBehavior: Clip.none,
      color: widget.fill,
      child: MouseInteractiveViewer(
        scaleEnabled: !plPlayerController.controlsLock.value,
        pointerSignalFallback: _onPointerSignal,
        onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
        onPointerPanZoomEnd: _onPointerPanZoomEnd,
        onPointerDown: _onPointerDown,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onScaleUpdate: _onScaleUpdate,
        scaleGestureRecognizer: _scaleGestureRecognizer,
        panEnabled: false,
        minScale: plPlayerController.enableShrinkVideoSize ? 0.75 : 1,
        maxScale: 2.0,
        boundaryMargin: plPlayerController.enableShrinkVideoSize
            ? const EdgeInsets.all(double.infinity)
            : EdgeInsets.zero,
        panAxis: PanAxis.aligned,
        transformationController: _transformationController,
        childKey: _videoKey,
        child: RepaintBoundary(
          key: _videoKey,
          child: Obx(
            () {
              final videoFit = plPlayerController.videoFit.value;
              return plPlayerController.buildVideoWidget(
                fit: videoFit.boxFit,
                flipX: plPlayerController.flipX.value,
                flipY: plPlayerController.flipY.value,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 视频时间显示
class _VideoTime extends LeafRenderObjectWidget {
  const _VideoTime({
    required this.position,
    required this.duration,
  });

  final String position;
  final String duration;

  @override
  _RenderVideoTime createRenderObject(BuildContext context) => _RenderVideoTime(
    position: position,
    duration: duration,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderVideoTime renderObject,
  ) {
    renderObject
      ..position = position
      ..duration = duration;
  }
}

class _RenderVideoTime extends RenderBox {
  _RenderVideoTime({
    required this._position,
    required this._duration,
  });

  String _duration;
  set duration(String value) {
    _duration = value;
    final paragraph = _buildParagraph(const ui.Color(0xFFD0D0D0), _duration);
    if (paragraph.maxIntrinsicWidth != _cache?.maxIntrinsicWidth) {
      markNeedsLayout();
    }
    _cache?.dispose();
    _cache = paragraph;
    markNeedsSemanticsUpdate();
  }

  String _position;
  set position(String value) {
    _position = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  ui.Paragraph? _cache;

  ui.Paragraph _buildParagraph(ui.Color color, String time) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: 10,
        height: 1.4,
        fontFamily: 'Monospace',
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontSize: 10,
          height: 1.4,
          fontFamily: 'Monospace',
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      )
      ..addText(time);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  @override
  ui.Size computeDryLayout(covariant BoxConstraints constraints) {
    final paragraph = _cache ??= _buildParagraph(
      const ui.Color(0xFFD0D0D0),
      _duration,
    );
    return ui.Size(paragraph.maxIntrinsicWidth, paragraph.height * 2);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.label = 'position:$_position\nduration:$_duration';
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paint(PaintingContext context, ui.Offset offset) {
    final para = _buildParagraph(Colors.white, _position);
    context.canvas
      ..drawParagraph(
        para,
        ui.Offset(
          offset.dx + _cache!.maxIntrinsicWidth - para.maxIntrinsicWidth,
          offset.dy,
        ),
      )
      ..drawParagraph(_cache!, ui.Offset(offset.dx, offset.dy + para.height));
    para.dispose();
  }

  @override
  void dispose() {
    _cache?.dispose();
    _cache = null;
    super.dispose();
  }

  @override
  bool get isRepaintBoundary => true;
}