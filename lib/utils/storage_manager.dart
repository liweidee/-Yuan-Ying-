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
    return _settingBox.get(key, defaultValue: defaultValue);
  }

  static Future<void> deleteSetting(String key) async {
    if (kIsWeb) {
      _memoryStorage?.remove(key);
      return;
    }
    await _settingBox.delete(key);
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