import 'package:flutter/material.dart';

class ColorPalette extends StatelessWidget {
  final Color color;
  final bool selected;
  final double size;
  final double borderWidth;

  const ColorPalette({
    super.key,
    required this.color,
    this.selected = false,
    this.size = 44,
    this.borderWidth = 3,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          width: borderWidth,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(selected ? 2.0 : 0),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : theme.colorScheme.outline.withOpacity(0.2),
              width: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}