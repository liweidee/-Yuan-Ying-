// lib/modules/sandbox/services/sandbox_service_store.dart
import 'package:hive_ce/hive.dart';

import 'package:yuanying/modules/sandbox/models/sandbox_service.dart';

/// 沙盒服务持久化（Hive）
abstract final class SandboxServiceStore {
  static const String boxName = 'sandbox_services';
  static const String listKey = 'list';

  static Box get _box => Hive.box(boxName);

  /// 在 main.dart 中调用一次
  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox(boxName);
    }
  }

  static List<SandboxService> getAll() {
    if (!Hive.isBoxOpen(boxName)) return [];
    final raw = _box.get(listKey);
    if (raw is! List) return [];
    return raw
        .map((e) =>
            SandboxService.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> _saveAll(List<SandboxService> list) async {
    await _box.put(listKey, list.map((e) => e.toJson()).toList());
  }

  static Future<void> addOrUpdate(SandboxService service) async {
    final list = getAll();
    final idx = list.indexWhere((e) => e.id == service.id);
    if (idx >= 0) {
      list[idx] = service;
    } else {
      list.add(service);
    }
    await _saveAll(list);
  }

  static Future<void> remove(String id) async {
    final list = getAll();
    list.removeWhere((e) => e.id == id);
    await _saveAll(list);
  }
}