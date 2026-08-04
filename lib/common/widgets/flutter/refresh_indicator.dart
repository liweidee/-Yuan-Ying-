// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: prefer_initializing_formals

import 'dart:async' show Completer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart' hide RefreshIndicator;
import 'package:yuanying/common/widgets/scroll_behavior.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';

/// The distance from the child's top or bottom [edgeOffset] where
/// the refresh indicator will settle.
double get displacement => SettingPref.refreshDisplacement;

// The over-scroll distance that moves the indicator to its maximum
// displacement, as a percentage of the scrollable's container extent.
double get kDragContainerExtentPercentage => SettingPref.refreshDragPercentage;

// How much the scroll's drag gesture can overshoot the RefreshIndicator's
// displacement; max displacement = _kDragSizeFactorLimit * displacement.
const double _kDragSizeFactorLimit = 1.5;

// When the scroll ends, the duration of the refresh indicator's animation
// to the RefreshIndicator's displacement.
const Duration _kIndicatorSnapDuration = Duration(milliseconds: 150);

// The duration of the ScaleTransition that starts when the refresh action
// has completed.
const Duration _kIndicatorScaleDuration = Duration(milliseconds: 200);

/// Indicates current status of Material `RefreshIndicator`.
enum RefreshIndicatorStatus {
  /// Pointer is down.
  drag,

  /// Animating to the indicator's final "displacement".
  snap,

  /// Running the refresh callback.
  refresh,

  /// Animating the indicator's fade-out after refreshing.
  done,

  /// Animating the indicator's fade-out after not arming.
  canceled,
}

/// A widget that supports the Material "swipe to refresh" idiom.
class RefreshIndicator extends StatefulWidget {
  const RefreshIndicator({
    super.key,
    this.edgeOffset = 0.0,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.strokeWidth = RefreshProgressIndicator.defaultStrokeWidth,
    this.elevation = 2.0,
    this.isClampingScrollPhysics = false,
    required this.child,
  }) : assert(elevation >= 0.0);

  final Widget child;
  final double edgeOffset;
  final RefreshCallback onRefresh;
  final Color? color;
  final Color? backgroundColor;
  final ScrollNotificationPredicate notificationPredicate;
  final double strokeWidth;
  final double elevation;
  final bool isClampingScrollPhysics;

  @override
  RefreshIndicatorState createState() => RefreshIndicatorState();
}

/// Contains the state for a [RefreshIndicator].
class RefreshIndicatorState extends State<RefreshIndicator>
    with TickerProviderStateMixin<RefreshIndicator> {
  late AnimationController _positionController;
  late AnimationController _scaleController;
  late Animation<double> _positionFactor;
  late Animation<double> _scaleFactor;
  late Animation<double> _value;
  late Animation<Color?> _valueColor;

  RefreshIndicatorStatus? _status;
  late Future<void> _pendingRefreshFuture;
  double? _dragOffset;
  late Color _effectiveValueColor;

  static final Animatable<double> _threeQuarterTween = Tween<double>(
    begin: 0.0,
    end: 0.75,
  );

  static final Animatable<double> _kDragSizeFactorLimitTween = Tween<double>(
    begin: 0.0,
    end: _kDragSizeFactorLimit,
  );

  static final Animatable<double> _oneToZeroTween = Tween<double>(
    begin: 1.0,
    end: 0.0,
  );

  @protected
  @override
  void initState() {
    super.initState();
    _positionController = AnimationController(vsync: this);
    _positionFactor = _positionController.drive(_kDragSizeFactorLimitTween);
    _value = _positionController.drive(_threeQuarterTween);
    _scaleController = AnimationController(vsync: this);
    _scaleFactor = _scaleController.drive(_oneToZeroTween);
  }

  @protected
  @override
  void didChangeDependencies() {
    _setupColorTween();
    super.didChangeDependencies();
  }

  @protected
  @override
  void didUpdateWidget(covariant RefreshIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _setupColorTween();
    }
  }

  @protected
  @override
  void dispose() {
    _positionController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _setupColorTween() {
    final colorScheme = Theme.of(context).colorScheme;
    _effectiveValueColor = widget.color ?? colorScheme.primary;
    final Color color = _effectiveValueColor;
    if (color.a == 0) {
      _valueColor = AlwaysStoppedAnimation<Color>(color);
    } else {
      _valueColor = _positionController.drive(
        ColorTween(
          begin: color.withValues(alpha: 0),
          end: color,
        ).chain(
          CurveTween(curve: const Interval(0.0, 1.0 / _kDragSizeFactorLimit)),
        ),
      );
    }
  }

  bool _shouldStart(ScrollNotification notification) {
    return _status == null &&
        ((notification is ScrollStartNotification &&
                notification.dragDetails != null) ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null)) &&
        notification.metrics.extentBefore == 0.0 &&
        _start();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) {
      return false;
    }
    if (_shouldStart(notification)) {
      setState(() {
        _status = RefreshIndicatorStatus.drag;
      });
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      if (_status == RefreshIndicatorStatus.drag) {
        _dragOffset = _dragOffset! - notification.scrollDelta!;
        _checkDragOffset(notification.metrics.viewportDimension);

        if (notification.dragDetails == null &&
            _valueColor.value!.a == _effectiveValueColor.a) {
          _show();
        }
      }
    } else if (notification is OverscrollNotification) {
      if (_status == RefreshIndicatorStatus.drag) {
        _dragOffset = _dragOffset! - notification.overscroll;
        _checkDragOffset(notification.metrics.viewportDimension);
      }
    } else if (notification is ScrollEndNotification) {
      switch (_status) {
        case RefreshIndicatorStatus.drag:
          if (_valueColor.value!.a == _effectiveValueColor.a) {
            _show();
          } else {
            _dismiss(RefreshIndicatorStatus.canceled);
          }
        case RefreshIndicatorStatus.canceled:
        case RefreshIndicatorStatus.done:
        case RefreshIndicatorStatus.refresh:
        case RefreshIndicatorStatus.snap:
        case null:
          break;
      }
    }
    return false;
  }

  bool _handleIndicatorNotification(OverscrollIndicatorNotification notification) {
    if (notification.depth != 0 || !notification.leading) {
      return false;
    }
    if (_status == RefreshIndicatorStatus.drag) {
      notification.disallowIndicator();
      return true;
    }
    return false;
  }

  bool _start() {
    assert(_status == null);
    assert(_dragOffset == null);
    _dragOffset = 0.0;
    _scaleController.value = 0.0;
    _positionController.value = 0.0;
    return true;
  }

  void _checkDragOffset(double containerExtent) {
    assert(_status == RefreshIndicatorStatus.drag);
    double newValue = _dragOffset! / (containerExtent * kDragContainerExtentPercentage);
    _positionController.value = clampDouble(newValue, 0.0, 1.0);
  }

  Future<void> _dismiss(RefreshIndicatorStatus newMode) async {
    await Future<void>.value();
    assert(
      newMode == RefreshIndicatorStatus.canceled || newMode == RefreshIndicatorStatus.done,
    );
    setState(() {
      _status = newMode;
    });
    switch (_status!) {
      case RefreshIndicatorStatus.done:
        await _scaleController.animateTo(1.0, duration: _kIndicatorScaleDuration);
      case RefreshIndicatorStatus.canceled:
        await _positionController.animateTo(0.0, duration: _kIndicatorScaleDuration);
      case RefreshIndicatorStatus.drag:
      case RefreshIndicatorStatus.refresh:
      case RefreshIndicatorStatus.snap:
        assert(false);
    }
    if (mounted && _status == newMode) {
      _dragOffset = null;
      setState(() {
        _status = null;
      });
    }
  }

  void _show() {
    assert(_status != RefreshIndicatorStatus.refresh);
    assert(_status != RefreshIndicatorStatus.snap);
    final Completer<void> completer = Completer<void>();
    _pendingRefreshFuture = completer.future;
    _status = RefreshIndicatorStatus.snap;
    _positionController.animateTo(
      1.0 / _kDragSizeFactorLimit,
      duration: _kIndicatorSnapDuration,
    ).whenComplete(() {
      if (mounted && _status == RefreshIndicatorStatus.snap) {
        setState(() {
          _status = RefreshIndicatorStatus.refresh;
        });
        widget.onRefresh().whenComplete(() {
          if (mounted && _status == RefreshIndicatorStatus.refresh) {
            completer.complete();
            _dismiss(RefreshIndicatorStatus.done);
          }
        });
      }
    });
  }

  Future<void> show() {
    if (_status != RefreshIndicatorStatus.refresh && _status != RefreshIndicatorStatus.snap) {
      if (_status == null) {
        _start();
      }
      _show();
    }
    return _pendingRefreshFuture;
  }

  @protected
  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterialLocalizations(context));
    Widget child = NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: _handleIndicatorNotification,
        child: widget.child,
      ),
    );
    assert(() {
      if (_status == null) {
        assert(_dragOffset == null);
      } else {
        assert(_dragOffset != null);
      }
      return true;
    }());

    final bool showIndeterminateIndicator =
        _status == RefreshIndicatorStatus.refresh || _status == RefreshIndicatorStatus.done;

    child = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        if (_status != null)
          Positioned(
            top: widget.edgeOffset,
            left: 0.0,
            right: 0.0,
            child: SizeTransition(
              alignment: Alignment.bottomCenter,
              sizeFactor: _positionFactor,
              child: Padding(
                padding: EdgeInsets.only(top: displacement),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ScaleTransition(
                    scale: _scaleFactor,
                    child: AnimatedBuilder(
                      animation: _positionController,
                      builder: (context, child) => RefreshProgressIndicator(
                        value: showIndeterminateIndicator ? null : _value.value,
                        valueColor: _valueColor,
                        backgroundColor: widget.backgroundColor,
                        strokeWidth: widget.strokeWidth,
                        elevation: widget.elevation,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (!widget.isClampingScrollPhysics && (Platform.isIOS || Platform.isMacOS)) {
      return child;
    }
    return ScrollConfiguration(
      behavior: const AppScrollBehavior(),
      child: child,
    );
  }
}

typedef refreshIndicator = RefreshIndicator;