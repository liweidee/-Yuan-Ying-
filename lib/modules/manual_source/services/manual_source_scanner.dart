// lib/modules/manual_source/services/manual_source_scanner.dart

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/manual_source_item.dart';
import '../models/web_source_meta.dart';
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

    // 1. 扫描文件源（html 特殊处理：聚合 .web.json / .html）
    for (final type in ManualSourceType.values) {
      if (!type.isFileBased) continue;

      if (type == ManualSourceType.html) {
        await _scanHtmlDir(result, metas);
        continue;
      }

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

    // 2. T4 源
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

    // 3. 排序
    if (order.isEmpty) {
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
    final validIds = result.map((e) => e.id).toSet();
    final cleanedOrder = order.where(validIds.contains).toList();

    result.sort((a, b) {
      final ai = orderIndex[a.id];
      final bi = orderIndex[b.id];
      if (ai == null && bi == null) return a.name.compareTo(b.name);
      if (ai == null) return 1;
      if (bi == null) return -1;
      return ai.compareTo(bi);
    });

    if (cleanedOrder.length != order.length) {
      await ManualSourceStore.saveOrder(result.map((e) => e.id).toList());
    }

    return result;
  }

  /// 扫描 html/ 目录，聚合 .web.json / .html / .js
  static Future<void> _scanHtmlDir(
    List<ManualSourceItem> result,
    Map<String, ManualSourceMeta> metas,
  ) async {
    final dir = await typeDir(ManualSourceType.html);

    // 收集所有文件：baseName → File，并区分类型
    final webJsonMap = <String, File>{}; // xxx.web.json → xxx
    final htmlMap = <String, File>{};    // xxx.html → xxx
    // final jsSet = <String>{};         // 孤立 js 不处理，也不需要单独存

    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final fileName = p.basename(e.path);
      final lower = fileName.toLowerCase();

      if (lower.endsWith('.web.json')) {
        final base = fileName.substring(0, fileName.length - '.web.json'.length);
        webJsonMap[base] = e;
      } else if (lower.endsWith('.html')) {
        final base = p.basenameWithoutExtension(fileName);
        htmlMap[base] = e;
      }
      // .js 视为配套文件，不独立成源
    }

    // 合并所有基名
    final allBases = <String>{...webJsonMap.keys, ...htmlMap.keys};

    for (final base in allBases) {
      // 优先用 web.json，其次 .html
      final file = webJsonMap[base] ?? htmlMap[base];
      if (file == null) continue;

      try {
        final stat = await file.stat();

        // 显示名：优先读 web.json 的 name
        String? customDisplayName;
        if (file.path.toLowerCase().endsWith('.web.json')) {
          try {
            final content = await file.readAsString();
            final parsed = WebSourceMeta.parse(content);
            if (parsed != null && parsed.name.isNotEmpty) {
              final cleaned = parsed.name
                  .replaceAll(RegExp(r'\(WEB\)', caseSensitive: false), '')
                  .trim();
              if (cleaned.isNotEmpty) customDisplayName = cleaned;
            }
          } catch (_) {}
        }

        // meta id 兼容：新 → manual_html_xxx；旧 → manual_web_xxx
        final htmlId = 'manual_html_$base';
        final webId = 'manual_web_$base';
        final meta = metas[htmlId] ?? metas[webId];

        result.add(ManualSourceItem(
          type: ManualSourceType.html,
          name: base,
          path: file.path,
          size: stat.size,
          modified: stat.modified,
          disabled: meta?.disabled ?? false,
          searchable: meta?.searchable ?? 1,
          filterable: meta?.filterable ?? 1,
          quickSearch: meta?.quickSearch ?? 1,
          ext: meta?.ext ?? '',
          customDisplayName: customDisplayName,
        ));
      } catch (_) {}
    }
  }

  /// 保存文件
  /// - HTML 类型：保留原文件名（.web.json / .html / .js），冲突时加数字后缀但不改扩展
  /// - 其他类型：单文件，重命名 `base.ext`
  static Future<String> saveBytes(
    ManualSourceType type,
    String fileName,
    List<int> bytes,
  ) async {
    final dir = await typeDir(type);

    if (type == ManualSourceType.html) {
      var target = File(p.join(dir.path, fileName));
      int i = 1;
      while (target.existsSync()) {
        final lower = fileName.toLowerCase();
        String renamed;
        if (lower.endsWith('.web.json')) {
          final base = fileName.substring(0, fileName.length - 9);
          renamed = '${base}_$i.web.json';
        } else if (lower.endsWith('.html')) {
          final base = fileName.substring(0, fileName.length - 5);
          renamed = '${base}_$i.html';
        } else if (lower.endsWith('.js')) {
          final base = fileName.substring(0, fileName.length - 3);
          renamed = '${base}_$i.js';
        } else {
          final ext = p.extension(fileName);
          final base = fileName.substring(0, fileName.length - ext.length);
          renamed = '${base}_$i$ext';
        }
        target = File(p.join(dir.path, renamed));
        i++;
      }
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    }

    // 其他类型原逻辑
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

  /// 删除
  /// - HTML 类型：删除主文件（.web.json / .html）及同名配套 .js
  /// - 其他类型：删除单文件
  static Future<void> deleteFile(ManualSourceItem item) async {
    if (!item.type.isFileBased) return;
    final f = File(item.path);
    if (f.existsSync()) await f.delete();

    if (item.type == ManualSourceType.html) {
      final lower = item.path.toLowerCase();
      String? jsPath;
      if (lower.endsWith('.web.json')) {
        jsPath = item.path.replaceAll('.web.json', '.js');
      } else if (lower.endsWith('.html')) {
        jsPath = item.path.replaceAll('.html', '.js');
      }
      if (jsPath != null) {
        final js = File(jsPath);
        if (js.existsSync()) await js.delete();
      }
    }
  }
}