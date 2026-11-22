// lib/modules/download/services/cache_service.dart
import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/modules/download/models/cache_entry.dart';
import 'package:yuanying/modules/download/services/download_manager.dart';
import 'package:yuanying/utils/storage_manager.dart';

class CacheStorageStats {
  final String directory;
  final int usedBytes;
  final int fileCount;

  const CacheStorageStats({
    required this.directory,
    required this.usedBytes,
    required this.fileCount,
  });
}

class CacheService extends GetxService {
  static const String boxName = 'download_entries';
  static const String downloadDirName = 'downloads';
  static const String customDownloadDirName = 'YuanYingDownloads';

  late final Box _box;

  final entries = <CacheEntry>[].obs;
  final currentDownload = Rxn<CacheEntry>();
  final isMigrating = false.obs;

  DownloadManager? _manager;
  bool _migrationInProgress = false;

  @override
  void onInit() {
    super.onInit();
    _box = Hive.box(boxName);
    _loadEntries();
    _autoResumeOnStart();
  }

  // ============================================================
  // 初始化 & 持久化
  // ============================================================
  void _loadEntries() {
    final list = <CacheEntry>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        try {
          final entry = CacheEntry.fromMap(raw);
          // 应用被强杀时状态可能停在 downloading，重置为 paused
          if (entry.status == CacheStatus.downloading) {
            entry.status = CacheStatus.paused;
          }
          list.add(entry);
        } catch (e) {
          debugPrint('CacheEntry parse error: $e');
        }
      }
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    entries.assignAll(list);
  }

  Future<void> _saveEntry(CacheEntry entry) async {
    try {
      await _box.put(entry.id, entry.toMap());
    } catch (e) {
      debugPrint('CacheEntry save error: $e');
    }
  }

  // ============================================================
  // 路径
  // ============================================================
  Future<String> defaultDownloadDirectoryPath() async {
    final supportDir = await getApplicationSupportDirectory();
    return path.join(supportDir.path, downloadDirName);
  }

  /// 用户选择的目录下统一创建 YuanYingDownloads 子目录，避免与其他文件混放。
  static String resolveTargetDirectory(String selectedDirectory) {
    final normalized = path.normalize(selectedDirectory);
    return path.basename(normalized) == customDownloadDirName
        ? normalized
        : path.join(normalized, customDownloadDirName);
  }

  Future<String> downloadDirectoryPath() async {
    final configured = StorageManager.getSetting<String>(
      SettingBoxKey.cacheDownloadPath,
    );
    final rootPath = configured == null || configured.trim().isEmpty
        ? await defaultDownloadDirectoryPath()
        : path.normalize(configured.trim());
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<String> _ensureEntryDir(String id) async {
    final rootPath = await downloadDirectoryPath();
    final dir = Directory(path.join(rootPath, id));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  String _extractExt(String url) {
    try {
      final uri = Uri.parse(url);
      final p = uri.path;
      final lastDot = p.lastIndexOf('.');
      if (lastDot == -1) return '.mp4';
      final ext = p.substring(lastDot);
      if (ext.length > 6 || ext.contains('/') || ext.contains('?')) {
        return '.mp4';
      }
      return ext;
    } catch (_) {
      return '.mp4';
    }
  }

  // ============================================================
  // 添加 & 启动下载
  // ============================================================
  Future<void> addDownload(CacheEntry entry) async {
    if (_migrationInProgress) {
      debugPrint('下载目录迁移中，忽略新增下载');
      return;
    }
    final exist = entries.firstWhereOrNull((e) => e.url == entry.url);
    if (exist != null) return;

    final dir = await _ensureEntryDir(entry.id);

    // M3U8 输出为 .ts，普通直链保留原扩展名
    final isM3u8 =
        entry.isM3u8 || entry.url.toLowerCase().contains('.m3u8');
    final ext = isM3u8 ? '.ts' : _extractExt(entry.url);
    entry.savePath = path.join(dir, 'video$ext');

    // 确保 updatedAt 为当前时间，让新条目在队列中排最前
    entry.updatedAt = DateTime.now().millisecondsSinceEpoch;

    await _saveEntry(entry);
    entries.insert(0, entry);

    if (currentDownload.value == null) {
      _startNext(entry);
    } else {
      entry.status = CacheStatus.waiting;
      await _saveEntry(entry);
      entries.refresh();
    }
  }

  void _startNext(CacheEntry entry) {
    try {
      File(entry.savePath).parent.createSync(recursive: true);
    } catch (error) {
      debugPrint('无法创建下载目录: $error');
      entry.status = CacheStatus.failed;
      entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
      _saveEntry(entry);
      entries.refresh();
      Future.microtask(_autoNext);
      return;
    }
    entry.status = CacheStatus.downloading;
    entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
    currentDownload.value = entry;
    _saveEntry(entry);
    entries.refresh();

    _manager = DownloadManager(
      url: entry.url,
      savePath: entry.savePath,
      headers: entry.headers,
      onProgress: (received, total) {
        // M3U8：received / total 是分片数
        // 直链：received / total 是字节数
        entry.downloadedBytes = received;
        entry.totalBytes = total;
        entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
        entries.refresh();
      },
      onComplete: () async {
        // M3U8 完成后，totalBytes 原来是分片数，需要替换为实际文件大小
        if (entry.isM3u8 || entry.url.toLowerCase().contains('.m3u8')) {
          try {
            final file = File(entry.savePath);
            if (file.existsSync()) {
              final size = await file.length();
              entry.totalBytes = size;
              entry.downloadedBytes = size;
            }
          } catch (e) {
            debugPrint('read final size error: $e');
          }
        } else {
          entry.downloadedBytes = entry.totalBytes;
        }

        entry.status = CacheStatus.completed;
        entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
        await _saveEntry(entry);
        _manager = null;
        currentDownload.value = null;
        entries.refresh();
        _autoNext();
      },
      onError: (e) async {
        debugPrint('Download error: $e');
        entry.status = CacheStatus.failed;
        entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
        await _saveEntry(entry);
        _manager = null;
        currentDownload.value = null;
        entries.refresh();
        _autoNext();
      },
    );
  }

  /// 调度下一个 waiting 条目
  ///
  /// 关键：按 `updatedAt` 倒序找 waiting，让**用户最近操作的条目优先**。
  /// 这样用户点击重试 A 后，A 会排在其他 waiting 条目之前被启动。
  void _autoNext() {
    if (_migrationInProgress) return;
    final candidates = entries
        .where((e) => e.status == CacheStatus.waiting)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (candidates.isNotEmpty) {
      _startNext(candidates.first);
    }
  }

  /// 应用冷启动自动续传
  ///
  /// 只在启动时执行一次，按 `updatedAt` 倒序优先恢复用户最近操作的条目。
  void _autoResumeOnStart() {
    Future.microtask(() {
      final candidates = entries
          .where((e) =>
              e.status == CacheStatus.paused ||
              e.status == CacheStatus.waiting)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (candidates.isNotEmpty) {
        _startNext(candidates.first);
      }
    });
  }

  // ============================================================
  // 暂停 / 继续 / 重试 / 删除
  // ============================================================
  Future<void> pauseDownload(CacheEntry entry) async {
    if (_migrationInProgress) return;
    // 先改状态让 UI 秒响应
    entry.status = CacheStatus.paused;
    entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
    entries.refresh();

    if (currentDownload.value?.id == entry.id) {
      await _manager?.cancel();
      _manager = null;
      currentDownload.value = null;
    }

    await _saveEntry(entry);
    _autoNext();
  }

  Future<void> resumeDownload(CacheEntry entry) async {
    if (_migrationInProgress) return;
    // 用户主动点击 → 刷新 updatedAt，让其在队列中排最前
    entry.updatedAt = DateTime.now().millisecondsSinceEpoch;

    if (currentDownload.value != null) {
      // 已有下载中任务 → 加入 waiting 队列，updatedAt 保证它优先
      entry.status = CacheStatus.waiting;
      await _saveEntry(entry);
      entries.refresh();
      return;
    }

    // 无下载中任务 → 立即启动
    await _saveEntry(entry);
    _startNext(entry);
  }

  /// 重试失败条目
  ///
  /// - 保留 `downloadedBytes`，以便 M3U8 分片级断点续传
  /// - 刷新 `updatedAt`，让它在队列中排最前
  Future<void> retryDownload(CacheEntry entry) async {
    if (_migrationInProgress) return;
    entry.status = CacheStatus.waiting;
    entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _saveEntry(entry);
    entries.refresh();
    await resumeDownload(entry);
  }

  Future<void> deleteEntry(CacheEntry entry, {bool deleteFile = true}) async {
    if (_migrationInProgress) return;
    if (currentDownload.value?.id == entry.id) {
      await _manager?.cancel();
      _manager = null;
      currentDownload.value = null;
    }

    await _box.delete(entry.id);
    entries.removeWhere((e) => e.id == entry.id);

    if (deleteFile) {
      try {
        final file = File(entry.savePath);
        final dir = file.parent;
        if (dir.existsSync() && await _isManagedEntryDirectory(dir)) {
          if (file.existsSync()) await file.delete();
          await dir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('Delete file error: $e');
      }
    }

    entries.refresh();
    _autoNext();
  }

  Future<void> deleteAll() async {
    if (_migrationInProgress) return;
    final entriesSnapshot = entries.toList();
    await _manager?.cancel();
    _manager = null;
    currentDownload.value = null;

    for (final entry in entriesSnapshot) {
      try {
        final file = File(entry.savePath);
        final dir = file.parent;
        if (dir.existsSync() && await _isManagedEntryDirectory(dir)) {
          if (file.existsSync()) await file.delete();
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    }
    try {
      final root = Directory(await downloadDirectoryPath());
      for (final entry in entriesSnapshot) {
        final entryDir = Directory(path.join(root.path, entry.id));
        if (await entryDir.exists()) {
          await entryDir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('清理下载根目录失败: $e');
    }
    await _box.clear();
    entries.clear();
  }

  Future<CacheStorageStats> storageStats() async {
    final rootPath = await downloadDirectoryPath();
    final root = Directory(rootPath);
    var usedBytes = 0;
    var fileCount = 0;
    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          usedBytes += await entity.length();
          fileCount++;
        }
      }
    } catch (e) {
      debugPrint('统计下载空间失败: $e');
    }
    return CacheStorageStats(
      directory: rootPath,
      usedBytes: usedBytes,
      fileCount: fileCount,
    );
  }

  /// 将当前下载目录完整迁移到用户选择的父目录下的 downloads 子目录。
  ///
  /// 只有所有文件复制、Hive 路径更新和目录设置都成功后才算迁移完成。
  Future<void> moveDownloadDirectory(String selectedDirectory) {
    return _moveDownloadDirectoryToRoot(
      resolveTargetDirectory(selectedDirectory),
    );
  }

  Future<void> moveToDefaultDownloadDirectory() async {
    return _moveDownloadDirectoryToRoot(
      await defaultDownloadDirectoryPath(),
    );
  }

  Future<void> _moveDownloadDirectoryToRoot(String requestedTargetRoot) async {
    if (_migrationInProgress) {
      throw StateError('下载目录正在迁移，请稍候');
    }

    final oldRootPath = path.normalize(await downloadDirectoryPath());
    final targetRootPath = path.normalize(requestedTargetRoot);
    if (path.equals(oldRootPath, targetRootPath)) {
      return;
    }
    if (path.isWithin(oldRootPath, targetRootPath) ||
        path.isWithin(targetRootPath, oldRootPath)) {
      throw StateError('新旧下载目录不能互相包含');
    }

    _migrationInProgress = true;
    isMigrating.value = true;
    final oldRoot = Directory(oldRootPath);
    final targetRootDirectory = Directory(targetRootPath);
    final stagingRoot = Directory(
      path.join(
        targetRootPath,
        '.yuanying_migrating_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    final previousSetting = StorageManager.getSetting<String>(
      SettingBoxKey.cacheDownloadPath,
    );
    final entriesSnapshot = entries.toList();
    final previousPaths = <String, String>{
      for (final entry in entriesSnapshot) entry.id: entry.savePath,
    };
    final sourceDirectories = <String, Directory>{};
    final stagedDirectories = <String, Directory>{};
    final promotedDirectories = <Directory>[];
    CacheEntry? activeEntry;
    var recordsCommitted = false;
    var settingCommitted = false;
    var succeeded = false;

    try {
      await targetRootDirectory.create(recursive: true);
      await _cleanupStaleMigrationEntries(targetRootPath);
      final probe = File(
        path.join(targetRootPath, '.yuanying_write_test_$pid'),
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();

      for (final entry in entriesSnapshot) {
        final targetEntryDir = Directory(path.join(targetRootPath, entry.id));
        if (await targetEntryDir.exists()) {
          throw StateError('目标目录已存在同名缓存：${entry.id}');
        }
        final sourceDir = _entryDirectoryFor(entry, oldRootPath);
        if (await sourceDir.exists()) {
          sourceDirectories[entry.id] = sourceDir;
        }
      }

      activeEntry = currentDownload.value;
      if (activeEntry != null) {
        activeEntry.status = CacheStatus.paused;
        activeEntry.updatedAt = DateTime.now().millisecondsSinceEpoch;
        await _manager?.cancel();
        _manager = null;
        currentDownload.value = null;
        await _saveEntry(activeEntry);
        entries.refresh();
      }

      await stagingRoot.create(recursive: true);
      for (final item in sourceDirectories.entries) {
        final staged = Directory(path.join(stagingRoot.path, item.key));
        await _copyDirectory(item.value, staged);
        stagedDirectories[item.key] = staged;
      }

      for (final item in stagedDirectories.entries) {
        final finalized = Directory(path.join(targetRootPath, item.key));
        await item.value.rename(finalized.path);
        promotedDirectories.add(finalized);
      }

      for (final entry in entriesSnapshot) {
        if (entry.savePath.isNotEmpty &&
            path.isWithin(oldRootPath, entry.savePath)) {
          final relative = path.relative(entry.savePath, from: oldRootPath);
          entry.savePath = path.join(targetRootPath, relative);
        }
      }

      await _box.putAll({
        for (final entry in entriesSnapshot) entry.id: entry.toMap(),
      });
      recordsCommitted = true;
      await StorageManager.setSetting(
        SettingBoxKey.cacheDownloadPath,
        targetRootPath,
      );
      settingCommitted = true;
      succeeded = true;

      for (final sourceDir in sourceDirectories.values) {
        try {
          if (await sourceDir.exists()) {
            await sourceDir.delete(recursive: true);
          }
        } catch (e) {
          debugPrint('清理旧下载目录失败: $e');
        }
      }
      try {
        if (await oldRoot.exists() && await oldRoot.list().isEmpty) {
          await oldRoot.delete();
        }
      } catch (_) {}
      entries.refresh();
    } catch (error) {
      if (settingCommitted) {
        try {
          if (previousSetting == null || previousSetting.trim().isEmpty) {
            await StorageManager.deleteSetting(
              SettingBoxKey.cacheDownloadPath,
            );
          } else {
            await StorageManager.setSetting(
              SettingBoxKey.cacheDownloadPath,
              previousSetting,
            );
          }
        } catch (restoreError) {
          debugPrint('恢复下载目录设置失败: $restoreError');
        }
      }

      for (final entry in entriesSnapshot) {
        entry.savePath = previousPaths[entry.id] ?? entry.savePath;
      }
      if (recordsCommitted) {
        try {
          await _box.putAll({
            for (final entry in entriesSnapshot) entry.id: entry.toMap(),
          });
        } catch (restoreError) {
          debugPrint('恢复下载记录路径失败: $restoreError');
        }
      }
      for (final directory in promotedDirectories) {
        try {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        } catch (_) {}
      }
      entries.refresh();
      rethrow;
    } finally {
      try {
        if (await stagingRoot.exists()) {
          await stagingRoot.delete(recursive: true);
        }
      } catch (_) {}
      _migrationInProgress = false;
      isMigrating.value = false;
      if (succeeded && activeEntry != null) {
        activeEntry.status = CacheStatus.waiting;
        activeEntry.updatedAt = DateTime.now().millisecondsSinceEpoch;
        await _saveEntry(activeEntry);
        _startNext(activeEntry);
      }
    }
  }

  Directory _entryDirectoryFor(CacheEntry entry, String rootPath) {
    if (entry.savePath.isNotEmpty) {
      final parent = Directory(path.dirname(entry.savePath));
      if (path.isWithin(rootPath, parent.path)) {
        return parent;
      }
    }
    return Directory(path.join(rootPath, entry.id));
  }

  Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(
      recursive: false,
      followLinks: false,
    )) {
      final targetPath = path.join(destination.path, path.basename(entity.path));
      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      }
    }
  }

  Future<void> _cleanupStaleMigrationEntries(String targetRootPath) async {
    final root = Directory(targetRootPath);
    await for (final entity in root.list(
      recursive: false,
      followLinks: false,
    )) {
      final name = path.basename(entity.path);
      if (entity is Directory && name.startsWith('.yuanying_migrating_')) {
        await entity.delete(recursive: true);
      } else if (entity is File && name.startsWith('.yuanying_write_test_')) {
        await entity.delete();
      }
    }
  }

  Future<bool> _isManagedEntryDirectory(Directory directory) async {
    final rootPath = path.normalize(await downloadDirectoryPath());
    final directoryPath = path.normalize(directory.path);
    return !path.equals(rootPath, directoryPath) &&
        path.equals(path.dirname(directoryPath), rootPath);
  }
}
