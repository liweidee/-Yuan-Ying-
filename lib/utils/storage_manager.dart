import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_ce/hive_ce.dart';
import 'package:yuanying/core/constants/storage_keys.dart';

// Web 端内存存储
Map<String, dynamic>? _memoryStorage;

class StorageManager {
  static late Box _settingBox;
  static late Box _cacheBox;

  static Future<void> init() async {
    if (kIsWeb) {
      // Web 端使用内存
      _memoryStorage = {};
      return;
    }
    _settingBox = await Hive.openBox(StorageKeys.settingBox);
    _cacheBox = await Hive.openBox(StorageKeys.cacheBox);
  }

  /// 生成带源标识的进度 key
  /// [prefix] 如 'novel_progress' / 'manga_progress'
  /// [apiUrl] 为空时退化为旧格式（仅 vodId），兼容极老记录
  static String progressKey(String prefix, String vodId, String? apiUrl) {
      if (apiUrl == null || apiUrl.isEmpty) return '${prefix}_$vodId';
      return '${prefix}_${vodId}_${_stableHash(apiUrl)}';
  }

  /// 给任意 base key 附加源标识
  ///
  /// 用于章节内容缓存、书签、净化规则等非"进度"数据
  /// [baseKey] 原 base key，如 'novel_chapter_12345_5'
  /// [apiUrl] 为空时返回原 baseKey（兼容无源信息场景）
  static String sourceScopedKey(String baseKey, String? apiUrl) {
      if (apiUrl == null || apiUrl.isEmpty) return baseKey;
      return '${baseKey}_${_stableHash(apiUrl)}';
  }

  /// 跨进程稳定的字符串 hash
  /// 不能用 String.hashCode —— 它在不同进程/重启后可能不同
  static String _stableHash(String s) {
      var hash = 0;
      for (final code in s.codeUnits) {
        hash = (hash * 31 + code) & 0x7fffffff;
      }
      return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<void> setSetting(String key, dynamic value) async {
    if (kIsWeb) {
      _memoryStorage?[key] = value;
      return;
    }
    await _settingBox.put(key, value);
  }

  static T? getSetting<T>(String key, {T? defaultValue}) {
    if (kIsWeb) {
      final value = _memoryStorage?[key];
      if (value is T) return value;
      return defaultValue;
    }

    final raw = _settingBox.get(key);
    if (raw == null) return defaultValue;
    if (raw is T) return raw;

    // ------------------------------------------------------------------
    // 兼容 Hive 序列化 List<T> 后取回变成 List<dynamic> 的问题
    // Hive 不保留泛型参数，直接 `as List<int>` 会抛 TypeError
    // ------------------------------------------------------------------
    if (raw is List) {
      final t = T.toString();
      try {
        if (t.contains('List<int>')) {
          return raw.cast<int>().toList() as T;
        }
        if (t.contains('List<double>')) {
          return raw.cast<double>().toList() as T;
        }
        if (t.contains('List<String>')) {
          return raw.cast<String>().toList() as T;
        }
        if (t.contains('List<bool>')) {
          return raw.cast<bool>().toList() as T;
        }
        if (t.contains('List<num>')) {
          return raw.cast<num>().toList() as T;
        }
        if (t.contains('List<dynamic>')) {
          return List<dynamic>.from(raw) as T;
        }
      } catch (_) {
        // 转换失败（例如元素类型不对）→ 回落到 defaultValue
      }
    }

    // 其它无法兼容的情况：返回默认值，绝不抛异常
    return defaultValue;
  }

  static Future<void> deleteSetting(String key) async {
    if (kIsWeb) {
      _memoryStorage?.remove(key);
      return;
    }
    await _settingBox.delete(key);
  }

  static Future<void> resetSettingBox() async {
    if (kIsWeb) {
      _memoryStorage?.clear();
      return;
    }
    await _settingBox.clear();
  }

  static Future<void> setCache(String key, dynamic value) async {
    if (kIsWeb) {
      _memoryStorage?['cache_$key'] = value;
      return;
    }
    await _cacheBox.put(key, value);
  }

  static T? getCache<T>(String key, {T? defaultValue}) {
    if (kIsWeb) {
      final value = _memoryStorage?['cache_$key'];
      if (value is T) return value;
      return defaultValue;
    }
    return _cacheBox.get(key, defaultValue: defaultValue);
  }

  static Future<void> deleteCache(String key) async {
    if (kIsWeb) {
      _memoryStorage?.remove('cache_$key');
      return;
    }
    await _cacheBox.delete(key);
  }

  static Future<void> clearCache() async {
    if (kIsWeb) {
      _memoryStorage?.removeWhere((key, _) => key.startsWith('cache_'));
      return;
    }
    await _cacheBox.clear();
  }
}