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

/// 播放器键盘快捷键焦点组件
/// 支持桌面端键盘操作：空格、F、方向键、M静音、S截图、L锁屏、括号切换剧集等
class PlayerFocus extends StatelessWidget {
  const PlayerFocus({
    super.key,
    required this.child,
    required this.plPlayerController,
    required this.controllerTag,
    this.onSendDanmaku,
  });

  final Widget child;
  final PlPlayerController plPlayerController;
  final String controllerTag;
  final VoidCallback? onSendDanmaku;

  static bool _shouldHandle(LogicalKeyboardKey logicalKey) {
    return logicalKey == LogicalKeyboardKey.tab ||
        logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.arrowDown;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // 检查键盘控制是否启用
        if (!PlayerPref.keyboardControl) {
          return KeyEventResult.ignored;
        }
        final handled = _handleKey(event);
        if (handled || _shouldHandle(event.logicalKey)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  bool get isFullScreen => plPlayerController.isFullScreen.value;
  bool get hasPlayer => plPlayerController.videoPlayerController != null;

  void _setVolume({required bool isIncrease}) {
    final volume = isIncrease
        ? (plPlayerController.volume.value + 0.1).clamp(0.0, plPlayerController.maxVolume)
        : (plPlayerController.volume.value - 0.1).clamp(0.0, plPlayerController.maxVolume);
    plPlayerController.setVolume(volume);
  }

  void _updateVolume(KeyEvent event, {required bool isIncrease}) {
    if (event is KeyDownEvent) {
      if (hasPlayer) {
        _setVolume(isIncrease: isIncrease);
        plPlayerController
          ..longPressTimer?.cancel()
          ..longPressTimer = Timer.periodic(
            const Duration(milliseconds: 150),
            (_) => _setVolume(isIncrease: isIncrease),
          );
      }
    } else if (event is KeyUpEvent) {
      plPlayerController.cancelLongPressTimer();
    }
  }

  bool _handleKey(KeyEvent event) {
    final key = event.logicalKey;

    // Q / R：无操作（原三连，已移除）
    if (key == LogicalKeyboardKey.keyQ || key == LogicalKeyboardKey.keyR) {
      if (HardwareKeyboard.instance.isMetaPressed) {
        if (key == LogicalKeyboardKey.keyQ && Platform.isMacOS) {
          exit(0);
        }
        return true;
      }
      return true;
    }

    // 上下键调音量
    final isArrowUp = key == LogicalKeyboardKey.arrowUp;
    if (isArrowUp || key == LogicalKeyboardKey.arrowDown) {
      _updateVolume(event, isIncrease: isArrowUp);
      return true;
    }

    // 左右键快进/快退（长按连续）
    if (key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent) {
        if (hasPlayer && !plPlayerController.longPressStatus.value) {
          plPlayerController
            ..longPressTimer?.cancel()
            ..longPressTimer = Timer(
              const Duration(milliseconds: 200),
              () => plPlayerController
                ..cancelLongPressTimer()
                ..setLongPressStatus(true),
            );
        }
      } else if (event is KeyUpEvent) {
        plPlayerController.cancelLongPressTimer();
        if (hasPlayer) {
          if (plPlayerController.longPressStatus.value) {
            plPlayerController.setLongPressStatus(false);
          } else {
            plPlayerController.onForward(
              plPlayerController.fastForBackwardDuration,
            );
          }
        }
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (event is KeyDownEvent) {
        // 左键：后退，不触发长按倍速
        if (hasPlayer) {
          plPlayerController.onBackward(
            plPlayerController.fastForBackwardDuration,
          );
        }
        return true;
      }
      return true;
    }

    // 仅处理KeyDown事件
    if (event is! KeyDownEvent) return false;

    // 数字键：1恢复速度，2两倍速（Shift+数字）
    final isDigit1 = key == LogicalKeyboardKey.digit1;
    if (isDigit1 || key == LogicalKeyboardKey.digit2) {
      if (HardwareKeyboard.instance.isShiftPressed && hasPlayer) {
        final speed = isDigit1 ? 1.0 : 2.0;
        if (speed != plPlayerController.playbackSpeed) {
          plPlayerController.setPlaybackSpeed(speed);
        }
        SmartDialog.showToast('${speed}x播放');
      }
      return true;
    }

    switch (key) {
      case LogicalKeyboardKey.space:
        if (hasPlayer) {
          plPlayerController.onDoubleTapCenter();
        }
        return true;

      case LogicalKeyboardKey.keyF:
        final isFullScreen = this.isFullScreen;
        if (isFullScreen && plPlayerController.controlsLock.value) {
          plPlayerController
            ..controlsLock.value = false
            ..showControls.value = false;
        }
        plPlayerController.triggerFullScreen(
          status: !isFullScreen,
          inAppFullScreen: HardwareKeyboard.instance.isShiftPressed,
        );
        return true;

      case LogicalKeyboardKey.keyD:
        plPlayerController.toggleDanmaku();
        return true;

      case LogicalKeyboardKey.keyP:
        if (PlatformUtils.isDesktop && hasPlayer && !isFullScreen) {
          plPlayerController.toggleDesktopPip();
        }
        return true;

      case LogicalKeyboardKey.keyM:
        if (hasPlayer) {
          final isMuted = !plPlayerController.isMuted;
          plPlayerController.videoPlayerController!.setVolume(
            isMuted ? 0 : plPlayerController.volume.value * 100,
          );
          plPlayerController.isMuted = isMuted;
          SmartDialog.showToast('${isMuted ? '' : '取消'}静音');
        }
        return true;

      case LogicalKeyboardKey.keyS:
        if (hasPlayer && isFullScreen) {
          plPlayerController.takeScreenshot();
        }
        return true;

      case LogicalKeyboardKey.keyL:
        if (isFullScreen || plPlayerController.isDesktopPip) {
          plPlayerController.onLockControl(
            !plPlayerController.controlsLock.value,
          );
        }
        return true;

      case LogicalKeyboardKey.enter:
        if (onSendDanmaku != null) {
          onSendDanmaku!();
        }
        return true;

      // 括号键切换剧集
      case LogicalKeyboardKey.bracketLeft:
        _switchEpisode(prev: true);
        return true;

      case LogicalKeyboardKey.bracketRight:
        _switchEpisode(prev: false);
        return true;

      default:
        return false;
    }
  }

  void _switchEpisode({required bool prev}) {
    try {
      final detailController = Get.find<DetailController>(tag: controllerTag);
      if (prev) {
        detailController.playPrev().then((success) {
          if (!success) {
            SmartDialog.showToast('已经是第一集了');
          }
        });
      } else {
        detailController.playNext().then((success) {
          if (!success) {
            SmartDialog.showToast('已经是最后一集了');
          }
        });
      }
    } catch (_) {
      // 忽略
    }
  }
}