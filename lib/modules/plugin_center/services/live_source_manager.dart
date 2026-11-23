import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/models/live/live_config.dart';
import 'package:yuanying/utils/storage_manager.dart';

class LiveSourceImportResult {
  final List<String> managedKeys;
  final int added;
  final int removed;
  final int updated;

  const LiveSourceImportResult({
    required this.managedKeys,
    required this.added,
    required this.removed,
    required this.updated,
  });

  bool get hasChanges => managedKeys.isNotEmpty || removed > 0 || updated > 0;
}

abstract final class LiveSourceManager {
  static Future<LiveSourceImportResult> applyPackage({
    required List<dynamic> lives,
    required Set<String> previousManagedKeys,
    required bool replaceManaged,
    bool claimExistingNames = false,
    bool overwriteExistingNames = false,
  }) async {
    final existingRaw =
        StorageManager.getSetting<List<dynamic>>(SettingBoxKey.liveConfigs) ??
        [];
    final existing = existingRaw
        .map((e) => LiveConfig.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    var removed = 0;
    if (replaceManaged && previousManagedKeys.isNotEmpty) {
      final before = existing.length;
      existing.removeWhere(
        (config) => previousManagedKeys.contains(config.key),
      );
      removed = before - existing.length;
    }

    final existingByName = <String, LiveConfig>{
      for (final config in existing) config.name: config,
    };
    final existingNames = existingByName.keys.toSet();
    final managedKeys = <String>{};
    final processedNames = <String>{};
    var added = 0;
    var updated = 0;

    for (final item in lives) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      // 同一包内重复名字按首次出现处理，避免反复覆盖同一线路。
      if (!processedNames.add(name)) continue;

      final current = existingByName[name];
      if (overwriteExistingNames && current != null) {
        // 版本化包重装采用同名 upsert：保留原 key，更新线路字段，
        // 并重新认领该线路。即使内容完全一致也视为一次成功重装。
        final index = existing.indexWhere((c) => c.key == current.key);
        if (index != -1) {
          final replacement = LiveConfig(
            key: current.key,
            name: name,
            url: item['url']?.toString() ?? '',
            ua: item['ua']?.toString(),
            epg: item['epg']?.toString(),
            logo: item['logo']?.toString(),
          );
          existing[index] = replacement;
          existingByName[name] = replacement;
          managedKeys.add(current.key);
          updated++;
          continue;
        }
      }

      if (existingNames.contains(name)) {
        if (claimExistingNames &&
            !replaceManaged &&
            current != null &&
            !previousManagedKeys.contains(current.key)) {
          managedKeys.add(current.key);
        }
        continue;
      }

      final newConfig = LiveConfig(
        key: _generateKey(name, existing),
        name: name,
        url: item['url']?.toString() ?? '',
        ua: item['ua']?.toString(),
        epg: item['epg']?.toString(),
        logo: item['logo']?.toString(),
      );
      existing.add(newConfig);
      existingNames.add(name);
      existingByName[name] = newConfig;
      managedKeys.add(newConfig.key);
      added++;
    }

    if (added > 0 || removed > 0 || updated > 0) {
      await StorageManager.setSetting(
        SettingBoxKey.liveConfigs,
        existing.map((c) => c.toJson()).toList(),
      );
    }

    return LiveSourceImportResult(
      managedKeys: managedKeys.toList(),
      added: added,
      removed: removed,
      updated: updated,
    );
  }

  static String _generateKey(String name, List<LiveConfig> existing) {
    var base = name
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w]'), '');
    if (base.isEmpty) base = 'live';
    var key = base;
    var index = 1;
    final keys = existing.map((c) => c.key).toSet();
    while (keys.contains(key)) {
      key = '${base}_$index';
      index++;
    }
    return key;
  }
}
