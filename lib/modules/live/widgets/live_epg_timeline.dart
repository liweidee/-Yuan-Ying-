// lib/modules/live/widgets/live_epg_timeline.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/live_controller.dart';
import '../models/epg_programme.dart';

class LiveEpgTimeline extends StatefulWidget {
  const LiveEpgTimeline({super.key});

  @override
  State<LiveEpgTimeline> createState() => _LiveEpgTimelineState();
}

class _LiveEpgTimelineState extends State<LiveEpgTimeline> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemWidth = 140;
  static const double _itemHeight = 72;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<LiveController>(tag: 'live');
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      if (ctrl.epgLoading.value) {
        return _buildStatus(context, colorScheme, '节目单加载中...', loading: true);
      }
      if (ctrl.epgError.value.isNotEmpty) {
        return _buildStatus(context, colorScheme, ctrl.epgError.value);
      }

      final programmes = ctrl.todayProgrammes;
      if (programmes.isEmpty) {
        return _buildStatus(context, colorScheme, '暂无节目单');
      }

      // 自动滚动到当前节目
      final now = DateTime.now();
      final currentIndex = programmes.indexWhere((p) => p.isPlayingAt(now));
      if (currentIndex >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final offset = (currentIndex * _itemWidth) - _itemWidth;
            _scrollController.animateTo(
              offset.clamp(0.0, _scrollController.position.maxScrollExtent),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }

      return Container(
        height: _itemHeight,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outline.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        child: ListView.builder(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: programmes.length,
          itemBuilder: (context, index) {
            final p = programmes[index];
            final isCurrent = index == currentIndex;
            final isEnded = p.stop.isBefore(now);
            return _TimelineItem(
              programme: p,
              isCurrent: isCurrent,
              isEnded: isEnded,
              width: _itemWidth,
              now: now,
            );
          },
        ),
      );
    });
  }

  Widget _buildStatus(BuildContext context, ColorScheme colorScheme, String text,
      {bool loading = false}) {
    return Container(
      height: _itemHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: TextStyle(fontSize: 13, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final EpgProgramme programme;
  final bool isCurrent;
  final bool isEnded;
  final double width;
  final DateTime now;

  const _TimelineItem({
    required this.programme,
    required this.isCurrent,
    required this.isEnded,
    required this.width,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color bgColor;
    Color titleColor;
    if (isCurrent) {
      bgColor = colorScheme.primary.withOpacity(0.08);
      titleColor = colorScheme.primary;
    } else if (isEnded) {
      bgColor = Colors.transparent;
      titleColor = colorScheme.outline.withOpacity(0.5);
    } else {
      bgColor = Colors.transparent;
      titleColor = colorScheme.onSurface;
    }

    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: isCurrent
            ? Border.all(color: colorScheme.primary.withOpacity(0.3), width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,   // ← 关键修复
        children: [
          Text(
            programme.startLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              color: isCurrent ? colorScheme.primary : colorScheme.outline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Flexible(
            child: Text(
              programme.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                color: titleColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: LinearProgressIndicator(
                value: programme.progressAt(now),
                minHeight: 2,
                backgroundColor: colorScheme.outline.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation(colorScheme.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}