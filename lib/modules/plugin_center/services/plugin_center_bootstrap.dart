// lib/modules/plugin_center/services/plugin_center_bootstrap.dart

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/market_manager.dart';
import 'package:yuanying/modules/plugin_center/services/port_cleaner.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/t4/services/python_runtime.dart';

/// 插件中心启动引导
/// 在 main() 里 Hive 初始化完成后调用
abstract final class PluginCenterBootstrap {
  /// 初始化（不阻塞 UI）
  static Future<void> init() async {
    // 1. 确保市场源至少有一个默认
    try {
      await MarketManager.instance.ensureDefaultSource();
    } catch (e) {
      debugPrint('[PluginCenterBootstrap] ensureDefaultSource failed: $e');
    }

    // 1.5 应用 py 插件保活开关（Android only）
    // 用 Future.microtask 延迟到 Flutter 引擎就绪后执行，避免 channel 未注册
    if (Platform.isAndroid) {
      Future.microtask(() async {
        try {
          final pyPlugin = InstallManager.instance.findInstalled('py');
          if (pyPlugin != null) {
            final keepAlive = pyPlugin.extras['pyKeepAlive'] == true;
            await PythonRuntime.androidSetKeepAlive(keepAlive);
            debugPrint('[PluginCenterBootstrap] py 保活 = $keepAlive');
          }
        } catch (e) {
          debugPrint('[PluginCenterBootstrap] 应用 py 保活失败: $e');
        }
      });
    }

    // 2. 延迟执行自动清理 + 自启动（不阻塞主线程）
    Future.microtask(() async {
      try {
        await PortCleaner.autoCleanIfEnabled();
      } catch (e) {
        debugPrint('[PluginCenterBootstrap] autoClean failed: $e');
      }
      try {
        await ServiceManager.instance.autoStartAll();
      } catch (e) {
        debugPrint('[PluginCenterBootstrap] autoStartAll failed: $e');
      }
    });
  }

  /// App 关闭时调用
  static Future<void> shutdown() async {
    await ServiceManager.instance.shutdown();
  }
}