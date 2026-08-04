import 'package:flutter/material.dart';

/// 视频详情适配器 - 替代 B站的 VideoDetailController
class VideoDetailAdapter {
  final List<SegmentProgressItem> segmentProgressList;
  final List<ViewPointItem> viewPointList;
  final bool showVP;
  final bool showDmTrendChart;
  final dynamic dmTrend;

  VideoDetailAdapter({
    this.segmentProgressList = const [],
    this.viewPointList = const [],
    this.showVP = false,
    this.showDmTrendChart = false,
    this.dmTrend,
  });
}

class SegmentProgressItem {
  final double start;
  final double end;
  final Color color;

  SegmentProgressItem({
    required this.start,
    required this.end,
    required this.color,
  });
}

class ViewPointItem {
  final String title;
  final int start;
  final int end;

  ViewPointItem({
    required this.title,
    required this.start,
    required this.end,
  });
}