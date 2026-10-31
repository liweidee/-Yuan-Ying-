// lib/modules/sandbox/services/sandbox_paths.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';

/// 沙盒路径唯一出口
///
/// 所有路径基于 PluginPaths.dataRoot()（Android = dataDir/files），
/// 与 PluginPaths 的插件目录同根，但不混在一起。
abstract final class SandboxPaths {
  /// 根目录：{dataRoot}/sandbox/
  static Future<Directory> root() async {
    final data = await PluginPaths.dataRoot();
    final dir = Directory(p.join(data.path, 'sandbox'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// rootfs 目录：{sandbox}/rootfs/{distroId}/
  static Future<Directory> rootfs(String distroId) async {
    final root = await SandboxPaths.root();
    final dir = Directory(p.join(root.path, 'rootfs', distroId));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// PROOT_TMP_DIR：{sandbox}/proot-tmp/
  static Future<Directory> prootTmp() async {
    final root = await SandboxPaths.root();
    final dir = Directory(p.join(root.path, 'proot-tmp'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// 下载缓存：{sandbox}/cache/
  static Future<Directory> cache() async {
    final root = await SandboxPaths.root();
    final dir = Directory(p.join(root.path, 'cache'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// 安装标记：{sandbox}/rootfs/{distroId}.installed
  static Future<File> installedMarker(String distroId) async {
    final root = await SandboxPaths.root();
    final dir = Directory(p.join(root.path, 'rootfs'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File(p.join(dir.path, '$distroId.installed'));
  }
}