import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// 加载进度环
class LoadingIndicator extends LeafRenderObjectWidget {
  const LoadingIndicator({
    super.key,
    required this.size,
    required this.progress,
  });

  final double size;
  final double progress;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLoadingIndicator(
      preferredSize: size,
      progress: progress,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLoadingIndicator renderObject,
  ) {
    renderObject
      ..preferredSize = size
      ..progress = progress;
  }
}

class RenderLoadingIndicator extends RenderBox {
  RenderLoadingIndicator({
    required this._preferredSize,
    required this._progress,
  });

  double _preferredSize;
  double get preferredSize => _preferredSize;
  set preferredSize(double value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  double _progress;
  double get progress => _progress;
  set progress(double value) {
    if (_progress == value) return;
    _progress = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void performLayout() {
    size = constraints.constrainDimensions(_preferredSize, _preferredSize);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_progress == 0) {
      return;
    }
    const padding = 8.0;
    const strokeWidth = 1.4;
    const startAngle = -pi / 2;

    final paint = Paint()..isAntiAlias = true;
    final size = this.size;
    final radius = size.width / 2 - strokeWidth;
    final center = size.center(Offset.zero);

    context.canvas
      ..drawCircle(
        center,
        radius,
        paint
          ..style = PaintingStyle.fill
          ..color = const Color(0x80000000),
      )
      ..drawCircle(
        center,
        radius,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = Colors.white,
      )
      ..drawArc(
        Rect.fromCircle(center: center, radius: radius - padding),
        startAngle,
        progress * 2 * pi,
        true,
        paint..style = PaintingStyle.fill,
      );
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..role = SemanticsRole.progressBar
      ..minValue = '0'
      ..maxValue = '100'
      ..value = (_progress * 100).round().toString();
  }

  @override
  bool get isRepaintBoundary => true;
}