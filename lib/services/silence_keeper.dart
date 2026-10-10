import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS 后台音频保活控制器
///
/// - start() 使用独占模式（保持锁屏控制栏）
/// - 通过 audio_session 插件控制音频会话配置
class SilenceKeeper {
  SilenceKeeper._();

  static const _channel = MethodChannel('com.yuanying/silence_keeper');
  static bool _isRunning = false;

  static bool get isRunning => _isRunning;

  static bool get _supported {
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  static Future<bool> start({Duration? timeout}) async {
    if (!_supported) return false;
    if (_isRunning) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('startSilence', {
        'timeoutSeconds': timeout?.inSeconds,
      }) ?? false;
      _isRunning = ok;
      return ok;
    } catch (e) {
      _isRunning = false;
      debugPrint('[SilenceKeeper] start failed: $e');
      return false;
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