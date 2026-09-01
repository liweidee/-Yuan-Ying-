// lib/modules/music/widgets/music_list_tile.dart
import 'package:flutter/material.dart';
import 'package:yuanying/t4/models/video_detail.dart';

class MusicListTile extends StatelessWidget {
  final Episode episode;
  final int index;
  final bool isPlaying;
  final bool isCurrent;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  const MusicListTile({
    super.key,
    required this.episode,
    required this.index,
    this.isPlaying = false,
    this.isCurrent = false,
    this.backgroundColor,
    this.onTap,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isHighlight = isCurrent || isPlaying;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      tileColor: backgroundColor,
      leading: SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: isCurrent
              ? Icon(Icons.equalizer, size: 20, color: colorScheme.primary)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: colorScheme.outline,
                  ),
                ),
        ),
      ),
      title: Text(
        episode.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: isHighlight ? colorScheme.primary : colorScheme.onSurface,
          fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      // trailing: IconButton(
      //   iconSize: 18,
      //   padding: EdgeInsets.zero,
      //   constraints: const BoxConstraints(),
      //   icon: Icon(Icons.more_vert, color: colorScheme.outline),
      //   onPressed: onMore,
      // ),
      onTap: onTap,
    );
  }
}