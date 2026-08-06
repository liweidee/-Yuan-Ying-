import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';

/// 滚动监听基类（与 PiliPlus 完全一致）
abstract class CommonPageState<T extends StatefulWidget> extends State<T> {
  RxDouble? _barOffset;
  final _mainController = Get.find<MainController>();

  /// 是否需要修正滚动偏移（用于同步模式）
  bool get needsCorrection => false;

  @override
  void initState() {
    super.initState();
    _barOffset = _mainController.barOffset;
  }

  /// 包裹需要监听滚动的内容
  Widget onBuild(Widget child) {
    if (_barOffset != null) {
      return NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: child,
      );
    }
    return child;
  }

  void _updateOffset(double scrollDelta) {
    const maxOffset = 56.0;
    _barOffset!.value = (_barOffset!.value + scrollDelta).clamp(0.0, maxOffset);
  }

  bool _onNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis == Axis.horizontal) return false;

    if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails == null) return false;
      final pixel = metrics.pixels;
      final scrollDelta = notification.scrollDelta ?? 0;
      if (pixel < 0.0 && scrollDelta > 0) return false;

      if (needsCorrection) {
        final value = _barOffset!.value;
        const maxOffset = 56.0;
        final newValue = (value + scrollDelta).clamp(0.0, maxOffset);
        final offset = value - newValue;
        if (offset != 0) {
          _barOffset!.value = newValue;
          if (pixel < 0.0 && scrollDelta < 0.0 && value > 0.0) {
            return false;
          }
          Scrollable.of(notification.context!).position.correctBy(offset);
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
    _barOffset = null;
    super.dispose();
  }
}