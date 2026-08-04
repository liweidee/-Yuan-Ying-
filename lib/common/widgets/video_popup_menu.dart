import 'package:flutter/material.dart';

class VideoPopupMenu extends StatelessWidget {
  final double iconSize;
  final dynamic videoItem;
  final VoidCallback? onRemove;

  const VideoPopupMenu({
    super.key,
    required this.iconSize,
    required this.videoItem,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert_outlined,
        color: Theme.of(context).colorScheme.outline,
        size: iconSize,
      ),
      onSelected: (value) {
        if (value == 'remove' && onRemove != null) onRemove!();
      },
      itemBuilder: (context) => [
        if (onRemove != null)
          const PopupMenuItem(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.delete, size: 18),
                SizedBox(width: 6),
                Text('移除', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }
}