// lib/modules/sandbox/services/service_host_bridge.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 前台服务桥接（对齐 DsPlayer 的 com.dsplayer/service_host channel）
///
/// 职责：把沙盒和猫影视 Node 的运行状态同步到原生 ServiceHostService，
///      原生侧负责前台服务保活、通知展示和统一停止。
class ServiceHostBridge {
  ServiceHostBridge._();
  static final ServiceHostBridge instance = ServiceHostBridge._();

  static const _ch = MethodChannel('com.example.yuanying/service_host');

  /// 同步沙盒服务 PID。
  ///
  /// pids 为空只表示当前没有沙盒服务；原生服务仍可能因猫影视 Node
  /// 处于活跃状态而继续运行。
  Future<bool> sync({
    required List<int> pids,
    int? serviceCount,
    int? pluginCount,
    String? gateway,
  }) async {
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

  /// 同步猫影视 Node 保活状态。
  ///
  /// [active] 表示当前配置是否仍需要猫影视 Node。Node 重启期间可以
  /// active=true、pid=null，以保持前台服务不中断。
  Future<bool> syncCatVod({required bool active, int? pid}) async {
    try {
      final ok = await _ch.invokeMethod<bool>('syncCatVod', {
        'active': active,
        if (active && pid != null && pid > 0) 'pid': pid,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[ServiceHostBridge] syncCatVod failed: $e');
      return false;
    }
  }

  /// 消费通知栏“全部停止”留下的猫影视停止标记。
  Future<bool> consumeCatVodStopRequest() async {
    try {
      return await _ch.invokeMethod<bool>('consumeCatVodStopRequest') ?? false;
    } catch (e) {
      debugPrint('[ServiceHostBridge] consumeCatVodStopRequest failed: $e');
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
