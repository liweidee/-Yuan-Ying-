import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS 后台音频保活控制器
///
/// 仅 iOS 生效；其他平台 start/stop 为 no-op。
///
/// 使用方式：
/// - 短时保活（切歌窗口）：
///   `await SilenceKeeper.start(timeout: const Duration(seconds: 30));`
/// - 长期保活（后台服务）：
///   `await SilenceKeeper.start();`
///   // ... 长时间运行 ...
///   `await SilenceKeeper.stop();`
///
/// 状态同步策略：
/// - start() 调用原生后，用原生返回的真实状态设置 _isRunning，
///   避免"原生启动失败但 Dart 层认为成功"的状态不一致。
class SilenceKeeper {
  SilenceKeeper._();

  static const _channel = MethodChannel('com.yuanying/silence_keeper');

  static bool _isRunning = false;

  static bool get _supported {
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  /// 启动保活
  ///
  /// [timeout] 为 null 时不超时，需手动调用 [stop]；
  /// 非 null 时，原生侧在指定时长后自动停止（作为异常兜底）。
  static Future<void> start({Duration? timeout}) async {
    if (!_supported) return;
    if (_isRunning) return;
    try {
      final ok = await _channel.invokeMethod<bool>('startSilence', {
        'timeoutSeconds': timeout?.inSeconds,
      }) ?? false;
      _isRunning = ok;
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