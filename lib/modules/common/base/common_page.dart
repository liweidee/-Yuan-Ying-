import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';
import 'package:yuanying/core/theme/style.dart';

/// 通用页面状态基类，负责处理顶部栏/底部栏的滚动隐藏逻辑
/// 支持两种模式：
/// - 同步模式（sync）：通过 barOffset 偏移量连续变化
/// - 即时模式（instant）：通过 showTopBar/showBottomBar 二值状态 + 动画
abstract class CommonPageState<T extends StatefulWidget> extends State<T> {
  RxDouble? _barOffset;
  RxBool? _showTopBar;
  RxBool? _showBottomBar;
  final _mainController = Get.find<MainController>();

  /// 子类可覆写，表示是否需要滚动校正（通常当顶部栏可隐藏时启用）
  bool get needsCorrection => false;

  @override
  void initState() {
    super.initState();
    // 根据当前模式决定使用哪组控制变量
    if (_mainController.isInstantMode) {
      // 即时模式：使用 showTopBar / showBottomBar（二者均由 MainController 管理）
      _barOffset = null;
      _showTopBar = _mainController.showTopBar;
      _showBottomBar = _mainController.showBottomBar;
    } else {
      // 同步模式：使用 barOffset（共享偏移量）
      _barOffset = _mainController.barOffset;
      _showTopBar = null;
      _showBottomBar = null;
    }
  }

  /// 将滚动监听包裹到 child 上
  Widget onBuild(Widget child) {
    if (_barOffset != null) {
      // 同步模式：监听 ScrollUpdateNotification 和 OverscrollNotification
      return NotificationListener<ScrollNotification>(
        onNotification: onNotificationType2,
        child: child,
      );
    }
    if (_showTopBar != null || _showBottomBar != null) {
      // 即时模式：监听 UserScrollNotification（滚动方向变化）
      return NotificationListener<UserScrollNotification>(
        onNotification: onNotificationType1,
        child: child,
      );
    }
    return child;
  }

  /// 即时模式通知处理：根据滚动方向显示/隐藏栏
  bool onNotificationType1(UserScrollNotification notification) {
    // if (!_mainController.useBottomNav.value) return false;
    if (notification.metrics.axis == Axis.horizontal) return false;

    switch (notification.direction) {
      case ScrollDirection.forward:   // 向上滚动（手指从下往上滑）→ 显示栏
        _showTopBar?.value = true;
        _showBottomBar?.value = true;
        break;
      case ScrollDirection.reverse:   // 向下滚动（手指从上往下滑）→ 隐藏栏
        _showTopBar?.value = false;
        _showBottomBar?.value = false;
        break;
      default:
        break;
    }
    return false;
  }

  /// 同步模式偏移更新辅助方法
  void _updateOffset(double scrollDelta) {
    final oldValue = _barOffset!.value;
    final newValue = (oldValue + scrollDelta).clamp(0.0, Style.topBarHeight);
    _barOffset!.value = newValue;
  }

  /// 同步模式通知处理：根据滚动增量累计偏移量
  bool onNotificationType2(ScrollNotification notification) {
    // if (!_mainController.useBottomNav.value) return false;

    final metrics = notification.metrics;
    if (metrics.axis == Axis.horizontal) return false;

    if (notification is ScrollUpdateNotification) {
      // 忽略非拖拽触发的滚动（例如惯性滚动）
      // if (notification.dragDetails == null) return false;
      final pixel = metrics.pixels;
      final scrollDelta = notification.scrollDelta ?? 0;
      if (pixel < 0.0 && scrollDelta > 0) return false;

      if (needsCorrection) {
        final oldValue = _barOffset!.value;
        final newValue = (oldValue + scrollDelta).clamp(0.0, Style.topBarHeight);
        final correction = oldValue - newValue;
        if (correction != 0) {
          _barOffset!.value = newValue;
          if (pixel < 0.0 && scrollDelta < 0.0 && oldValue > 0.0) return false;
          Scrollable.of(notification.context!).position.correctBy(correction);
        }
      } else {
        _updateOffset(scrollDelta);
      }
      return false;
    }

    if (notification is OverscrollNotification) {
      _updateOffset(notification.overscroll);
      return false;
    }

    return false;
  }

  @override
  void dispose() {
    // 避免内存泄漏，但注意变量是外部传入的，不应在此 dispose
    _barOffset = null;
    _showTopBar = null;
    _showBottomBar = null;
    super.dispose();
  }
}