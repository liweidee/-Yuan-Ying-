import 'package:flutter/material.dart';
import 'package:yuanying/t4/models/video_detail.dart';

/// 剧集列表组件
class EpisodePanel extends StatelessWidget {
  const EpisodePanel({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onEpisodeTap,
  });

  final List<Episode> episodes;
  final int currentIndex;
  final ValueChanged<int> onEpisodeTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: episodes.asMap().entries.map((entry) {
          final index = entry.key;
          final episode = entry.value;
          final isActive = index == currentIndex;
          
          return GestureDetector(
            onTap: () => onEpisodeTap(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive 
                    ? colorScheme.primary  // 修改这里
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                episode.name,
                style: TextStyle(
                  fontSize: 13,
                  color: isActive ? colorScheme.onPrimary : colorScheme.onSurface,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}