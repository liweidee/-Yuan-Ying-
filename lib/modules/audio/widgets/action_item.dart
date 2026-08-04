import 'package:flutter/material.dart';

import 'package:yuanying/common/widgets/custom_arc.dart';
import 'package:yuanying/utils/platform_utils.dart';

class ActionItem extends StatelessWidget {
  const ActionItem({
    super.key,
    required this.icon,
    this.selectIcon,
    this.onTap,
    this.onLongPress,
    this.text,
    this.selectStatus = false,
    required this.semanticsLabel,
    this.expand = true,
    this.animation,
  }) : assert(!selectStatus || selectIcon != null);

  final Icon icon;
  final Icon? selectIcon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? text;
  final bool selectStatus;
  final String semanticsLabel;
  final bool expand;
  final Animation<double>? animation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    late final primary = !expand && colorScheme.brightness == Brightness.light
        ? colorScheme.inversePrimary
        : colorScheme.primary;

    Widget child = Icon(
      selectStatus ? selectIcon!.icon! : icon.icon,
      size: 18,
      color: selectStatus ? primary : icon.color ?? colorScheme.outline,
    );

    if (animation != null) {
      child = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: animation!,
            builder: (context, child) => Arc(
              size: 28,
              color: primary,
              progress: -animation!.value,
            ),
          ),
          child,
        ],
      );
    } else {
      child = SizedBox.square(dimension: 28, child: child);
    }

    child = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: expand
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [child, _buildText(theme)],
              )
            : child,
      ),
    );
    return expand ? Expanded(child: child) : child;
  }

  Widget _buildText(ThemeData theme) {
    final hasText = text != null;
    final child = Text(
      hasText ? text! : '-',
      key: hasText ? ValueKey(text!) : null,
      style: TextStyle(
        color: selectStatus
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
        fontSize: theme.textTheme.labelSmall!.fontSize,
      ),
    );
    if (hasText) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return ScaleTransition(scale: animation, child: child);
        },
        child: child,
      );
    }
    return child;
  }
}