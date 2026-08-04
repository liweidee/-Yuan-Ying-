import 'package:flutter/material.dart';
import 'package:yuanying/models/common/stat_type.dart';
import 'package:yuanying/utils/num_utils.dart';

class StatWidget extends StatelessWidget {
  final StatType type;
  final int? value;

  const StatWidget({
    super.key,
    required this.type,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData icon;
    switch (type) {
      case StatType.play:
        icon = Icons.play_arrow;
        break;
      case StatType.danmaku:
        icon = Icons.chat_bubble_outline;
        break;
      default:
        icon = Icons.visibility;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 2),
        Text(
          value != null ? NumUtils.numFormat(value) : '-',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
