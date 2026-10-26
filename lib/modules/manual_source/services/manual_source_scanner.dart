// lib/modules/manual_source/services/manual_source_scanner.dart

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/manual_source_item.dart';
import 'manual_source_store.dart';

abstract final class ManualSourceScanner {
  static Future<Directory> spiderRoot() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'spider'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> typeDir(ManualSourceType type) async {
    final root = await spiderRoot();
    final dir = Directory(p.join(root.path, type.dirName));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<ManualSourceItem>> scanAll() async {
    await ManualSourceStore.ensureOpen();
    final metas = ManualSourceStore.readAll();
    final order = ManualSourceStore.readOrder();
    final result = <ManualSourceItem>[];

    // 1. 扫描文件源
    for (final type in ManualSourceType.values) {
      if (!type.isFileBased) continue;
      final dir = await typeDir(type);
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        if (!e.path.toLowerCase().endsWith('.${type.ext}')) continue;
        try {
          final stat = await e.stat();
          final name = p.basenameWithoutExtension(e.path);
          final id = 'manual_${type.name}_$name';
          final meta = metas[id];
          result.add(ManualSourceItem(
            type: type,
            name: name,
            path: e.path,
            size: stat.size,
            modified: stat.modified,
            disabled: meta?.disabled ?? false,
            searchable: meta?.searchable ?? 1,
            filterable: meta?.filterable ?? 1,
            quickSearch: meta?.quickSearch ?? 1,
            ext: meta?.ext ?? '',
          ));
        } catch (_) {}
      }
    }

    // 2. 从 meta 反序列化 T4 源
    for (final entry in metas.entries) {
      final id = entry.key;
      if (!id.startsWith('manual_t4_')) continue;
      final meta = entry.value;
      if (meta.api == null || meta.api!.isEmpty) continue;
      result.add(ManualSourceItem(
        type: ManualSourceType.t4,
        name: meta.name ?? id.substring('manual_t4_'.length),
        path: meta.api!,
        size: 0,
        modified: DateTime.fromMillisecondsSinceEpoch(0),
        disabled: meta.disabled,
        searchable: meta.searchable,
        filterable: meta.filterable,
        quickSearch: meta.quickSearch,
        ext: meta.ext ?? '',
      ));
    }

    // 3. 按 order 排序；order 里没有的 append
    if (order.isEmpty) {
      // 首次：默认按类型 + 名称排序，并写入 order
      result.sort((a, b) {
        final t = a.type.index.compareTo(b.type.index);
        if (t != 0) return t;
        return a.name.compareTo(b.name);
      });
      await ManualSourceStore.saveOrder(result.map((e) => e.id).toList());
      return result;
    }

    final orderIndex = <String, int>{};
    for (int i = 0; i < order.length; i++) {
      orderIndex[order[i]] = i;
    }
    // 清理 order 里已不存在的 id
    final validIds = result.map((e) => e.id).toSet();
    final cleanedOrder = order.where(validIds.contains).toList();

    result.sort((a, b) {
      final ai = orderIndex[a.id];
      final bi = orderIndex[b.id];
      if (ai == null && bi == null) return a.name.compareTo(b.name);
      if (ai == null) return 1; // 新源排末尾
      if (bi == null) return -1;
      return ai.compareTo(bi);
    });

    // 用新的 id 列表覆盖 order
    if (cleanedOrder.length != order.length) {
      await ManualSourceStore.saveOrder(result.map((e) => e.id).toList());
    }

    return result;
  }

  static Future<String> saveBytes(
    ManualSourceType type,
    String fileName,
    List<int> bytes,
  ) async {
    final dir = await typeDir(type);
    var base = p.basenameWithoutExtension(fileName);
    var target = File(p.join(dir.path, '$base.${type.ext}'));
    int i = 1;
    while (target.existsSync()) {
      target = File(p.join(dir.path, '${base}_$i.${type.ext}'));
      i++;
    }
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  static Future<void> deleteFile(ManualSourceItem item) async {
    if (!item.type.isFileBased) return;
    final f = File(item.path);
    if (f.existsSync()) await f.delete();
  }
}