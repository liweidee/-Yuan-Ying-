import 'package:flutter/material.dart';
import 'package:yuanying/common/types/stat_type.dart';
import 'package:yuanying/utils/num_utils.dart';

class StatWidget extends StatelessWidget {
  final StatType type;
  final dynamic value;
  final Color? color;
  final double iconSize;

  const StatWidget({
    super.key,
    required this.type,
    required this.value,
    this.color,
    this.iconSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = this.color ?? theme.colorScheme.outline.withValues(alpha: 0.8);
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          type.iconData,
          semanticLabel: type.label,
          size: iconSize,
          color: textColor,
        ),
        const SizedBox(width: 2),
        Text(
          NumUtils.numFormat(value),
          style: TextStyle(fontSize: 12, color: textColor),
        ),
      ],
    );
  }
}