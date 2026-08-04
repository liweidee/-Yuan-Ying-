import 'dart:io';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/utils/platform_utils.dart';

abstract final class CacheManager {
  static late final DefaultCacheManager manager;

  static Future<void> ensureInitialized() =>
      DefaultCacheManager.init().then((i) => manager = i);

  /// 加载应用缓存总大小
  static Future<int> loadApplicationCache() async {
    try {
      final tempDirectory = await getTemporaryDirectory();
      if (PlatformUtils.isDesktop) {
        return manager.getTotalLength();
      }
      if (tempDirectory.existsSync()) {
        return await _getTotalSizeOfFilesInDir(tempDirectory);
      }
    } catch (_) {}
    return 0;
  }

  static Future<int> _getTotalSizeOfFilesInDir(Directory file) async {
    int total = 0;
    await for (final child in file.list(recursive: false)) {
      if (child is File) {
        total += await child.length();
      } else if (child is Directory) {
        if (path.equals(child.path, manager.cacheDir)) {
          total += manager.getTotalLength();
        } else {
          await for (final i in child.list(recursive: true)) {
            if (i is File) {
              total += await i.length();
            }
          }
        }
      }
    }
    return total;
  }

  /// 格式化缓存大小
  static String formatSize(num value) {
    const unitArr = ['B', 'K', 'M', 'G', 'T', 'P'];
    int index = 0;
    var v = value.toDouble();
    while (v >= 1024) {
      index++;
      v = v / 1024;
    }
    return '${v.toStringAsFixed(2)}${unitArr[index]}';
  }

  /// 清空 Library/Caches 目录及文件缓存
  static Future<void> clearLibraryCache() async {
    try {
      await manager.emptyCache();
      if (PlatformUtils.isDesktop) return;

      final tempDirectory = await getTemporaryDirectory();
      if (tempDirectory.existsSync()) {
        await for (final file in tempDirectory.list(recursive: false)) {
          if (file is Directory && path.equals(file.path, manager.cacheDir)) {
            continue;
          }
          await file.delete(recursive: true);
        }
      }
    } catch (_) {}
  }

  /// 自动清除缓存（根据设置判断）
  static Future<void> autoClearCache() async {
    if (SettingPref.autoClearCache) {
      await clearLibraryCache();
    } else {
      final maxCacheSize = SettingPref.maxCacheSize;
      if (maxCacheSize != 0) {
        final currCache = await loadApplicationCache();
        if (currCache >= maxCacheSize) {
          await clearLibraryCache();
        }
      }
    }
  }
}