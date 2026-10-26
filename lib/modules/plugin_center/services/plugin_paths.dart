// lib/modules/plugin_center/services/plugin_paths.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 插件中心所有路径的唯一出口
/// 落盘根：
///   Android：{support}/      （应用私有目录，零存储权限）
///   桌面端：{support}/
///   ├── plugins/   插件（目录不带版本号，升级覆盖）
///   └── services/  服务
abstract final class PluginPaths {
  static Directory? _rootCache;

  /// 数据根：应用私有 support 目录（Android 与桌面端一致，不再套子目录）
  static Future<Directory> dataRoot() async {
    if (_rootCache != null && _rootCache!.existsSync()) return _rootCache!;
    final support = await getApplicationSupportDirectory();
    final root = Directory(support.path);
    if (!root.existsSync()) {
      await root.create(recursive: true);
    }
    _rootCache = root;
    return root;
  }

  /// 插件根：{support}/plugins/
  static Future<Directory> root() async {
    final data = await dataRoot();
    final dir = Directory(p.join(data.path, 'plugins'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// 服务根：{support}/services/
  static Future<Directory> servicesRoot() async {
    final data = await dataRoot();
    final dir = Directory(p.join(data.path, 'services'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// 下载临时目录：{support}/plugins/cache/download/
  static Future<Directory> downloadDir() async {
    final root = await PluginPaths.root();
    final dir = Directory(p.join(root.path, 'cache', 'download'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// 已装插件目录：{support}/plugins/{id}/
  /// 注：目录不带版本号，升级覆盖；版本由 Hive 登记表维护
  static Future<Directory> pluginDir(String id, String version) async {
    final root = await PluginPaths.root();
    final dir = Directory(p.join(root.path, id));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// 服务数据目录：{support}/services/{serviceId}/
  static Future<Directory> serverDir(String serviceId) async {
    final root = await PluginPaths.servicesRoot();
    final dir = Directory(p.join(root.path, serviceId));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// 下载临时文件：{support}/plugins/cache/download/{id}-{version}.zip
  static Future<String> downloadFilePath(String id, String version) async {
    final dir = await downloadDir();
    return p.join(dir.path, '$id-$version.zip');
  }

  /// 已装插件目录是否存在
  static Future<bool> isPluginInstalled(String id, String version) async {
    final root = await PluginPaths.root();
    return Directory(p.join(root.path, id)).existsSync();
  }

  /// 从图标路径（相对或绝对）解析出本地 File 或远端 URL
  static Future<String?> resolveIcon({
    required String? icon,
    required String indexBaseUrl,
  }) async {
    if (icon == null || icon.isEmpty) return null;
    if (icon.startsWith('http://') || icon.startsWith('https://')) {
      return icon;
    }
    if (indexBaseUrl.isNotEmpty) {
      final idx = indexBaseUrl.lastIndexOf('/');
      if (idx > 0) {
        return '${indexBaseUrl.substring(0, idx + 1)}$icon';
      }
    }
    return null;
  }

  /// Android：把插件内的二进制复制到可执行目录并 chmod 755。
  /// 返回可直接 Process.start 的绝对路径；失败时回退返回 srcPath。
  /// 非 Android 平台原样返回 srcPath。
  static Future<String> prepareAndroidExecutable(String srcPath) async {
    if (!Platform.isAndroid) return srcPath;
    try {
      final cache = await getApplicationCacheDirectory();
      final execDir = Directory(p.join(cache.path, 'exec'));
      if (!execDir.existsSync()) {
        await execDir.create(recursive: true);
      }
      final destPath = p.join(execDir.path, p.basename(srcPath));
      final dest = File(destPath);
      final src = File(srcPath);
      if (!dest.existsSync() || dest.lengthSync() != src.lengthSync()) {
        await src.copy(destPath);
      }
      await Process.run('chmod', ['755', destPath]);
      return destPath;
    } catch (e) {
      debugPrint('[PluginPaths] prepareAndroidExecutable failed: $e');
      return srcPath;
    }
  }
}