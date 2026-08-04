import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:yuanying/models/common/card_layout_mode.dart';

abstract final class Grid {
  /// 根据布局模式获取卡片宽度
  static double getCardWidth(
    BuildContext context,
    CardLayoutMode mode,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    final spacing = 8.0;
    final padding = 16.0; // 左右边距

    switch (mode) {
      case CardLayoutMode.grid3:
        // 移动端：3列，宽度自适应
        if (width < 600) {
          return (width - padding * 2 - spacing * 2) / 3;
        } else if (width < 900) {
          return (width - padding * 2 - spacing * 3) / 4;
        } else {
          return (width - padding * 2 - spacing * 5) / 6;
        }
      case CardLayoutMode.grid2:
        if (width < 600) {
          return (width - padding * 2 - spacing * 1) / 2;
        } else if (width < 900) {
          return (width - padding * 2 - spacing * 2) / 3;
        } else {
          return (width - padding * 2 - spacing * 3) / 4;
        }
      case CardLayoutMode.list:
        return width - padding * 2;
    }
  }

  static SliverGridDelegateWithExtentAndRatio videoCardVDelegate(
    BuildContext context, {
    required CardLayoutMode mode,
    double minHeight = 25,
  }) {
    final cardWidth = getCardWidth(context, mode);
    final aspectRatio = 0.75;

    return SliverGridDelegateWithExtentAndRatio(
      mainAxisSpacing: 8.0,
      crossAxisSpacing: 8.0,
      maxCrossAxisExtent: cardWidth.clamp(80.0, 300.0),
      childAspectRatio: aspectRatio,
      mainAxisExtent: MediaQuery.textScalerOf(context).scale(minHeight),
    );
  }

  /// 判断是否为列表模式
  static bool isListMode(CardLayoutMode mode) {
    return mode == CardLayoutMode.list;
  }
}

// 保留 SliverGridDelegateWithExtentAndRatio 不变
class SliverGridDelegateWithExtentAndRatio extends SliverGridDelegate {
  SliverGridDelegateWithExtentAndRatio({
    required this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.childAspectRatio = 1.0,
    this.mainAxisExtent = 0.0,
    this.minHeight = 0.0,
  }) : assert(maxCrossAxisExtent > 0),
       assert(mainAxisSpacing >= 0),
       assert(crossAxisSpacing >= 0),
       assert(childAspectRatio > 0),
       assert(minHeight >= 0);

  final double minHeight;
  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final double mainAxisExtent;

  SliverGridLayout? _layoutCache;
  double? _crossAxisExtentCache;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    if (_layoutCache != null &&
        constraints.crossAxisExtent == _crossAxisExtentCache) {
      return _layoutCache!;
    }
    _crossAxisExtentCache = constraints.crossAxisExtent;
    int crossAxisCount = ((constraints.crossAxisExtent - crossAxisSpacing) /
            (maxCrossAxisExtent + crossAxisSpacing))
        .ceil();
    crossAxisCount = max(1, crossAxisCount);
    final double usableCrossAxisExtent = max(
      0.0,
      constraints.crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1),
    );
    final double childCrossAxisExtent = usableCrossAxisExtent / crossAxisCount;
    final double childMainAxisExtent = max(
      minHeight,
      childCrossAxisExtent / childAspectRatio + mainAxisExtent,
    );
    return _layoutCache = SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: childMainAxisExtent + mainAxisSpacing,
      crossAxisStride: childCrossAxisExtent + crossAxisSpacing,
      childMainAxisExtent: childMainAxisExtent,
      childCrossAxisExtent: childCrossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(SliverGridDelegateWithExtentAndRatio oldDelegate) {
    final flag = oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
        oldDelegate.mainAxisSpacing != mainAxisSpacing ||
        oldDelegate.crossAxisSpacing != crossAxisSpacing ||
        oldDelegate.childAspectRatio != childAspectRatio ||
        oldDelegate.mainAxisExtent != mainAxisExtent;
    if (flag) _layoutCache = null;
    return flag;
  }
}