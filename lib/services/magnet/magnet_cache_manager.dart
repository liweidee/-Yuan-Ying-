import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:yuanying/modules/download/services/cache_service.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/services/magnet/magnet_models.dart';

class MagnetCacheEntry {
  final String infoHash;
  final int fileIndex;
  final String fileName;
  final String? originalMagnet;
  final int totalBytes;
  final int downloadedBytes;
  final bool complete;
  final String? mediaPath;
  final int lastUsedAtMs;

  const MagnetCacheEntry({
    required this.infoHash,
    required this.fileIndex,
    required this.fileName,
    required this.originalMagnet,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.complete,
    required this.mediaPath,
    required this.lastUsedAtMs,
  });

  String get key => '$infoHash/$fileIndex';
  int get sizeOnDisk => complete ? totalBytes : downloadedBytes;

  MagnetCacheEntry copyWith({
    int? totalBytes,
    int? downloadedBytes,
    bool? complete,
    String? mediaPath,
    bool clearMediaPath = false,
    int? lastUsedAtMs,
  }) {
    return MagnetCacheEntry(
      infoHash: infoHash,
      fileIndex: fileIndex,
      fileName: fileName,
      originalMagnet: originalMagnet,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      complete: complete ?? this.complete,
      mediaPath: clearMediaPath ? null : (mediaPath ?? this.mediaPath),
      lastUsedAtMs: lastUsedAtMs ?? this.lastUsedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'infoHash': infoHash,
    'fileIndex': fileIndex,
    'fileName': fileName,
    'originalMagnet': originalMagnet,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'complete': complete,
    'mediaPath': mediaPath,
    'lastUsedAtMs': lastUsedAtMs,
  };

  factory MagnetCacheEntry.fromJson(Map<String, dynamic> json) {
    return MagnetCacheEntry(
      infoHash: json['infoHash']?.toString() ?? '',
      fileIndex: (json['fileIndex'] as num?)?.toInt() ?? 0,
      fileName: json['fileName']?.toString() ?? '',
      originalMagnet: json['originalMagnet']?.toString(),
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      complete: json['complete'] == true,
      mediaPath: json['mediaPath']?.toString(),
      lastUsedAtMs: (json['lastUsedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class MagnetCacheManager {
  MagnetCacheManager._();

  static final MagnetCacheManager instance = MagnetCacheManager._();

  static const _defaultCacheGb = 4;
  final entries = <MagnetCacheEntry>[].obs;

  Future<void>? _initializing;
  Timer? _saveTimer;
  bool _initialized = false;
  Directory? _cacheDirectory;
  final Set<String> _locatingMedia = {};
  final Map<String, int> _lastLocateAttemptMs = {};

  Future<void> init() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      _cacheDirectory = await _resolveCacheDirectory();
      await _loadLedger();
      await _verifyEntries();
    } finally {
      _initialized = true;
      _initializing = null;
    }
  }

  Future<Directory> cacheDirectory() async {
    await init();
    final current = await _resolveCacheDirectory();
    if (_cacheDirectory?.path != current.path) {
      _cacheDirectory = current;
      await _verifyEntries();
    }
    return current;
  }

  int get cacheLimitGb {
    final value = InstallManager.instance
        .findInstalled('magnet')
        ?.extras['magnetCacheGb'];
    if (value is num) return max(1, value.toInt());
    return _defaultCacheGb;
  }

  bool get deleteMediaOnStop {
    final value = InstallManager.instance
        .findInstalled('magnet')
        ?.extras['magnetDeleteOnStop'];
    return value is bool ? value : true;
  }

  int get totalBytes => entries.fold(0, (sum, entry) => sum + entry.sizeOnDisk);

  MagnetCacheEntry? find(String infoHash, int fileIndex) {
    for (final entry in entries) {
      if (entry.infoHash == infoHash && entry.fileIndex == fileIndex) {
        return entry;
      }
    }
    return null;
  }

  void recordPlayback({
    required String infoHash,
    required MagnetFileInfo file,
    required int downloadedBytes,
    required bool complete,
    String? originalMagnet,
  }) {
    final key = '$infoHash/${file.index}';
    final existingIndex = entries.indexWhere((entry) => entry.key == key);
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = existingIndex >= 0 ? entries[existingIndex] : null;
    final entry = MagnetCacheEntry(
      infoHash: infoHash,
      fileIndex: file.index,
      fileName: file.name,
      originalMagnet: originalMagnet ?? existing?.originalMagnet,
      totalBytes: max(file.size, existing?.totalBytes ?? 0),
      downloadedBytes: max(
        downloadedBytes,
        existing?.downloadedBytes ?? 0,
      ).clamp(0, max(1, file.size)),
      complete: complete || (existing?.complete ?? false),
      mediaPath: existing?.mediaPath,
      lastUsedAtMs: now,
    );
    if (existingIndex >= 0) {
      entries[existingIndex] = entry;
    } else {
      entries.add(entry);
    }
    entries.refresh();
    _scheduleSave();

    if (complete && (entry.mediaPath == null || entry.mediaPath!.isEmpty)) {
      final lastAttempt = _lastLocateAttemptMs[entry.key] ?? 0;
      if (now - lastAttempt >= 15000) {
        _lastLocateAttemptMs[entry.key] = now;
        unawaited(_locateCompletedMedia(entry));
      }
    }
  }

  void markStopped({
    required String infoHash,
    required int fileIndex,
    required bool mediaDeleted,
  }) {
    final index = entries.indexWhere(
      (entry) => entry.infoHash == infoHash && entry.fileIndex == fileIndex,
    );
    if (index < 0) return;
    if (mediaDeleted) {
      _lastLocateAttemptMs.remove(entries[index].key);
      entries.removeAt(index);
    } else {
      entries[index] = entries[index].copyWith(
        lastUsedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }
    entries.refresh();
    _scheduleSave();
  }

  Future<void> deleteEntry(MagnetCacheEntry entry) async {
    final root = await cacheDirectory();
    final mediaPath = entry.mediaPath;
    if (mediaPath != null && mediaPath.isNotEmpty) {
      await _deleteManagedFile(root, mediaPath);
    } else {
      final located = await _findMediaFile(
        root,
        name: entry.fileName,
        expectedSize: entry.totalBytes,
      );
      if (located != null) await _deleteManagedFile(root, located);
    }
    entries.removeWhere((item) => item.key == entry.key);
    _lastLocateAttemptMs.remove(entry.key);
    entries.refresh();
    await _saveLedger();
  }

  Future<void> clearAllMedia() async {
    final root = await cacheDirectory();
    for (final entry in entries.toList()) {
      final mediaPath = entry.mediaPath;
      if (mediaPath != null && mediaPath.isNotEmpty) {
        await _deleteManagedFile(root, mediaPath);
      } else {
        final located = await _findMediaFile(
          root,
          name: entry.fileName,
          expectedSize: entry.totalBytes,
        );
        if (located != null) await _deleteManagedFile(root, located);
      }
    }
    entries.clear();
    _lastLocateAttemptMs.clear();
    await _saveLedger();
  }

  Future<void> pruneIfNeeded({String? activeInfoHash}) async {
    final limit = cacheLimitGb * 1024 * 1024 * 1024;
    if (limit <= 0 || totalBytes <= limit) return;
    final candidates =
        entries.where((entry) => entry.infoHash != activeInfoHash).toList()
          ..sort((a, b) => a.lastUsedAtMs.compareTo(b.lastUsedAtMs));
    var usage = totalBytes;
    final target = (limit * 0.9).round();
    for (final entry in candidates) {
      if (usage <= target) break;
      usage -= entry.sizeOnDisk;
      await deleteEntry(entry);
    }
  }

  Future<void> reloadSettings() async {
    if (totalBytes > cacheLimitGb * 1024 * 1024 * 1024) {
      await pruneIfNeeded();
    }
  }

  Future<Directory> _resolveCacheDirectory() async {
    String? downloadRoot;
    if (Get.isRegistered<CacheService>()) {
      try {
        downloadRoot = await Get.find<CacheService>().downloadDirectoryPath();
      } catch (_) {}
    }
    if (downloadRoot == null || downloadRoot.isEmpty) {
      final support = await getApplicationSupportDirectory();
      downloadRoot = p.join(support.path, CacheService.downloadDirName);
    }
    final preferred = Directory(p.join(downloadRoot, 'magnet'));
    try {
      await preferred.create(recursive: true);
      return preferred;
    } catch (_) {
      final support = await getApplicationSupportDirectory();
      final fallback = Directory(
        p.join(support.path, CacheService.downloadDirName, 'magnet'),
      );
      await fallback.create(recursive: true);
      return fallback;
    }
  }

  Future<File> _ledgerFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'magnet-cache-ledger.json'));
  }

  Future<void> _loadLedger() async {
    final file = await _ledgerFile();
    if (!file.existsSync()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['entries'] is! List) return;
      final loaded = <MagnetCacheEntry>[];
      for (final item in raw['entries'] as List) {
        if (item is Map) {
          final entry = MagnetCacheEntry.fromJson(
            item.cast<String, dynamic>(),
          );
          if (entry.infoHash.isNotEmpty && entry.fileName.isNotEmpty) {
            loaded.add(entry);
          }
        }
      }
      entries.assignAll(loaded);
    } catch (_) {
      entries.clear();
    }
  }

  Future<void> _verifyEntries() async {
    final Directory root =
        _cacheDirectory ??
        await getApplicationSupportDirectory().then(
          (support) => Directory(
            p.join(support.path, CacheService.downloadDirName, 'magnet'),
          ),
        );
    var changed = false;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final path = entry.mediaPath;
      if (path == null || path.isEmpty) continue;
      final validPath = p.isWithin(root.path, path) || root.path == path;
      final file = File(path);
      if (!validPath || !file.existsSync()) {
        entries[i] = entry.copyWith(complete: false, clearMediaPath: true);
        changed = true;
      }
    }
    if (changed) {
      entries.refresh();
      await _saveLedger();
    }
  }

  Future<void> _locateCompletedMedia(MagnetCacheEntry entry) async {
    if (!_locatingMedia.add(entry.key)) return;
    try {
      final root = await cacheDirectory();
      final match = await _findMediaFile(
        root,
        name: entry.fileName,
        expectedSize: entry.totalBytes,
      );
      if (match == null) return;
      final index = entries.indexWhere((item) => item.key == entry.key);
      if (index < 0) return;
      entries[index] = entries[index].copyWith(
        mediaPath: match,
        complete: true,
      );
      entries.refresh();
      await _saveLedger();
    } catch (_) {
      return;
    } finally {
      _locatingMedia.remove(entry.key);
    }
  }

  Future<String?> _findMediaFile(
    Directory root, {
    required String name,
    required int expectedSize,
  }) async {
    File? match;
    try {
      await for (final entity in root.list(recursive: true)) {
        if (entity is! File) continue;
        if (p.basename(entity.path).toLowerCase() != name.toLowerCase()) {
          continue;
        }
        if (expectedSize > 0 && await entity.length() < expectedSize) {
          continue;
        }
        if (match == null ||
            entity.lastModifiedSync().isAfter(match.lastModifiedSync())) {
          match = entity;
        }
      }
    } catch (_) {
      return null;
    }
    return match?.path;
  }

  Future<void> _deleteManagedFile(Directory root, String path) async {
    try {
      if (!(p.isWithin(root.path, path) || root.path == path)) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_saveLedger());
    });
  }

  Future<void> _saveLedger() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      final file = await _ledgerFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'entries': entries.map((entry) => entry.toJson()).toList(),
        }),
        flush: true,
      );
    } catch (_) {}
  }
}
