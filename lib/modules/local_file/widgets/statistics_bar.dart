import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StatisticsBar extends StatelessWidget {
  final int videoCount;
  final String totalSize;
  final int pathCount;
  final String lastScanTime;

  const StatisticsBar({
    super.key,
    required this.videoCount,
    required this.totalSize,
    required this.pathCount,
    required this.lastScanTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withOpacity(0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildStatItem(
            context,
            icon: Icons.video_library_outlined,
            label: '$videoCount 个视频',
            color: colorScheme.primary,
          ),
          const SizedBox(width: 16),
          _buildStatItem(
            context,
            icon: Icons.storage_outlined,
            label: totalSize,
            color: colorScheme.onSurfaceVariant,
          ),
          const Spacer(),
          _buildStatItem(
            context,
            icon: Icons.folder_outlined,
            label: '$pathCount 个路径',
            color: colorScheme.onSurfaceVariant,
            small: true,
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              lastScanTime,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    bool small = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: small ? 11 : 12,
            fontWeight: small ? FontWeight.w400 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}