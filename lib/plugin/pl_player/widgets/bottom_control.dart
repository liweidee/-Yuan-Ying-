import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:yuanying/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/utils/feed_back.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

/// 播放器底部控制栏（不含预览功能）
class BottomControl extends StatelessWidget {
  const BottomControl({
    super.key,
    required this.maxWidth,
    required this.isFullScreen,
    required this.controller,
    required this.buildBottomControl,
  });

  final double maxWidth;
  final bool isFullScreen;
  final PlPlayerController controller;
  final ValueGetter<Widget> buildBottomControl;

  void onDragStart(ThumbDragDetails duration) {
    feedBack();
    controller.onChangedSliderStart(duration.timeStamp);
  }

  void onDragUpdate(ThumbDragDetails duration) {
    // 预览功能已移除，只更新进度
    controller.onUpdatedSliderProgress(duration.timeStamp);
  }

  void onSeek(Duration duration) {
    controller
      ..onChangedSliderEnd()
      ..onChangedSlider(duration.inSeconds)
      ..seekTo(Duration(seconds: duration.inSeconds), isSeek: false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final primary = colorScheme.brightness == Brightness.light
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    final thumbGlowColor = primary.withAlpha(80);
    final bufferedBarColor = primary.withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
            child: Obx(() {
              // 直接读取存储值
              final int progressType = PlayerPref.btmProgressBehavior;
              final bool showControls = controller.showControls.value;
              final bool isSliderMoving = controller.isSliderMoving.value;
              final bool isFullScreen = controller.isFullScreen.value;

              bool offstage;
              switch (progressType) {
                case 0: // 始终展示
                  offstage = !showControls;
                  break;
                case 1: // 始终隐藏
                  if (!isSliderMoving) {
                    return const SizedBox.shrink();
                  }
                  offstage = !showControls;
                  break;
                case 2: // 仅全屏时展示
                  offstage = !showControls || (!isFullScreen && !isSliderMoving);
                  break;
                case 3: // 仅全屏时隐藏
                  offstage = !showControls || (isFullScreen && !isSliderMoving);
                  break;
                default:
                  offstage = !showControls;
              }

              return Offstage(
                offstage: offstage,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Obx(() {
                      final int value = controller.sliderPositionSeconds.value;
                      final int max = controller.duration.value.inSeconds;
                      return ProgressBar(
                        progress: Duration(seconds: value),
                        buffered: Duration(seconds: controller.bufferedSeconds.value),
                        total: Duration(seconds: max),
                        progressBarColor: Theme.of(context).brightness == Brightness.light
                            ? Theme.of(context).colorScheme.inversePrimary
                            : Theme.of(context).colorScheme.primary,
                        baseBarColor: const Color(0x33FFFFFF),
                        bufferedBarColor: Theme.of(context).brightness == Brightness.light
                            ? Theme.of(context).colorScheme.inversePrimary.withAlpha(80)
                            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                        thumbColor: Theme.of(context).brightness == Brightness.light
                            ? Theme.of(context).colorScheme.inversePrimary
                            : Theme.of(context).colorScheme.primary,
                        thumbGlowColor: Theme.of(context).brightness == Brightness.light
                            ? Theme.of(context).colorScheme.inversePrimary.withAlpha(80)
                            : Theme.of(context).colorScheme.primary.withAlpha(80),
                        barHeight: 3.5,
                        thumbRadius: 7,
                        thumbGlowRadius: 25,
                        onDragStart: (details) {
                          feedBack();
                          controller.onChangedSliderStart(details.timeStamp);
                        },
                        onDragUpdate: (details) {
                          controller.onUpdatedSliderProgress(details.timeStamp);
                        },
                        onSeek: (duration) {
                          controller
                            ..onChangedSliderEnd()
                            ..onChangedSlider(duration.inSeconds)
                            ..seekTo(Duration(seconds: duration.inSeconds), isSeek: false);
                        },
                      );
                    }),
                  ],
                ),
              );
            }),
          ),
          buildBottomControl(),
        ],
      ),
    );
  }
}