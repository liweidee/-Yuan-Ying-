import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidPipHelper {
  static const _channel = MethodChannel('com.example.yuanying/pip');

  /// 当前是否处于 PiP 模式（全局单例，由原生回调驱动）
  static final ValueNotifier<bool> isPipActive = ValueNotifier<bool>(false);

  static bool _initialized = false;

  /// 在 main() 中调用一次
  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipModeChanged' && call.arguments is bool) {
        isPipActive.value = call.arguments as bool;
      }
    });
  }

  static Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enter({int width = 16, int height = 9}) async {
    try {
      return await _channel.invokeMethod<bool>('enter', {
        'width': width,
        'height': height,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }
}