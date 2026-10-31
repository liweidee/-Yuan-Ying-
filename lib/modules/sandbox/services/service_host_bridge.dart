// lib/modules/sandbox/services/service_host_bridge.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 前台服务桥接（对齐 DsPlayer 的 com.dsplayer/service_host channel）
///
/// 职责：把 SandboxServiceManager 中所有运行中的子进程 PID 同步到原生
///      ServiceHostService，原生侧负责保活（App 退后台不被回收）。
class ServiceHostBridge {
  ServiceHostBridge._();
  static final ServiceHostBridge instance = ServiceHostBridge._();

  static const _ch = MethodChannel('com.example.yuanying/service_host');

  /// 同步 PID 列表到原生前台服务
  ///
  /// pids 为空时调用 stopAll（让前台服务自行退出）
  Future<bool> sync({
    required List<int> pids,
    int? serviceCount,
    int? pluginCount,
    String? gateway,
  }) async {
    if (pids.isEmpty) {
      await stopAll();
      return true;
    }
    try {
      final ok = await _ch.invokeMethod<bool>('start', {
        'pids': pids,
        'count': pids.length,
        if (serviceCount != null) 'services': serviceCount,
        if (pluginCount != null) 'plugins': pluginCount,
        if (gateway != null) 'gw': gateway,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[ServiceHostBridge] sync failed: $e');
      return false;
    }
  }

  Future<void> stopAll() async {
    try {
      await _ch.invokeMethod<bool>('stopAll');
    } catch (e) {
      debugPrint('[ServiceHostBridge] stopAll failed: $e');
    }
  }
}