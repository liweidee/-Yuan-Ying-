import 'package:flutter/material.dart';
import 'package:yuanying/common/types/badge_type.dart';
import 'package:yuanying/common/extensions/string_ext.dart';
import 'package:yuanying/common/extensions/theme_ext.dart';

class PBadge extends StatelessWidget {
  final String? text;
  final bool isStack;
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final EdgeInsets? padding;
  final BadgeType type;
  final BadgeSize size;
  final double fontSize;
  final bool isBold;
  final double? textScaleFactor;
  final double? maxWidth;
  final TextOverflow overflow;

  const PBadge({
    super.key,
    required this.text,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.type = BadgeType.primary,
    this.size = BadgeSize.medium,
    this.isStack = true,
    this.fontSize = 11,
    this.isBold = true,
    this.textScaleFactor,
    this.padding,
    this.maxWidth,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isNullOrEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context).colorScheme;

    Color bgColor;
    Color color;
    Color borderColor = Colors.transparent;

    switch (type) {
      case BadgeType.primary:
        bgColor = theme.primary;
        color = theme.onPrimary;
      case BadgeType.secondary:
        bgColor = theme.secondaryContainer.withValues(alpha: 0.5);
        color = theme.onSecondaryContainer;
      case BadgeType.gray:
        bgColor = Colors.black45;
        color = Colors.white;
      case BadgeType.error:
        if (theme.isDark) {
          bgColor = theme.errorContainer;
          color = theme.onErrorContainer;
        } else {
          bgColor = theme.error;
          color = theme.onError;
        }
      case BadgeType.line_primary:
        color = theme.primary;
        bgColor = Colors.transparent;
        borderColor = theme.primary;
      case BadgeType.line_secondary:
        color = theme.secondary;
        bgColor = Colors.transparent;
        borderColor = theme.secondary;
      case BadgeType.free:
        bgColor = theme.freeColor;
        color = Colors.white;
      case BadgeType.shop:
        bgColor = theme.secondaryContainer.withValues(alpha: 0.5);
        color = theme.onSurfaceVariant;
    }

    final paddingStyle = padding ?? const EdgeInsets.symmetric(vertical: 2, horizontal: 3);
    final borderRadius = size == BadgeSize.small
        ? BorderRadius.circular(3)
        : BorderRadius.circular(4);

    Widget content = Container(
      padding: paddingStyle,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: bgColor,
        border: Border.all(color: borderColor),
      ),
      child: Text(
        text!,
        maxLines: 1,
        overflow: overflow,
        textScaler: textScaleFactor != null ? TextScaler.linear(textScaleFactor!) : null,
        style: TextStyle(
          height: 1,
          fontSize: fontSize,
          color: color,
          fontWeight: isBold ? FontWeight.bold : null,
        ),
        strutStyle: StrutStyle(
          leading: 0,
          height: 1,
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : null,
        ),
      ),
    );

    // ===== 应用最大宽度约束 =====
    if (maxWidth != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: content,
      );
    }

    if (isStack) {
      return Positioned(
        top: top,
        left: left,
        right: right,
        bottom: bottom,
        child: content,
      );
    }
    return content;
  }
}