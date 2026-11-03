import 'package:flutter/material.dart';

class ViewSafeArea extends StatelessWidget {
  const ViewSafeArea({
    super.key,
    this.top = false,
    this.bottom = false,
    this.left = true,
    this.right = true,
    required this.child,
  });

  final bool top;
  // bottom 参数，用于全屏时避让 iOS 的 Home Indicator
  final bool bottom;
  final bool left;
  final bool right;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 使用 viewPadding 而非 padding：
    // - viewPadding 反映设备原始安全区，不受父级 MediaQuery.removePadding 影响；
    // - 当 video_page 全屏时执行 removePadding(removeBottom: true) 后，
    //   padding.bottom 会变为 0，但 viewPadding.bottom 仍保留原始值，
    //   从而能继续正确避让 Home Indicator。
    EdgeInsets padding = MediaQuery.viewPaddingOf(context);
    return Padding(
      padding: EdgeInsets.only(
        top: top ? padding.top : 0.0,
        bottom: bottom ? padding.bottom : 0.0,
        left: left ? padding.left : 0.0,
        right: right ? padding.right : 0.0,
      ),
      child: child,
    );
  }
}