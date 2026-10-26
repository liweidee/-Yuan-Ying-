// lib/modules/py_source/services/py_source_scanner.dart

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/py_local_source.dart';

/// 扫描应用私有目录 files/spider/hipy 下的 .py 文件
abstract final class PySourceScanner {
  static Future<Directory> hipyDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'spider', 'hipy'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<PyLocalSource>> scan({
    Map<String, PySourceMeta>? metaMap,
  }) async {
    final dir = await hipyDir();
    final result = <PyLocalSource>[];
    if (!dir.existsSync()) return result;

    final metas = metaMap ?? {};

    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      if (!e.path.toLowerCase().endsWith('.py')) continue;
      try {
        final stat = await e.stat();
        final name = p.basenameWithoutExtension(e.path);
        final header = await _parseHeader(e);
        result.add(PyLocalSource(
          name: name,
          path: e.path,
          size: stat.size,
          modified: stat.modified,
          header: header,
          meta: metas['local_py_$name'],
        ));
      } catch (_) {}
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  /// 解析文件头部的 @header({...})
  static Future<PySourceHeader> _parseHeader(File f) async {
    try {
      // 只读前 8KB，够覆盖 @header
      final raf = await f.open();
      final bytes = await raf.read(8192);
      await raf.close();
      final text = utf8.decode(bytes, allowMalformed: true);
      final start = text.indexOf('@header(');
      if (start < 0) return const PySourceHeader();
      final braceStart = text.indexOf('{', start);
      if (braceStart < 0) return const PySourceHeader();
      // 找配对右括号
      int depth = 0;
      int end = -1;
      for (int i = braceStart; i < text.length; i++) {
        final c = text[i];
        if (c == '{') depth++;
        if (c == '}') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }
      if (end < 0) return const PySourceHeader();
      final jsonStr = text.substring(braceStart, end + 1);
      // @header 语法是 JS 对象字面量（key 无引号），需宽松解析
      final normalized = _normalizeJsObject(jsonStr);
      final m = jsonDecode(normalized) as Map<String, dynamic>;
      return PySourceHeader(
        title: m['title']?.toString(),
        searchable: _toInt(m['searchable']),
        filterable: _toInt(m['filterable']),
        quickSearch: _toInt(m['quickSearch']),
        lang: m['lang']?.toString(),
        type: m['type']?.toString(),
        icon: m['icon']?.toString(),
      );
    } catch (_) {
      return const PySourceHeader();
    }
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// 把 JS 对象字面量的单引号 key/value 转成合法 JSON
  static String _normalizeJsObject(String raw) {
    var s = raw;
    // key 无引号 → 加双引号
    s = s.replaceAllMapped(
      RegExp(r"([{,]\s*)([a-zA-Z_$][a-zA-Z0-9_$]*)(\s*:)"),
      (m) => '${m[1]}"${m[2]}"${m[3]}',
    );
    // 单引号字符串 → 双引号（简单处理，不含转义场景）
    s = s.replaceAllMapped(
      RegExp(r"'([^'\\]*)'"),
      (m) => '"${m[1]}"',
    );
    return s;
  }

  static Future<String> saveBytes(String fileName, List<int> bytes) async {
    final dir = await hipyDir();
    var base = p.basenameWithoutExtension(fileName);
    var target = File(p.join(dir.path, '$base.py'));
    int i = 1;
    while (target.existsSync()) {
      target = File(p.join(dir.path, '${base}_$i.py'));
      i++;
    }
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  static Future<void> delete(String path) async {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }
}