import 'dart:async';
import 'dart:io' show exit, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyUpEvent, LogicalKeyboardKey, HardwareKeyboard;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

/// 播放器键盘快捷键处理。
///
/// 由 PLVideoPlayer (view.dart) 中已有的 Focus 节点调用。
/// **不提供 Widget**，避免多个焦点节点竞争（历史问题的根因）。
///
/// 调用方（view.dart 的 Focus.onKeyEvent）保证：
/// - ESC 由调用方单独处理（全屏时退出全屏）
/// - SmartDialog 打开、焦点在输入框时调用方已短路
///
/// 返回 true 表示事件已被消费。
bool handlePlaybackShortcut(
  KeyEvent event, {
  required PlPlayerController controller,
  required String controllerTag,
  VoidCallback? onSendDanmaku,
}) {
  final key = event.logicalKey;
  final hasPlayer = controller.videoPlayerController != null;

  // Q/R：保留防误触
  if (key == LogicalKeyboardKey.keyQ || key == LogicalKeyboardKey.keyR) {
    if (HardwareKeyboard.instance.isMetaPressed &&
        key == LogicalKeyboardKey.keyQ &&
        Platform.isMacOS) {
      exit(0);
    }
    return true;
  }

  // 上下键：音量
  final isArrowUp = key == LogicalKeyboardKey.arrowUp;
  if (isArrowUp || key == LogicalKeyboardKey.arrowDown) {
    _handleVolumeKey(event, controller: controller, isIncrease: isArrowUp);
    return true;
  }

  // 右键：快进（长按倍速）
  if (key == LogicalKeyboardKey.arrowRight) {
    _handleFastForwardKey(event, controller: controller);
    return true;
  }

  // 左键：快退
  if (key == LogicalKeyboardKey.arrowLeft) {
    if (event is KeyDownEvent && hasPlayer) {
      controller.onBackward(controller.fastForBackwardDuration);
    }
    return true;
  }

  // 之后只处理 KeyDown
  if (event is! KeyDownEvent) return false;

  // Shift+1 / Shift+2：切换倍速
  final isDigit1 = key == LogicalKeyboardKey.digit1;
  if (isDigit1 || key == LogicalKeyboardKey.digit2) {
    if (HardwareKeyboard.instance.isShiftPressed && hasPlayer) {
      final speed = isDigit1 ? 1.0 : 2.0;
      if (speed != controller.playbackSpeed) {
        controller.setPlaybackSpeed(speed);
      }
      SmartDialog.showToast('${speed}x播放');
    }
    return true;
  }

  switch (key) {
    case LogicalKeyboardKey.space:
      if (hasPlayer) controller.onDoubleTapCenter();
      return true;

    case LogicalKeyboardKey.keyF:
      if (controller.isFullScreen.value && controller.controlsLock.value) {
        controller
          ..controlsLock.value = false
          ..showControls.value = false;
      }
      controller.triggerFullScreen(
        status: !controller.isFullScreen.value,
        inAppFullScreen: HardwareKeyboard.instance.isShiftPressed,
      );
      return true;

    case LogicalKeyboardKey.keyD:
      controller.toggleDanmaku();
      return true;

    case LogicalKeyboardKey.keyP:
      if (PlatformUtils.isDesktop &&
          hasPlayer &&
          !controller.isFullScreen.value) {
        controller.toggleDesktopPip();
      }
      return true;

    case LogicalKeyboardKey.keyM:
      if (hasPlayer) {
        final isMuted = !controller.isMuted;
        controller.videoPlayerController!.setVolume(
          isMuted ? 0 : controller.volume.value * 100,
        );
        controller.isMuted = isMuted;
        SmartDialog.showToast('${isMuted ? '' : '取消'}静音');
      }
      return true;

    case LogicalKeyboardKey.keyS:
      if (hasPlayer && controller.isFullScreen.value) {
        controller.takeScreenshot();
      }
      return true;

    case LogicalKeyboardKey.keyL:
      if (controller.isFullScreen.value || controller.isDesktopPip) {
        controller.onLockControl(!controller.controlsLock.value);
      }
      return true;

    case LogicalKeyboardKey.enter:
      onSendDanmaku?.call();
      return true;

    case LogicalKeyboardKey.bracketLeft:
      _switchEpisode(controllerTag, prev: true);
      return true;

    case LogicalKeyboardKey.bracketRight:
      _switchEpisode(controllerTag, prev: false);
      return true;

    default:
      return false;
  }
}

/// 上下键音量：KeyDown 首次触发 + 定时重复，KeyUp 停止
void _handleVolumeKey(
  KeyEvent event, {
  required PlPlayerController controller,
  required bool isIncrease,
}) {
  if (event is KeyUpEvent) {
    controller.cancelLongPressTimer();
    return;
  }
  if (event is! KeyDownEvent) return;
  if (controller.videoPlayerController == null) return;

  void adjust() {
    final v = isIncrease
        ? (controller.volume.value + 0.1).clamp(0.0, controller.maxVolume)
        : (controller.volume.value - 0.1).clamp(0.0, controller.maxVolume);
    controller.setVolume(v);
  }

  adjust();
  controller
    ..longPressTimer?.cancel()
    ..longPressTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => adjust(),
    );
}

/// 右键快进：短按走固定时长，长按 200ms 后进入倍速状态
void _handleFastForwardKey(
  KeyEvent event, {
  required PlPlayerController controller,
}) {
  final hasPlayer = controller.videoPlayerController != null;

  if (event is KeyDownEvent) {
    if (hasPlayer && !controller.longPressStatus.value) {
      controller
        ..longPressTimer?.cancel()
        ..longPressTimer = Timer(
          const Duration(milliseconds: 200),
          () => controller
            ..cancelLongPressTimer()
            ..setLongPressStatus(true),
        );
    }
  } else if (event is KeyUpEvent) {
    controller.cancelLongPressTimer();
    if (hasPlayer) {
      if (controller.longPressStatus.value) {
        controller.setLongPressStatus(false);
      } else {
        controller.onForward(controller.fastForBackwardDuration);
      }
    }
  }
}

/// 括号键切换上下集
void _switchEpisode(String controllerTag, {required bool prev}) {
  try {
    final detailController = Get.find<DetailController>(tag: controllerTag);
    if (prev) {
      detailController.playPrev().then((s) {
        if (!s) SmartDialog.showToast('已经是第一集了');
      });
    } else {
      detailController.playNext().then((s) {
        if (!s) SmartDialog.showToast('已经是最后一集了');
      });
    }
  } catch (_) {}
}