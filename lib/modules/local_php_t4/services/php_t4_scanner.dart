// lib/modules/local_php_t4/services/php_t4_scanner.dart

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/php_t4_source.dart';

/// PHP-T4 本地源目录扫描与上传
abstract final class PhpT4Scanner {
  /// 有效源文件后缀（含前导空格，U+1D48 U+1DBB 是上标字母 ᵈ ᶻ）
  static const String phpt4Suffix = ' ᵈᶻ.php';

  /// 骨架必需文件（相对路径）
  ///
  /// 从 php-t4_tree.txt 提取的最小运行集合：
  ///   - 入口与桥接：index.php / config.php / _bridge.php
  ///   - 配置：config.json
  ///   - 库：lib/spider.php / lib/HtmlParser.php
  ///
  /// 骨架不完整时禁止上传源、禁止启动服务。
  static const List<String> skeletonFiles = <String>[
    'index.php',
    'config.php',
    'config.json',
    '_bridge.php',
    'lib/spider.php',
    'lib/HtmlParser.php',
  ];

  /// 源目录：{ApplicationSupport}/spider/php-t4
  ///
  /// 与 Py 源、通用手动源一致，落在系统私有目录：
  ///   Windows: C:\Users\<user>\AppData\Roaming\<pkg>\spider\php-t4
  ///   Android: /data/data/<pkg>/files/spider/php-t4
  static Future<Directory> dir() async {
    final support = await getApplicationSupportDirectory();
    final d = Directory(p.join(support.path, 'spider', 'php-t4'));
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }

  /// 返回缺失的骨架文件（空列表 = 完整）
  static Future<List<String>> missingSkeletonFiles() async {
    final d = await dir();
    final missing = <String>[];
    for (final rel in skeletonFiles) {
      final f = File(p.join(d.path, rel));
      if (!f.existsSync()) missing.add(rel);
    }
    return missing;
  }

  /// 骨架是否完整
  static Future<bool> hasSkeleton() async {
    return (await missingSkeletonFiles()).isEmpty;
  }

  /// 扫描有效源文件（只返回带 ` ᵈᶻ.php` 后缀的文件）
  static Future<List<PhpT4Source>> scan() async {
    final d = await dir();
    final result = <PhpT4Source>[];
    await for (final e in d.list(followLinks: false)) {
      if (e is! File) continue;
      final baseName = p.basename(e.path);
      if (!baseName.endsWith(phpt4Suffix)) continue;
      try {
        final stat = await e.stat();
        final name = baseName.substring(
          0,
          baseName.length - phpt4Suffix.length,
        );
        result.add(PhpT4Source(
          name: name,
          fileName: baseName,
          path: e.path,
          size: stat.size,
          modified: stat.modified,
        ));
      } catch (_) {}
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// 把上传的原始文件名规范化为带 ` ᵈᶻ.php` 后缀的形式
  ///
  /// 例子：
  ///   abc.php       → abc ᵈᶻ.php
  ///   abc ᵈᶻ.php    → abc ᵈᶻ.php（原样保留）
  ///   abc           → abc ᵈᶻ.php
  static String normalizeFileName(String input) {
    final baseName = p.basename(input);
    if (baseName.endsWith(phpt4Suffix)) return baseName;
    final withoutPhp = baseName.toLowerCase().endsWith('.php')
        ? baseName.substring(0, baseName.length - 4)
        : baseName;
    return '$withoutPhp$phpt4Suffix';
  }

  /// 保存上传文件，返回最终路径
  ///
  /// - 文件名自动规范化为 `{base} ᵈᶻ.php`
  /// - 同名已存在时追加 `_1`、`_2` 避免覆盖
  static Future<String> saveBytes(String inputFileName, List<int> bytes) async {
    final d = await dir();
    final normalized = normalizeFileName(inputFileName);
    var target = File(p.join(d.path, normalized));
    if (target.existsSync()) {
      final withoutSuffix = normalized.substring(
        0,
        normalized.length - phpt4Suffix.length,
      );
      int i = 1;
      while (target.existsSync()) {
        target = File(p.join(d.path, '${withoutSuffix}_$i$phpt4Suffix'));
        i++;
      }
    }
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  /// 删除源文件
  static Future<void> delete(String path) async {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }
}