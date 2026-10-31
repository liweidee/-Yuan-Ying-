// lib/modules/sandbox/models/sandbox_pref.dart
import 'package:hive_ce/hive.dart';

/// 沙盒偏好设置（下载源 + 软件源）
abstract final class SandboxPref {
  static const String boxName = 'sandbox_pref';

  static Box get _box => Hive.box(boxName);

  // ============================================================
  // 下载源：'auto' | '华为云' | '清华' | '官方'
  // 默认 'auto'（自动 fallback）
  // ============================================================
  static String get downloadMirror =>
      _box.get('downloadMirror', defaultValue: 'auto') as String;

  static Future<void> setDownloadMirror(String v) =>
      _box.put('downloadMirror', v);

  // ============================================================
  // 软件源：'aliyun' | 'tuna' | 'huawei' | 'official'
  // 默认 Alpine 用 aliyun，Ubuntu 用 tuna
  // ============================================================
  static String get softwareMirror =>
      _box.get('softwareMirror', defaultValue: 'aliyun') as String;

  static Future<void> setSoftwareMirror(String v) =>
      _box.put('softwareMirror', v);

  /// 按 distro 返回默认软件源（用户在安装时未显式选择时用）
  static String defaultSoftwareMirrorFor(String distroId) {
    switch (distroId) {
      case 'alpine':
        return 'aliyun';
      case 'ubuntu':
        return 'tuna';
      default:
        return 'official';
    }
  }
}