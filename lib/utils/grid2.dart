import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:yuanying/models/common/card_layout_mode.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';

abstract final class Grid2 {
  /// 使用 smallCardWidth 作为最大列宽度的网格委托
  /// 适用于分类页等非推荐流场景
  static SliverGridDelegateWithExtentAndRatio2 videoCardVDelegate(
    BuildContext context, {
    required CardLayoutMode mode,
    double minHeight = 25,
  }) {
    // 直接使用 smallCardWidth，忽略 mode（但保留 mode 参数以便后续扩展）
    final double maxWidth = SettingPref.smallCardWidth;

    return SliverGridDelegateWithExtentAndRatio2(
      mainAxisSpacing: 8.0,
      crossAxisSpacing: 8.0,
      maxCrossAxisExtent: maxWidth,
      childAspectRatio: 0.75,
      mainAxisExtent: MediaQuery.textScalerOf(context).scale(minHeight),
    );
  }
}

// 复制自 grid.dart 的 SliverGridDelegateWithExtentAndRatio，重命名避免冲突
class SliverGridDelegateWithExtentAndRatio2 extends SliverGridDelegate {
  SliverGridDelegateWithExtentAndRatio2({
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
  bool shouldRelayout(SliverGridDelegateWithExtentAndRatio2 oldDelegate) {
    final flag = oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
        oldDelegate.mainAxisSpacing != mainAxisSpacing ||
        oldDelegate.crossAxisSpacing != crossAxisSpacing ||
        oldDelegate.childAspectRatio != childAspectRatio ||
        oldDelegate.mainAxisExtent != mainAxisExtent;
    if (flag) _layoutCache = null;
    return flag;
  }
}


// 用法：
// import 'package:yuanying/utils/grid2.dart';

// 原写法：gridDelegate: Grid.videoCardVDelegate(
//   context,
//   mode: mode,
//   minHeight: 25,
// ),

// 新写法：gridDelegate: Grid2.videoCardVDelegate(
//   context,
//   mode: mode,
//   minHeight: 25,
// ),