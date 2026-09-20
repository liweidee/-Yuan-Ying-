// lib/services/ad_block_proxy_service.dart
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:yuanying/services/system_log_service.dart';

import 'package:yuanying/services/ad_block_proxy.dart';

/// AdBlockProxy 全局单例包装
///
/// 设计原则：
///   1. 常驻进程，不随详情页生命周期启停
///   2. 开关关闭 / 代理未启动 / 非 M3U8 时，[wrapIfNeeded] 原样返回
///   3. 启动失败自动降级，不影响播放
class AdBlockProxyService {
  AdBlockProxyService._();
  static final AdBlockProxyService instance = AdBlockProxyService._();

  AdBlockProxy? _proxy;
  bool _enabled = false;

  /// 是否真正生效（开关开启 + 代理已运行）
  bool get isEnabled => _enabled && (_proxy?.isRunning ?? false);

  /// 应用启动时调用
  Future<void> init({required bool enabled}) async {
    _enabled = enabled;
    if (!enabled) return;
    await _ensureStarted();
  }

  /// 开关切换时调用
  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      await _ensureStarted();
    } else {
      await _stop();
    }
  }

  /// 包装 URL
  ///
  /// - 开关关闭 → 原样返回
  /// - 代理未启动 → 原样返回
  /// - 非 M3U8 → 原样返回
  /// - 其他 → 返回代理 URL
  String wrapIfNeeded(String url, {String? referer}) {
    if (!isEnabled) return url;
    if (!_proxy!.shouldProxy(url)) return url;
    return _proxy!.wrap(url, referer: referer);
  }

  /// 应用退出时调用（可选）
  Future<void> dispose() async {
    await _stop();
  }

  // ----------------------------------------------------------
  // 内部
  // ----------------------------------------------------------

  Future<void> _ensureStarted() async {
    if (_proxy?.isRunning == true) return;
    try {
      _proxy = AdBlockProxy(
        onLog: (msg) {
          debugPrint(msg);
          // 写入系统日志（仅调试日志开关开启时生效）
          if (Get.isRegistered<SystemLogService>()) {
            Get.find<SystemLogService>().info(msg);
          }
        },
      );
      await _proxy!.start();
    } catch (e) {
      debugPrint('[AdBlockProxyService] 启动失败: $e');
      if (Get.isRegistered<SystemLogService>()) {
        Get.find<SystemLogService>().error('[AdBlockProxyService] 启动失败: $e');
      }
      _proxy = null;
      _enabled = false;
    }
  }

  Future<void> _stop() async {
    try {
      await _proxy?.stop();
    } catch (e) {
      debugPrint('[AdBlockProxyService] 停止失败: $e');
    }
    _proxy = null;
  }
}