// lib/common/widgets/scale_app.dart
import 'dart:async' show scheduleMicrotask;
import 'dart:collection' show Queue;
import 'dart:ui' show PointerDataPacket;

import 'package:flutter/gestures.dart' show PointerEventConverter;
import 'package:flutter/rendering.dart' show RenderView, ViewConfiguration;
import 'package:flutter/widgets.dart';

/// Adapted from [WidgetsFlutterBinding]
class ScaledWidgetsFlutterBinding extends WidgetsFlutterBinding {
  ScaledWidgetsFlutterBinding._({this._scaleFactor = 1.0});

  double _scaleFactor;

  set scaleFactor(double scaleFactor) {
    if (_scaleFactor == scaleFactor) return;
    _scaleFactor = scaleFactor;
    handleMetricsChanged();
  }

  double devicePixelRatioScaled = 0;

  static ScaledWidgetsFlutterBinding? _binding;

  static ScaledWidgetsFlutterBinding get instance => _binding!;

  static WidgetsBinding ensureInitialized({double scaleFactor = 1.0}) =>
      _binding ??= ScaledWidgetsFlutterBinding._(scaleFactor: scaleFactor);

  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    final view = renderView.flutterView;
    final devicePixelRatio = view.devicePixelRatio;
    devicePixelRatioScaled = devicePixelRatio * _scaleFactor;
    final BoxConstraints physicalConstraints =
        BoxConstraints.fromViewConstraints(view.physicalConstraints);
    return ViewConfiguration(
      physicalConstraints: physicalConstraints,
      logicalConstraints: physicalConstraints / devicePixelRatioScaled,
      devicePixelRatio: devicePixelRatioScaled,
    );
  }

  @override
  void initInstances() {
    super.initInstances();
    platformDispatcher.onPointerDataPacket = _handlePointerDataPacket;
  }

  @override
  void unlocked() {
    super.unlocked();
    _flushPointerEventQueue();
  }

  final Queue<PointerEvent> _pendingPointerEvents = Queue<PointerEvent>();

  void _handlePointerDataPacket(PointerDataPacket packet) {
    try {
      _pendingPointerEvents.addAll(
        PointerEventConverter.expand(packet.data, _devicePixelRatioForView),
      );
      if (!locked) {
        _flushPointerEventQueue();
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'gestures library',
          context: ErrorDescription('while handling a pointer data packet'),
        ),
      );
    }
  }

  double _devicePixelRatioForView(int viewId) => devicePixelRatioScaled;

  @override
  void cancelPointer(int pointer) {
    if (_pendingPointerEvents.isEmpty && !locked) {
      scheduleMicrotask(_flushPointerEventQueue);
    }
    _pendingPointerEvents.addFirst(PointerCancelEvent(pointer: pointer));
  }

  void _flushPointerEventQueue() {
    assert(!locked);
    while (_pendingPointerEvents.isNotEmpty) {
      handlePointerEvent(_pendingPointerEvents.removeFirst());
    }
  }
}