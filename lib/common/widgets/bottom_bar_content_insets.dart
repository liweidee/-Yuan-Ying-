import 'package:flutter/material.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';

/// 为自定义底栏页面提供内容安全区。
///
/// 不缩小页面视口，也不修改 MediaQuery 安全区，只由滚动视图显式读取
/// 并增加内容底部 padding。壁纸模式下内容仍可从底栏后方经过，同时最后
/// 一项可以完整滚动到底栏上方。
class BottomBarContentInsets extends StatelessWidget {
  const BottomBarContentInsets({
    super.key,
    required this.style,
    required this.child,
  });

  final NavigationBarStyle style;
  final Widget child;

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_BottomBarContentInsetScope>()
            ?.bottomInset ??
        0.0;
  }

  static EdgeInsets addToPadding(
    BuildContext context,
    EdgeInsets padding,
  ) {
    final bottomInset = of(context);
    if (bottomInset <= 0) return padding;
    return padding.copyWith(bottom: padding.bottom + bottomInset);
  }

  @override
  Widget build(BuildContext context) {
    if (style == NavigationBarStyle.floating) {
      return _BottomBarContentInsetScope(bottomInset: 0, child: child);
    }

    final bottomInset =
        style.baseHeight + MediaQuery.viewPaddingOf(context).bottom;
    return _BottomBarContentInsetScope(
      bottomInset: bottomInset,
      child: child,
    );
  }
}

class _BottomBarContentInsetScope extends InheritedWidget {
  const _BottomBarContentInsetScope({
    required this.bottomInset,
    required super.child,
  });

  final double bottomInset;

  @override
  bool updateShouldNotify(_BottomBarContentInsetScope oldWidget) {
    return bottomInset != oldWidget.bottomInset;
  }
}
