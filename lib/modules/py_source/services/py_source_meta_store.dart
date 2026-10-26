// lib/modules/py_source/services/py_source_meta_store.dart

import 'package:hive_ce/hive.dart';

import '../models/py_local_source.dart';

/// 本地 py 源的用户覆盖元数据（Hive 存储）
/// key = 'local_py_{文件名不含后缀}'
abstract final class PySourceMetaStore {
  static const boxName = 'py_source_meta';

  static Box get _box => Hive.box(boxName);

  static Future<void> ensureOpen() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox(boxName);
    }
  }

  static PySourceMeta? read(String siteKey) {
    if (!Hive.isBoxOpen(boxName)) return null;
    final raw = _box.get(siteKey);
    if (raw is Map) {
      return PySourceMeta.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  static Future<void> write(String siteKey, PySourceMeta meta) async {
    await ensureOpen();
    await _box.put(siteKey, meta.toJson());
  }

  static Future<void> remove(String siteKey) async {
    await ensureOpen();
    await _box.delete(siteKey);
  }

  static Map<String, PySourceMeta> readAll() {
    if (!Hive.isBoxOpen(boxName)) return {};
    final result = <String, PySourceMeta>{};
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        result[key.toString()] = PySourceMeta.fromJson(
          Map<String, dynamic>.from(raw),
        );
      }
    }
    return result;
  }
}