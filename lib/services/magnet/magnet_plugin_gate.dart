import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/services/magnet/magnet_models.dart';
import 'package:yuanying/services/magnet/magnet_plugin_service.dart';

abstract final class MagnetPluginGate {
  static MagnetPluginAvailability check() {
    return MagnetPluginService.instance.checkAvailability();
  }

  static Future<bool> ensureReady({bool showGuide = true}) async {
    final availability = check();
    if (availability.isReady) return true;
    if (!showGuide) return false;

    if (availability.state == MagnetPluginState.unsupportedPlatform ||
        availability.state == MagnetPluginState.unsupportedAbi) {
      SmartDialog.showToast(availability.message);
      return false;
    }

    final context = Get.context;
    if (context == null) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要磁力播放插件'),
        content: Text(availability.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              availability.state == MagnetPluginState.notInstalled
                  ? '前往市场'
                  : '前往开启',
            ),
          ),
        ],
      ),
    );
    if (go != true) return false;

    final initialTab = availability.state == MagnetPluginState.notInstalled
        ? 2
        : 0;
    await Get.toNamed(
      AppPages.pluginCenter,
      arguments: {'initialTab': initialTab},
    );
    return false;
  }
}
