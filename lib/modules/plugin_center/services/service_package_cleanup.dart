import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';

abstract final class ServicePackageCleanup {
  static Future<void> deleteManagedRoot({
    required ServiceConfig config,
    required Directory servicesRoot,
  }) async {
    final packageRoot = config.packageRoot?.trim();
    final targetPath = packageRoot == null || packageRoot.isEmpty
        ? p.join(servicesRoot.path, config.id)
        : packageRoot;
    if (!PluginPaths.isWithin(servicesRoot, targetPath) ||
        p.equals(targetPath, servicesRoot.path)) {
      throw Exception('拒绝删除越界服务目录：$targetPath');
    }

    final target = Directory(targetPath);
    try {
      if (target.existsSync()) {
        await target.delete(recursive: true);
      }
      if (target.existsSync()) {
        throw Exception('目录仍然存在');
      }
    } catch (e) {
      throw Exception('删除服务目录失败：$e');
    }
  }
}
