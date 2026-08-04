import 'package:flutter/material.dart';
import 'package:yuanying/utils/platform_utils.dart';

class SearchText extends StatelessWidget {
  final String text;
  final ValueChanged<String>? onTap;
  final ValueChanged<String>? onLongPress;
  final double? fontSize;
  final Color? bgColor;
  final Color? textColor;
  final TextAlign? textAlign;
  final double? height;
  final EdgeInsets padding;
  final BorderRadius borderRadius;

  const SearchText({
    super.key,
    required this.text,
    this.onTap,
    this.onLongPress,
    this.fontSize,
    this.bgColor,
    this.textColor,
    this.textAlign,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasLongPress = onLongPress != null;
    return Material(
      color: bgColor ?? colorScheme.surfaceContainerHighest,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: () => onTap?.call(text),
        onLongPress: hasLongPress ? () => onLongPress!(text) : null,
        borderRadius: borderRadius,
        child: Padding(
          padding: padding,
          child: Text(
            text,
            textAlign: textAlign,
            style: TextStyle(
              fontSize: fontSize,
              height: height,
              color: textColor ?? colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}