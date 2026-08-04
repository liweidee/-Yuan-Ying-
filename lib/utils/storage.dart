import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';

import 'storage_web.dart'
    if (dart.library.html) 'storage_web.dart'
    if (dart.library.io) 'storage_stub.dart' as web;

class GStorage {
  static late Box setting;
  static late Box video;
  static late Box historyWord;
  static late Box watchProgress;
  static late Box sitesBox;
  static late Box configPackageBox;

  static Future<void> init() async {
    if (!kIsWeb) {
      final appDocumentDir = await getApplicationDocumentsDirectory();
      Hive.init(appDocumentDir.path);
    }
    setting = await Hive.openBox('setting');
    video = await Hive.openBox('video');
    historyWord = await Hive.openBox('historyWord');
    watchProgress = await Hive.openBox('watchProgress');
    sitesBox = await Hive.openBox('custom_sites');
    configPackageBox = await Hive.openBox('config_package');
  }

  // ===== 配置列表操作 =====
  static Future<void> saveCustomSites(List<Map<String, dynamic>> sites) async {
    if (kIsWeb) {
      web.StorageWebHelper.saveCustomSites(sites);
    } else {
      await sitesBox.put('sites', sites);
    }
  }

  static List<Map<String, dynamic>> getCustomSites() {
    if (kIsWeb) {
      return web.StorageWebHelper.getCustomSites();
    } else {
      final result = sitesBox.get('sites');
      if (result == null) return [];
      return result.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
    }
  }

  static Future<void> addCustomSite(Map<String, dynamic> site) async {
    final sites = getCustomSites();
    sites.add(site);
    await saveCustomSites(sites);
  }

  static Future<void> removeCustomSite(String key) async {
    final sites = getCustomSites();
    sites.removeWhere((s) => s['key'] == key);
    await saveCustomSites(sites);
  }

  static Future<void> updateCustomSite(String key, Map<String, dynamic> newSite) async {
    final sites = getCustomSites();
    final index = sites.indexWhere((s) => s['key'] == key);
    if (index != -1) {
      sites[index] = newSite;
      await saveCustomSites(sites);
    }
  }

  // ===== 配置包操作 =====
  static Future<void> saveConfigPackage(String packageKey, Map<String, dynamic> package) async {
    if (kIsWeb) return;
    await configPackageBox.put(packageKey, package);
  }

  static Map<String, dynamic>? getConfigPackage(String packageKey) {
    if (kIsWeb) return null;
    final result = configPackageBox.get(packageKey);
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<void> deleteConfigPackage(String packageKey) async {
    if (kIsWeb) return;
    await configPackageBox.delete(packageKey);
  }

  // ===== 通用存储 =====
  static Future<void> setSetting(String key, dynamic value) async {
    await setting.put(key, value);
  }

  static T? getSetting<T>(String key, {T? defaultValue}) {
    return setting.get(key, defaultValue: defaultValue);
  }

  static Future<void> deleteSetting(String key) async {
    await setting.delete(key);
  }

  /// 导出所有设置（完整备份）
  static String exportAllSettings() {
    // 只备份远端配置，忽略本地导入的配置
    final allSites = getCustomSites();
    final remoteSites = allSites.where((site) {
      final source = site['_source']?.toString() ?? 'remote';
      return source != 'local';
    }).toList();

    return jsonEncode({
      setting.name: setting.toMap(),
      video.name: video.toMap(),
      historyWord.name: historyWord.toMap(),
      watchProgress.name: watchProgress.toMap(),
      'custom_sites': remoteSites,
      'version': 2,
    });
  }

  /// 导入所有设置（完整恢复）
  static Future<void> importAllSettings(String data) async {
    final map = jsonDecode(data) as Map<String, dynamic>;

    // 恢复 setting
    if (map[setting.name] is Map) {
      await setting.clear();
      await setting.putAll(map[setting.name] as Map);
    }

    // 恢复 video
    if (map[video.name] is Map) {
      await video.clear();
      await video.putAll(map[video.name] as Map);
    }

    // 恢复搜索历史
    if (map[historyWord.name] is Map) {
      await historyWord.clear();
      await historyWord.putAll(map[historyWord.name] as Map);
    }

    // 恢复观看进度
    if (map[watchProgress.name] is Map) {
      await watchProgress.clear();
      await watchProgress.putAll(map[watchProgress.name] as Map);
    }

    // 恢复自定义站点（只恢复远端配置，去重）
    if (map['custom_sites'] is List) {
      final sites = List<Map<String, dynamic>>.from(map['custom_sites']);
      final existingKeys = getCustomSites().map((s) => s['key']?.toString()).toSet();

      for (final site in sites) {
        final key = site['key']?.toString() ?? '';
        if (key.isEmpty) continue;

        if (existingKeys.contains(key)) {
          await removeCustomSite(key);
        }

        site['_source'] = 'remote';
        site.remove('_configKey');
        await addCustomSite(site);
      }
    }
  }

  // ===== 收藏操作 =====
  static List<Map<String, dynamic>> getFavorites() {
    final data = video.get('favorites');
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<void> saveFavorites(List<Map<String, dynamic>> list) async {
    await video.put('favorites', list);
  }

  static Future<void> addFavorite(Map<String, dynamic> item) async {
    final list = getFavorites();
    final exists = list.any((e) => e['vod_id'] == item['vod_id']);
    if (!exists) {
      list.add(item);
      await saveFavorites(list);
    }
  }

  static Future<void> removeFavorite(String vodId) async {
    final list = getFavorites();
    list.removeWhere((e) => e['vod_id'] == vodId);
    await saveFavorites(list);
  }

  static Future<void> clearFavorites() async {
    await video.delete('favorites');
  }

  // ===== 历史操作 =====
  static List<Map<String, dynamic>> getHistory() {
    final data = watchProgress.get('history');
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<void> saveHistory(List<Map<String, dynamic>> list) async {
    await watchProgress.put('history', list);
  }

  static Future<void> addHistory(Map<String, dynamic> item) async {
    final list = getHistory();
    list.removeWhere((e) => e['vod_id'] == item['vod_id']);
    list.insert(0, item);
    if (list.length > 500) {
      list.removeRange(500, list.length);
    }
    await saveHistory(list);
  }

  static Future<void> removeHistory(String vodId) async {
    final list = getHistory();
    list.removeWhere((e) => e['vod_id'] == vodId);
    await saveHistory(list);
  }

  static Future<void> clearHistory() async {
    await watchProgress.delete('history');
  }
}