// lib/modules/manual_source/services/manual_source_store.dart

import 'package:hive_ce/hive.dart';

import '../models/manual_source_item.dart';

abstract final class ManualSourceStore {
  static const boxName = 'manual_source_meta';
  static const orderBoxName = 'manual_source_order';
  static const orderKey = 'order';

  static Box get _box => Hive.box(boxName);
  static Box get _orderBox => Hive.box(orderBoxName);

  static Future<void> ensureOpen() async {
    if (!Hive.isBoxOpen(boxName)) await Hive.openBox(boxName);
    if (!Hive.isBoxOpen(orderBoxName)) await Hive.openBox(orderBoxName);
  }

  static ManualSourceMeta? read(String id) {
    if (!Hive.isBoxOpen(boxName)) return null;
    final raw = _box.get(id);
    if (raw is Map) {
      return ManualSourceMeta.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  static Map<String, ManualSourceMeta> readAll() {
    if (!Hive.isBoxOpen(boxName)) return {};
    final result = <String, ManualSourceMeta>{};
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        result[key.toString()] =
            ManualSourceMeta.fromJson(Map<String, dynamic>.from(raw));
      }
    }
    return result;
  }

  static Future<void> write(String id, ManualSourceMeta meta) async {
    await ensureOpen();
    await _box.put(id, meta.toJson());
  }

  static Future<void> remove(String id) async {
    await ensureOpen();
    await _box.delete(id);
    // 从 order 里清掉
    final order = readOrder();
    if (order.contains(id)) {
      order.remove(id);
      await saveOrder(order);
    }
  }

  // ===== 排序 =====
  static List<String> readOrder() {
    if (!Hive.isBoxOpen(orderBoxName)) return [];
    final raw = _orderBox.get(orderKey);
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  static Future<void> saveOrder(List<String> ids) async {
    await ensureOpen();
    await _orderBox.put(orderKey, ids);
  }
}