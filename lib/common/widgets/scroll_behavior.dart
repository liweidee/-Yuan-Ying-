import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'dart:io';

/// 基础滚动行为 - 全局隐藏滚动条，保留滚动功能
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // 全局禁用滚动条（桌面端和移动端都不显示）
    return child;
  }

  @override
  Widget buildViewportChrome(
    BuildContext context,
    Widget child,
    AxisDirection axisDirection,
  ) {
    // 关键：必须返回 child 以确保滚轮事件正常传递
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // 桌面端使用 ClampingScrollPhysics，移动端使用 BouncingScrollPhysics
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return const ClampingScrollPhysics();
    }
    return const BouncingScrollPhysics();
  }

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
    PointerDeviceKind.mouse,
  };
}

/// 无滚动条行为（继承自 AppScrollBehavior，同样隐藏滚动条）
class NoScrollbarBehavior extends AppScrollBehavior {
  const NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// 保留原有 CustomScrollBehavior 以兼容旧代码
class CustomScrollBehavior extends MaterialScrollBehavior {
  const CustomScrollBehavior(this.dragDevices);

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Widget buildViewportChrome(
    BuildContext context,
    Widget child,
    AxisDirection axisDirection,
  ) {
    return child;
  }

  @override
  final Set<PointerDeviceKind> dragDevices;
}