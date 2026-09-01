import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'; // DefaultCacheManager 在这里
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/utils/platform_utils.dart';

abstract final class CacheManager {
  static final DefaultCacheManager manager = DefaultCacheManager();

  static Future<void> ensureInitialized() async {
    // DefaultCacheManager 构造函数直接返回单例，无需 init()
  }

  /// 加载应用缓存总大小
  static Future<int> loadApplicationCache() async {
    try {
      final tempDirectory = await getTemporaryDirectory();
      if (tempDirectory.existsSync()) {
        return await _getTotalSizeOfFilesInDir(tempDirectory);
      }
    } catch (_) {}
    return 0;
  }

  static Future<int> _getTotalSizeOfFilesInDir(Directory dir) async {
    int total = 0;
    try {
      await for (final child in dir.list(recursive: false)) {
        if (child is File) {
          total += await child.length();
        } else if (child is Directory) {
          total += await _getTotalSizeOfFilesInDir(child);
        }
      }
    } catch (_) {}
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

  /// 清空缓存
  static Future<void> clearLibraryCache() async {
    try {
      await manager.emptyCache();

      if (!PlatformUtils.isDesktop) {
        final tempDirectory = await getTemporaryDirectory();
        if (tempDirectory.existsSync()) {
          await for (final file in tempDirectory.list(recursive: false)) {
            await file.delete(recursive: true);
          }
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