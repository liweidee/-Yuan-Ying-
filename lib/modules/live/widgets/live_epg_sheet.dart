import 'package:flutter/material.dart';

import '../models/epg_programme.dart';

class LiveEpgSheet extends StatelessWidget {
  final String channelName;
  final List<EpgProgramme> programmes;

  const LiveEpgSheet({
    super.key,
    required this.channelName,
    required this.programmes,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    // 找到当前节目索引，自动滚动
    final currentIndex = programmes.indexWhere((p) => p.isPlayingAt(now));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // ============================================================
            // 头部（本次唯一改动区域）
            // ============================================================
            const SizedBox(height: 8),
            // 拖拽把手：略微加宽加高，圆角更柔和
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: colorScheme.outline.withOpacity(0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          channelName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '节目单',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 圆形半透明关闭按钮（比裸 IconButton 精致）
                  Material(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ============================================================
            // 以下与原始版本完全一致
            // ============================================================
            Divider(height: 1, color: colorScheme.outline.withOpacity(0.1)),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: programmes.length,
                itemBuilder: (context, index) {
                  final p = programmes[index];
                  final isCurrent = index == currentIndex;
                  final isEnded = p.stop.isBefore(now);
                  return _ProgrammeItem(
                    programme: p,
                    isCurrent: isCurrent,
                    isEnded: isEnded,
                    now: now,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// 节目项：与原始版本完全一致，未做任何改动
// ============================================================
class _ProgrammeItem extends StatelessWidget {
  final EpgProgramme programme;
  final bool isCurrent;
  final bool isEnded;
  final DateTime now;

  const _ProgrammeItem({
    required this.programme,
    required this.isCurrent,
    required this.isEnded,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color titleColor;
    if (isCurrent) {
      titleColor = colorScheme.primary;
    } else if (isEnded) {
      titleColor = colorScheme.outline.withOpacity(0.5);
    } else {
      titleColor = colorScheme.onSurface;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isCurrent ? colorScheme.primary.withOpacity(0.06) : null,
      child: Row(
        children: [
          // 左侧竖条（当前节目）
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: isCurrent ? colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          // 时间
          SizedBox(
            width: 44,
            child: Text(
              programme.startLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                color: titleColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 节目名
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  programme.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color: titleColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isCurrent) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${programme.startLabel} - ${programme.stopLabel}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}