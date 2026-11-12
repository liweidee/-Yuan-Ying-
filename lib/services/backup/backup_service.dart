import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:yuanying/build_config.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/utils/device_utils.dart';

import 'backup_category.dart';
import 'backup_manifest.dart';
import 'backup_registry.dart';

/// 导出结果
class ExportResult {
  final bool success;
  final String? error;
  final List<String> warnings;
  final Uint8List? zipBytes;
  final BackupManifest? manifest;

  const ExportResult({
    required this.success,
    this.error,
    this.warnings = const [],
    this.zipBytes,
    this.manifest,
  });
}

/// 预览结果（读取 zip 但不写入）
class PreviewResult {
  final bool success;
  final String? error;
  final BackupManifest? manifest;

  const PreviewResult({required this.success, this.error, this.manifest});
}

/// 导入结果
class ImportResult {
  final bool success;
  final String? error;
  final List<String> warnings;

  const ImportResult({
    required this.success,
    this.error,
    this.warnings = const [],
  });
}

/// 备份服务（门面）
abstract final class BackupService {
  static const String _manifestEntry = 'manifest.json';
  static const String _boxesDir = 'boxes';
  static const String _filesDir = 'files';

  // 文件系统条目 id（与 manifest.files[].id 一致）
  static const String _fileIdSpider = 'spider';
  static const String _fileIdWallpaper = 'wallpaper';

  // 路径片段（与各模块实现保持一致）
  // - spider：ManualSourceScanner.spiderRoot() / PhpT4Scanner.dir()
  // - wallpaper：BgConfigController.uploadCustom()
  static const String _spiderDirName = 'spider';
  static const String _wallpaperDirName = 'yuanying_bg';
  static const String _wallpaperFilePrefix = 'wallpaper';

  // ============================================================
  // 导出
  // ============================================================
  static Future<ExportResult> export({
    required Set<BackupCategory> categories,
  }) async {
    final warnings = <String>[];
    final archive = Archive();
    final boxInfos = <BackupBoxInfo>[];
    final fileInfos = <BackupFileInfo>[];

    final targets = BackupRegistry.entries
        .where((e) => categories.contains(e.category))
        .toList();

    if (targets.isEmpty) {
      return const ExportResult(success: false, error: '未选择任何分类');
    }

    // -------- 1. Hive Boxes --------
    for (final entry in targets) {
      Box<dynamic>? box;
      try {
        box = Hive.box(entry.boxName);
      } catch (_) {
        warnings.add('「${entry.displayName}」未打开，已跳过');
        continue;
      }

      final raw = box.toMap();
      final filtered = <String, dynamic>{};
      for (final e in raw.entries) {
        final key = e.key?.toString() ?? '';
        if (entry.excludedKeys.contains(key)) continue;
        filtered[key] = e.value;
      }

      if (filtered.isEmpty) {
        warnings.add('「${entry.displayName}」为空，已跳过');
        continue;
      }

      final jsonBytes = utf8.encode(jsonEncode(filtered)) as List<int>;
      archive.addFile(ArchiveFile(
        '$_boxesDir/${entry.boxName}.json',
        jsonBytes.length,
        jsonBytes,
      ));

      boxInfos.add(BackupBoxInfo(
        name: entry.boxName,
        category: entry.category,
        count: filtered.length,
        bytes: jsonBytes.length,
      ));
    }

    // -------- 2. spider 目录 --------
    if (!kIsWeb && categories.contains(BackupCategory.sources)) {
      try {
        final spiderDir = await _spiderDir();
        if (spiderDir.existsSync()) {
          final packed = await _packDirectory(
            archive,
            spiderDir,
            '$_filesDir/$_spiderDirName/',
          );
          if (packed.count > 0) {
            fileInfos.add(BackupFileInfo(
              id: _fileIdSpider,
              category: BackupCategory.sources,
              count: packed.count,
              bytes: packed.bytes,
            ));
          }
        }
      } catch (e) {
        warnings.add('spider 目录打包失败：$e');
      }
    }

    // -------- 3. 壁纸 --------
    if (!kIsWeb && categories.contains(BackupCategory.settings)) {
      try {
        final packed = await _packWallpaper(archive);
        if (packed != null && packed.count > 0) {
          fileInfos.add(BackupFileInfo(
            id: _fileIdWallpaper,
            category: BackupCategory.settings,
            count: packed.count,
            bytes: packed.bytes,
          ));
        }
      } catch (e) {
        warnings.add('壁纸打包失败：$e');
      }
    }

    if (boxInfos.isEmpty && fileInfos.isEmpty) {
      return ExportResult(
        success: false,
        error: '无可导出的数据',
        warnings: warnings,
      );
    }

    // -------- 4. manifest --------
    final manifest = BackupManifest(
      formatName: BackupManifest.format,
      formatVersion: BackupManifest.currentFormatVersion,
      appVersion: BuildConfig.versionName,
      appVersionCode: BuildConfig.versionCode,
      platform: DeviceUtils.platformName,
      exportedAt: DateTime.now(),
      boxes: boxInfos,
      files: fileInfos,
    );
    final manifestBytes =
        utf8.encode(jsonEncode(manifest.toJson())) as List<int>;
    archive.addFile(ArchiveFile(
      _manifestEntry,
      manifestBytes.length,
      manifestBytes,
    ));

    try {
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) {
        return ExportResult(
          success: false,
          error: '打包失败：编码返回空',
          warnings: warnings,
        );
      }
      return ExportResult(
        success: true,
        zipBytes: Uint8List.fromList(encoded),
        manifest: manifest,
        warnings: warnings,
      );
    } catch (e) {
      return ExportResult(
        success: false,
        error: '打包失败：$e',
        warnings: warnings,
      );
    }
  }

  // ============================================================
  // 预览导入文件（只读）
  // ============================================================
  static PreviewResult preview(Uint8List zipBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);

      final manifestFile = _findFile(archive, _manifestEntry);
      if (manifestFile == null) {
        return const PreviewResult(success: false, error: '缺少 manifest.json');
      }

      final manifestJson = jsonDecode(
        utf8.decode(_readContent(manifestFile)),
      );
      if (manifestJson is! Map) {
        return const PreviewResult(success: false, error: 'manifest.json 格式错误');
      }
      final manifest =
          BackupManifest.fromJson(Map<String, dynamic>.from(manifestJson));

      if (manifest.formatName != BackupManifest.format) {
        return PreviewResult(
          success: false,
          error: '文件格式不匹配：${manifest.formatName}',
        );
      }
      if (manifest.formatVersion > BackupManifest.currentFormatVersion) {
        return PreviewResult(
          success: false,
          error: '文件版本过高（${manifest.formatVersion}）',
        );
      }
      if (manifest.boxes.isEmpty && manifest.files.isEmpty) {
        return const PreviewResult(success: false, error: '备份文件为空');
      }

      return PreviewResult(success: true, manifest: manifest);
    } catch (e) {
      return PreviewResult(success: false, error: '解析失败：$e');
    }
  }

  // ============================================================
  // 导入（原子化 + 失败回滚）
  // ============================================================
  static Future<ImportResult> import(
    Uint8List zipBytes, {
    required Set<BackupCategory> categories,
  }) async {
    final warnings = <String>[];

    // -------- 1. 解析 zip & manifest --------
    final Archive archive;
    final BackupManifest manifest;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile = _findFile(archive, _manifestEntry);
      if (manifestFile == null) {
        return const ImportResult(success: false, error: '缺少 manifest.json');
      }
      final manifestJson =
          jsonDecode(utf8.decode(_readContent(manifestFile)));
      if (manifestJson is! Map) {
        return const ImportResult(success: false, error: 'manifest.json 格式错误');
      }
      manifest =
          BackupManifest.fromJson(Map<String, dynamic>.from(manifestJson));
    } catch (e) {
      return ImportResult(success: false, error: '解析失败：$e');
    }

    if (manifest.formatName != BackupManifest.format) {
      return const ImportResult(success: false, error: '文件格式不匹配');
    }
    if (manifest.formatVersion > BackupManifest.currentFormatVersion) {
      return ImportResult(
        success: false,
        error: '文件版本过高（${manifest.formatVersion}）',
      );
    }

    // -------- 2. 过滤要导入的 Box --------
    final pending = <String, Map<String, dynamic>>{};
    for (final boxInfo in manifest.boxes) {
      if (!categories.contains(boxInfo.category)) continue;
      final entry = BackupRegistry.byName(boxInfo.name);
      if (entry == null) {
        warnings.add('未知 Box「${boxInfo.name}」已忽略');
        continue;
      }
      final archiveFile = _findFile(archive, '$_boxesDir/${boxInfo.name}.json');
      if (archiveFile == null) {
        warnings.add('「${entry.displayName}」数据缺失，已跳过');
        continue;
      }
      try {
        final raw = jsonDecode(utf8.decode(_readContent(archiveFile)));
        if (raw is! Map) throw Exception('内容不是 Map');
        pending[boxInfo.name] = Map<String, dynamic>.from(raw);
      } catch (e) {
        warnings.add('「${entry.displayName}」解析失败：$e');
      }
    }

    // -------- 3. 打开 Box + 拍快照 --------
    final opened = <String, Box<dynamic>>{};
    final snapshots = <String, Map<dynamic, dynamic>>{};
    for (final name in pending.keys) {
      try {
        final box = Hive.box(name);
        opened[name] = box;
        snapshots[name] = Map<dynamic, dynamic>.from(box.toMap());
      } catch (e) {
        return ImportResult(
          success: false,
          error: 'Box「$name」不可用：$e',
          warnings: warnings,
        );
      }
    }

    // -------- 4. 覆盖写入（任一失败全量回滚） --------
    try {
      for (final e in pending.entries) {
        final box = opened[e.key]!;
        await box.clear();
        await box.putAll(e.value);
      }
    } catch (e) {
      // 回滚
      for (final name in opened.keys) {
        try {
          await opened[name]!.clear();
          await opened[name]!.putAll(snapshots[name]!);
        } catch (_) {
          // 回滚也失败时忽略
        }
      }
      return ImportResult(
        success: false,
        error: '导入失败已尝试回滚：$e',
        warnings: warnings,
      );
    }

    // -------- 5. 文件系统恢复 --------
    // 注：box 已成功写入，文件系统失败只记 warning，不回滚
    if (!kIsWeb && categories.contains(BackupCategory.sources)) {
      try {
        await _unpackSpider(archive);
      } catch (e) {
        warnings.add('spider 目录恢复失败：$e');
      }
    }

    if (!kIsWeb && categories.contains(BackupCategory.settings)) {
      try {
        await _restoreWallpaper(archive);
      } catch (e) {
        warnings.add('壁纸恢复失败：$e');
      }
    }

    return ImportResult(success: true, warnings: warnings);
  }

  // ============================================================
  // 文件系统辅助
  // ============================================================

  /// spider 目录：{support}/spider/
  /// 与 ManualSourceScanner.spiderRoot() / PhpT4Scanner.dir() 一致
  static Future<Directory> _spiderDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, _spiderDirName));
  }

  /// 壁纸目录：{documents}/yuanying_bg/
  /// 与 BgConfigController.uploadCustom() 一致
  static Future<Directory> _wallpaperDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, _wallpaperDirName));
  }

  /// 递归打包目录到 zip（保留相对结构）
  static Future<_PackResult> _packDirectory(
    Archive archive,
    Directory srcDir,
    String zipPrefix,
  ) async {
    if (!srcDir.existsSync()) {
      return const _PackResult(count: 0, bytes: 0);
    }
    var count = 0;
    var bytes = 0;
    await for (final entity
        in srcDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final rel = p.relative(entity.path, from: srcDir.path);
        // zip 内统一用 '/'，避免 Windows 反斜杠
        final zipName = '$zipPrefix${rel.replaceAll('\\', '/')}';
        final content = await entity.readAsBytes();
        archive.addFile(ArchiveFile(zipName, content.length, content));
        count++;
        bytes += content.length;
      } catch (_) {
        // 单文件失败不影响整体
      }
    }
    return _PackResult(count: count, bytes: bytes);
  }

  /// 打包当前自定义壁纸（若不存在返回 null）
  static Future<_PackResult?> _packWallpaper(Archive archive) async {
    final path = SettingPref.bgCustomPath;
    if (path.isEmpty) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    final ext = p.extension(path).toLowerCase();
    final content = await f.readAsBytes();
    final zipName =
        '$_filesDir/$_wallpaperDirName/$_wallpaperFilePrefix$ext';
    archive.addFile(ArchiveFile(zipName, content.length, content));
    return _PackResult(count: 1, bytes: content.length);
  }

  /// 解压 spider 目录（覆盖同名文件，保留目标设备独有文件）
  static Future<void> _unpackSpider(Archive archive) async {
    final prefix = '$_filesDir/$_spiderDirName/';
    final hasSpider = archive.files.any(
      (f) => f.name.startsWith(prefix) && !f.name.endsWith('/'),
    );
    if (!hasSpider) return;

    final targetDir = await _spiderDir();
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }

    for (final f in archive.files) {
      if (!f.name.startsWith(prefix)) continue;
      if (f.name.endsWith('/')) continue;
      final rel = f.name.substring(prefix.length);
      if (rel.isEmpty) continue;

      final target = File(
        p.join(targetDir.path, rel.replaceAll('/', p.separator)),
      );
      final parent = target.parent;
      if (!parent.existsSync()) {
        await parent.create(recursive: true);
      }
      await target.writeAsBytes(_readContent(f));
    }
  }

  /// 恢复壁纸（若备份中无壁纸则跳过，不降级）
  static Future<void> _restoreWallpaper(Archive archive) async {
    final prefix = '$_filesDir/$_wallpaperDirName/';
    ArchiveFile? wp;
    for (final f in archive.files) {
      if (f.name.startsWith(prefix) && !f.name.endsWith('/')) {
        wp = f;
        break;
      }
    }
    if (wp == null) return;

    final targetDir = await _wallpaperDir();
    if (targetDir.existsSync()) {
      // 清空旧壁纸（避免多文件残留）
      for (final entity in targetDir.listSync()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } else {
      await targetDir.create(recursive: true);
    }

    final ext = p.extension(wp.name).toLowerCase();
    final fileName =
        'custom_${DateTime.now().millisecondsSinceEpoch}$ext';
    final target = File(p.join(targetDir.path, fileName));
    await target.writeAsBytes(_readContent(wp));

    // 重写 bgCustomPath 指向新路径
    SettingPref.bgCustomPath = target.path;
  }

  // ============================================================
  // 内部工具
  // ============================================================
  static ArchiveFile? _findFile(Archive archive, String name) {
    for (final f in archive.files) {
      if (f.name == name) return f;
    }
    return null;
  }

  static List<int> _readContent(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) return content;
    if (content is List<int>) return content;
    throw Exception('未知内容类型：${content.runtimeType}');
  }
}

/// 打包结果
class _PackResult {
  final int count;
  final int bytes;
  const _PackResult({required this.count, required this.bytes});
}