import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/danmaku/controllers/danmaku_controller.dart';
import 'package:yuanying/modules/danmaku/models/danmaku_model.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/plugin/pl_player/models/play_status.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/plugin/pl_player/utils/danmaku_options.dart';

class DanmakuView extends StatefulWidget {
  final PlPlayerController playerController;
  final DanmakuController danmakuController;
  final Size size;
  final bool isFullScreen;
  final bool isPipMode;

  const DanmakuView({
    super.key,
    required this.playerController,
    required this.danmakuController,
    required this.size,
    this.isFullScreen = false,
    this.isPipMode = false,
  });

  @override
  State<DanmakuView> createState() => _DanmakuViewState();
}

class _DanmakuViewState extends State<DanmakuView> {
  canvas.DanmakuController<DanmakuItem>? _canvasController;
  int _lastPosition = -1;

  bool get _notFullscreen => !widget.isFullScreen || widget.isPipMode;
  bool get _enabled => widget.playerController.enableShowDanmaku.value;

  late final void Function(PlayerStatus) _statusListener;

  @override
  void initState() {
    super.initState();
    _statusListener = _onStatus;
    widget.playerController.addPositionListener(_onPosition);
    widget.playerController.addStatusLister(_statusListener);
  }

  @override
  void dispose() {
    widget.playerController.removePositionListener(_onPosition);
    widget.playerController.removeStatusLister(_statusListener);
    // 不调用 clear，让 DanmakuScreen 自行清理
    _canvasController = null;
    _lastPosition = -1;
    super.dispose();
  }

  void _onStatus(PlayerStatus status) {
    if (!mounted) return;
    if (_canvasController == null) return;
    if (status.isPlaying) {
      _canvasController!.resume();
    } else {
      _canvasController!.pause();
    }
  }

  void _onPosition(Duration position) {
    if (!mounted) return;
    if (!_enabled) return;
    if (_canvasController == null) return;
    if (!widget.playerController.playerStatus.isPlaying) return;

    final progress = position.inMilliseconds;
    final key = (progress / 100).floor();
    if (key == _lastPosition) return;
    _lastPosition = key;

    final items = widget.danmakuController.getAt(progress);
    if (items != null && items.isNotEmpty) {
      final colorMode = PlayerPref.danmakuColorMode;
      for (final item in items) {
        Color textColor;
        if (colorMode == 1) {
          textColor = HSLColor.fromAHSL(1.0, Random().nextDouble() * 360, 1.0, 0.5).toColor();
        } else if (colorMode == 2) {
          final seconds = progress / 1000;
          final hue = (seconds * 12) % 360;
          textColor = HSLColor.fromAHSL(1.0, hue, 1.0, 0.5).toColor();
        } else {
          textColor = Color(item.opaqueColor);
        }
        _canvasController!.addDanmaku(
          canvas.DanmakuContentItem(
            item.content,
            color: textColor,
            type: _toDanmakuItemType(item.mode),
          ),
        );
      }
    }
  }

  canvas.DanmakuItemType _toDanmakuItemType(int mode) {
    switch (mode) {
      case 4:
        return canvas.DanmakuItemType.bottom;
      case 5:
        return canvas.DanmakuItemType.top;
      default:
        return canvas.DanmakuItemType.scroll;
    }
  }

  canvas.DanmakuOption _buildOption() {
    final double area = PlayerPref.danmakuShowArea;
    final double fontScale = _notFullscreen
        ? PlayerPref.danmakuFontScale
        : PlayerPref.danmakuFontScaleFS;
    final double fontSize = 15 * fontScale;
    final double duration = PlayerPref.danmakuDuration;
    final double staticDuration = PlayerPref.danmakuStaticDuration;
    final double strokeWidth = PlayerPref.danmakuStrokeWidth;
    final bool massiveMode = PlayerPref.danmakuMassiveMode;
    final bool static2Scroll = PlayerPref.danmakuStatic2Scroll;
    final bool fixedVelocity = PlayerPref.danmakuFixedV;
    final double lineHeight = PlayerPref.danmakuLineHeight;

    return canvas.DanmakuOption(
      fontSize: fontSize,
      area: area,
      duration: duration,
      staticDuration: staticDuration,
      hideBottom: false,
      hideScroll: false,
      hideTop: false,
      hideSpecial: false,
      strokeWidth: strokeWidth,
      scrollFixedVelocity: fixedVelocity,
      massiveMode: massiveMode,
      static2Scroll: static2Scroll,
      safeArea: true,
      lineHeight: lineHeight,
    );
  }

  @override
  void didUpdateWidget(DanmakuView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当全屏态或尺寸变化时，更新 Option（DanmakuScreen 内部会处理尺寸变化）
    if (oldWidget.isFullScreen != widget.isFullScreen ||
        oldWidget.isPipMode != widget.isPipMode ||
        oldWidget.size != widget.size) {
      _canvasController?.updateOption(_buildOption());
    }
  }

  @override
  Widget build(BuildContext context) {
    // 关键：不设 Key，不包裹 RepaintBoundary，让 DanmakuScreen 只创建一次并自然更新
    return Obx(
      () {
        final enabled = _enabled;
        final opacity = widget.playerController.danmakuOpacity.value;
        return AnimatedOpacity(
          opacity: enabled ? opacity : 0,
          duration: const Duration(milliseconds: 100),
          child: canvas.DanmakuScreen<DanmakuItem>(
            // 无 Key，让 Flutter 复用
            createdController: (e) {
              _canvasController = e;
              e.updateOption(_buildOption());
            },
            option: _buildOption(),
            size: widget.size,
          ),
        );
      },
    );
  }
}