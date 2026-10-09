import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// iOS 后台音频保活控制器
///
/// 通过 MethodChannel 调用原生 AVAudioEngine，
/// 在切集间隙持续输出静音音频，满足 iOS 后台音频模式的前提条件。
class SilenceKeeper {
  SilenceKeeper._();

  static const _channel = MethodChannel('com.yuanying/silence_keeper');

  /// 是否已启动（用于幂等保护，避免重复调用原生端）
  static bool _isRunning = false;

  /// 启动保活
  /// 幂等：重复调用安全
  static Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      await _channel.invokeMethod('startSilence');
    } catch (e) {
      _isRunning = false;
      debugPrint('[SilenceKeeper] start failed: $e');
    }
  }

  /// 停止保活
  static Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    try {
      await _channel.invokeMethod('stopSilence');
    } catch (e) {
      debugPrint('[SilenceKeeper] stop failed: $e');
    }
  }

  /// 强制重置状态（用于异常恢复）
  static void reset() {
    _isRunning = false;
  }
}