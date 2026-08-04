import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';

import 'package:flutter/services.dart'
    show SystemChrome, MethodChannel, SystemUiOverlay, DeviceOrientation;

bool _isDesktopFullScreen = false;

@pragma('vm:notify-debugger-on-exception')
Future<void> enterDesktopFullScreen({bool inAppFullScreen = false}) async {
  if (!inAppFullScreen && !_isDesktopFullScreen) {
    _isDesktopFullScreen = true;
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.EnterNativeFullscreen');
    } catch (_) {}
  }
}

@pragma('vm:notify-debugger-on-exception')
Future<void> exitDesktopFullScreen() async {
  if (_isDesktopFullScreen) {
    _isDesktopFullScreen = false;
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.ExitNativeFullscreen');
    } catch (_) {}
  }
}

List<DeviceOrientation>? _lastOrientation;
Future<void>? _setPreferredOrientations(List<DeviceOrientation> orientations) {
  if (_lastOrientation == orientations) {
    return null;
  }
  _lastOrientation = orientations;
  return SystemChrome.setPreferredOrientations(orientations);
}

Future<void>? portraitUpMode() {
  return _setPreferredOrientations(const [DeviceOrientation.portraitUp]);
}

Future<void>? portraitDownMode() {
  return _setPreferredOrientations(const [DeviceOrientation.portraitDown]);
}

Future<void>? landscapeLeftMode() {
  return _setPreferredOrientations(const [DeviceOrientation.landscapeLeft]);
}

Future<void>? landscapeRightMode() {
  return _setPreferredOrientations(const [DeviceOrientation.landscapeRight]);
}

Future<void>? fullMode() {
  return _setPreferredOrientations(
    const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
  );
}

bool _showSystemBar = true;
bool get showSystemBar_ => _showSystemBar;

Future<void>? hideSystemBar() {
  if (!_showSystemBar) {
    return null;
  }
  _showSystemBar = false;
  return SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

Future<void>? showSystemBar() {
  if (_showSystemBar) {
    return null;
  }
  _showSystemBar = true;
  return SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
}