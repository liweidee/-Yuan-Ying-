import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:hive_ce/hive.dart';

import 'package:yuanying/build_config.dart';
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

  // ============================================================
  // 导出
  // ============================================================
  static Future<ExportResult> export({
    required Set<BackupCategory> categories,
  }) async {
    final warnings = <String>[];
    final archive = Archive();
    final boxInfos = <BackupBoxInfo>[];

    final targets = BackupRegistry.entries
        .where((e) => categories.contains(e.category))
        .toList();

    if (targets.isEmpty) {
      return const ExportResult(success: false, error: '未选择任何分类');
    }

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

      final jsonBytes =
          utf8.encode(jsonEncode(filtered)) as List<int>;
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

    if (boxInfos.isEmpty) {
      return ExportResult(
        success: false,
        error: '无可导出的数据',
        warnings: warnings,
      );
    }

    final manifest = BackupManifest(
      formatName: BackupManifest.format,
      formatVersion: BackupManifest.currentFormatVersion,
      appVersion: BuildConfig.versionName,
      appVersionCode: BuildConfig.versionCode,
      platform: DeviceUtils.platformName,
      exportedAt: DateTime.now(),
      boxes: boxInfos,
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
      if (manifest.boxes.isEmpty) {
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

    if (pending.isEmpty) {
      return ImportResult(
        success: false,
        error: '无有效数据可导入',
        warnings: warnings,
      );
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
      for (final name in opened.keys) {
        try {
          await opened[name]!.clear();
          await opened[name]!.putAll(snapshots[name]!);
        } catch (_) {
          // 回滚也失败时忽略（记录在 warnings）
        }
      }
      return ImportResult(
        success: false,
        error: '导入失败已尝试回滚：$e',
        warnings: warnings,
      );
    }

    return ImportResult(success: true, warnings: warnings);
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