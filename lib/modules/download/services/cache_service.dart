// lib/modules/download/services/cache_service.dart
import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:yuanying/modules/download/models/cache_entry.dart';
import 'package:yuanying/modules/download/services/download_manager.dart';

class CacheService extends GetxService {
  static const String boxName = 'download_entries';
  static const String downloadDirName = 'downloads';

  late final Box _box;

  final entries = <CacheEntry>[].obs;
  final currentDownload = Rxn<CacheEntry>();

  DownloadManager? _manager;

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
  Future<String> _ensureEntryDir(String id) async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(path.join(supportDir.path, downloadDirName, id));
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
    entry.status = CacheStatus.waiting;
    entry.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _saveEntry(entry);
    entries.refresh();
    await resumeDownload(entry);
  }

  Future<void> deleteEntry(CacheEntry entry, {bool deleteFile = true}) async {
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
        if (file.existsSync()) await file.delete();
        final dir = file.parent;
        if (dir.existsSync() && dir.path.contains(downloadDirName)) {
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
    await _manager?.cancel();
    _manager = null;
    currentDownload.value = null;

    for (final entry in entries.toList()) {
      try {
        final file = File(entry.savePath);
        if (file.existsSync()) await file.delete();
        final dir = file.parent;
        if (dir.existsSync() && dir.path.contains(downloadDirName)) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    }
    await _box.clear();
    entries.clear();
  }
}