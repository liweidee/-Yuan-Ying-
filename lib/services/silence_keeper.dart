import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS 后台音频保活控制器
///
/// 仅 iOS 生效；其他平台 start/stop 为 no-op。
class SilenceKeeper {
  SilenceKeeper._();

  static const _channel = MethodChannel('com.yuanying/silence_keeper');

  static bool _isRunning = false;

  static bool get _supported {
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  static Future<void> start() async {
    if (!_supported) return;
    if (_isRunning) return;
    _isRunning = true;
    try {
      await _channel.invokeMethod('startSilence');
    } catch (e) {
      _isRunning = false;
      debugPrint('[SilenceKeeper] start failed: $e');
    }
  }

  static Future<void> stop() async {
    if (!_supported) return;
    if (!_isRunning) return;
    _isRunning = false;
    try {
      await _channel.invokeMethod('stopSilence');
    } catch (e) {
      debugPrint('[SilenceKeeper] stop failed: $e');
    }
  }

  static void reset() {
    _isRunning = false;
  }
}