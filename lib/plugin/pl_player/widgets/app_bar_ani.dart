import 'package:yuanying/common/widgets/view_safe_area.dart';
import 'package:flutter/material.dart';

class AppBarAni extends StatelessWidget {
  const AppBarAni({
    super.key,
    required this.child,
    required this.controller,
    required this.isTop,
    required this.isFullScreen,
    required this.removeSafeArea,
  });

  final Widget child;
  final AnimationController controller;
  final bool isTop;
  final bool isFullScreen;
  final bool removeSafeArea;

  static final _topPos = Tween<Offset>(
    begin: const Offset(0.0, -1.0),
    end: Offset.zero,
  );

  // 弱化渐变的黑色不透明度
  // 0xBF = 191 = 75%，0x80 = 128 = 50%
  // 全屏时底部 34pt 安全区（Home Indicator 所在区域）若被 75% 黑色覆盖，
  // 视觉上底栏按钮会"沉在黑色里"，看起来像被遮挡。改为 50% 后
  // 既保留了渐变遮罩的可读性，又不会吞没底部控件。
  static const _topDecoration = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0x80000000),
    ],
    tileMode: TileMode.mirror,
  );

  static final _bottomPos = Tween<Offset>(
    begin: const Offset(0, 1.2),
    end: Offset.zero,
  );

  static const _bottomDecoration = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0x80000000),
    ],
    tileMode: TileMode.mirror,
  );

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: controller.drive(isTop ? _topPos : _bottomPos),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isTop ? _topDecoration : _bottomDecoration,
        ),
        child: removeSafeArea
            ? child
            : ViewSafeArea(
                // 全屏时四边都避让安全区
                // - top:    避让 iOS 刘海 / Android 状态栏
                // - bottom: 避让 iOS Home Indicator / Android 手势条
                // - left / right: 避让横屏挖孔屏的挖孔
                // 非全屏时全部为 false，与修改前完全一致。
                top: isFullScreen,
                bottom: isFullScreen,
                left: isFullScreen,
                right: isFullScreen,
                child: child,
              ),
      ),
    );
  }
}
