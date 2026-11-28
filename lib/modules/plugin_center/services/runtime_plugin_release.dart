import 'package:get/get.dart';

import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/t4/services/qjs_catvod_service.dart';
import 'package:yuanying/t4/services/qjs_drpy2_service.dart';
import 'package:yuanying/t4/services/qjs_drpy3_service.dart';

/// 运行时插件替换前统一释放宿主资源。
///
/// 目录替换只能保证磁盘事务；Node、Python 以及 QJS isolate 还可能持有
/// 可执行文件、原生库或正在执行的脚本，因此在进入 staging 替换前必须先
/// 关闭这些实例。具体服务是否在下次使用时自动恢复，继续由各运行时自行决定。
abstract final class RuntimePluginRelease {
  static const Set<String> _runtimeIds = {
    'nodejs',
    'nodejs-win',
    'python',
    'python-win',
    'qjs',
    'qjs-arm32',
    'qjs-win',
    'proot',
  };

  static bool requiresRelease(String pluginId) {
    return _runtimeIds.contains(pluginId);
  }

  static Future<void> prepareForReplacement(String pluginId) async {
    await InstallManager.instance.stopRuntimeConsumers(pluginId);
    if (_isQjs(pluginId)) {
      await releaseQjsEngines();
    }
  }

  static Future<void> releaseQjsEngines() async {
    if (Get.isRegistered<QjsDrpy2Service>()) {
      Get.find<QjsDrpy2Service>().dispose();
    }
    if (Get.isRegistered<QjsDrpy3Service>()) {
      Get.find<QjsDrpy3Service>().dispose();
    }
    if (Get.isRegistered<QjsCatVodService>()) {
      await Get.find<QjsCatVodService>().close();
    }

    // isolate kill / close 会异步释放底层引擎句柄，给系统留出释放文件占用
    // 的时间，避免紧接着 rename 目录时与尚未退出的 isolate 竞争。
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  static bool _isQjs(String pluginId) {
    return pluginId == 'qjs' ||
        pluginId == 'qjs-arm32' ||
        pluginId == 'qjs-win';
  }
}
