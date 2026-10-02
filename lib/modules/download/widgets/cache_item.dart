// lib/modules/download/widgets/cache_item.dart
import 'package:flutter/material.dart';

import 'package:yuanying/modules/download/models/cache_entry.dart';

/// 缓存卡片（简化版）
///
/// 布局参考 PiliPlus DetailItem：
/// - 多选时不在左侧放 Checkbox，而是在封面上叠加遮罩 + 勾选图标
/// - 所有文本 Expanded + ellipsis 抗溢出
/// - 封面缺失时显示播放图标占位符
class CacheItem extends StatelessWidget {
  final CacheEntry entry;
  final bool multiSelect;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onPause;
  final VoidCallback onResume;

  const CacheItem({
    super.key,
    required this.entry,
    required this.multiSelect,
    required this.selected,
    required this.onSelect,
    required this.onTap,
    required this.onDelete,
    required this.onPause,
    required this.onResume,
  });

  static const double _coverWidth = 150;
  static const double _coverHeight = 94;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: multiSelect ? onSelect : onTap,
        onLongPress: multiSelect ? null : onDelete,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCover(colorScheme),
              const SizedBox(width: 10),
              Expanded(child: _buildInfo(colorScheme)),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 封面（含多选遮罩）
  // ============================================================
  Widget _buildCover(ColorScheme colorScheme) {
    final hasPic = entry.vodPic != null && entry.vodPic!.isNotEmpty;

    return SizedBox(
      width: _coverWidth,
      height: _coverHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: hasPic
                  ? Image.network(
                      entry.vodPic!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(colorScheme),
                    )
                  : _placeholder(colorScheme),
            ),
          ),
          if (multiSelect)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSelect,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primary.withValues(alpha: 0.35)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: selected ? 1 : 0,
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.play_circle_outline,
        size: 28,
        color: colorScheme.outline,
      ),
    );
  }

  // ============================================================
  // 信息区
  // ============================================================
  Widget _buildInfo(ColorScheme colorScheme) {
    return SizedBox(
      height: _coverHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${entry.vodName} · ${entry.qualityLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
          _buildStatus(colorScheme),
        ],
      ),
    );
  }

  // ============================================================
  // 状态行
  // ============================================================
  Widget _buildStatus(ColorScheme colorScheme) {
    // ========== 已完成 ==========
    if (entry.isCompleted) {
      return Row(
        children: [
          Icon(Icons.check_circle, size: 13, color: colorScheme.primary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              entry.sizeText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ),
          _actionButton(colorScheme),
        ],
      );
    }

    // ========== 下载中 ==========
    if (entry.isDownloading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 左侧：状态 + 百分比
              Text(
                '${entry.status.label} · ${entry.progressPercent}',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              // 中间：使用 Expanded 撑满，文本右对齐到按钮前
              Expanded(
                child: Text(
                  entry.progressText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _actionButton(colorScheme),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: entry.progress,
              minHeight: 3,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      );
    }

    // ========== paused / failed / waiting ==========
    return Row(
      children: [
        // 左侧：状态
        Text(
          entry.status.label,
          style: TextStyle(
            fontSize: 12,
            color: entry.status == CacheStatus.failed
                ? colorScheme.error
                : colorScheme.outline,
          ),
        ),
        // 中间：有进度则展示，Expanded 撑满右对齐
        if (entry.downloadedBytes > 0 && entry.totalBytes > 0) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.progressText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.outline,
              ),
            ),
          ),
        ] else
          const Spacer(),
        const SizedBox(width: 4),
        _actionButton(colorScheme),
      ],
    );
  }

  // ============================================================
  // 右侧操作按钮
  // ============================================================
  Widget _actionButton(ColorScheme colorScheme) {
    final IconData icon;
    final String tooltip;
    final VoidCallback onPressed;

    if (entry.isCompleted) {
      icon = Icons.play_circle_outline;
      tooltip = '播放';
      onPressed = onTap;
    } else if (entry.isDownloading) {
      icon = Icons.pause_circle_outline;
      tooltip = '暂停';
      onPressed = onPause;
    } else if (entry.status == CacheStatus.failed) {
      icon = Icons.refresh;
      tooltip = '重试';
      onPressed = onResume;
    } else {
      icon = Icons.play_circle_outline;
      tooltip = '继续';
      onPressed = onResume;
    }

    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(icon, size: 22),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
          maxWidth: 32,
          maxHeight: 32,
        ),
        splashRadius: 16,
        onPressed: onPressed,
      ),
    );
  }
}