// lib/services/tmdb_match_cache_service.dart
import 'package:hive_ce/hive.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/models/tmdb_match_record.dart';

/// TMDB 匹配缓存服务
///
/// 存储结构：`{siteKey:::vodId : TmdbMatchRecord.json}`
/// - siteKey 为空时不写入（避免污染）
/// - 超过 [maxEntries] 条时，淘汰最旧的 10%
class TmdbMatchCacheService {
  static const String boxName = StorageKeys.tmdbMatchBox;
  static const int maxEntries = 500;

  late Box _box;

  Future<void> init() async {
    _box = await Hive.openBox(boxName);
  }

  String _buildKey(String siteKey, String vodId) => '$siteKey:::$vodId';

  /// 读取匹配记录，不存在返回 null
  TmdbMatchRecord? get(String siteKey, String vodId) {
    if (siteKey.isEmpty || vodId.isEmpty) return null;
    final raw = _box.get(_buildKey(siteKey, vodId));
    if (raw == null) return null;
    try {
      return TmdbMatchRecord.fromJson(raw as Map);
    } catch (_) {
      return null;
    }
  }

  /// 写入匹配记录
  Future<void> put(String siteKey, String vodId, TmdbMatchRecord record) async {
    if (siteKey.isEmpty || vodId.isEmpty) return;
    await _box.put(_buildKey(siteKey, vodId), record.toJson());
    _maybeEvict();
  }

  /// 删除单条
  Future<void> remove(String siteKey, String vodId) async {
    if (siteKey.isEmpty || vodId.isEmpty) return;
    await _box.delete(_buildKey(siteKey, vodId));
  }

  /// 清空全部
  Future<void> clear() async => _box.clear();

  /// 条目数
  int get count => _box.length;

  /// 导出所有记录（用于缓存管理页展示）
  ///
  /// 返回：`List<({String siteKey, String vodId, TmdbMatchRecord record})>`
  List<TmdbCacheEntry> getAll() {
    final result = <TmdbCacheEntry>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw == null) continue;
      try {
        final parts = key.toString().split(':::');
        if (parts.length != 2) continue;
        result.add(TmdbCacheEntry(
          siteKey: parts[0],
          vodId: parts[1],
          record: TmdbMatchRecord.fromJson(raw as Map),
        ));
      } catch (_) {
        // 忽略损坏的记录
      }
    }
    // 按更新时间倒序
    result.sort((a, b) => b.record.updatedAt.compareTo(a.record.updatedAt));
    return result;
  }

  /// 按站点清理
  Future<void> removeBySiteKey(String siteKey) async {
    final keysToDelete = <dynamic>[];
    for (final key in _box.keys) {
      if (key.toString().startsWith('$siteKey:::')) {
        keysToDelete.add(key);
      }
    }
    if (keysToDelete.isNotEmpty) {
      await _box.deleteAll(keysToDelete);
    }
  }

  /// 淘汰：超过上限时，按 updatedAt 从旧到新删 10%
  void _maybeEvict() {
    if (_box.length <= maxEntries) return;

    final entries = <MapEntry<dynamic, int>>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        final ts = raw['updatedAt'] as int? ?? 0;
        entries.add(MapEntry(key, ts));
      }
    }
    entries.sort((a, b) => a.value.compareTo(b.value));

    final removeCount = (maxEntries * 0.1).ceil();
    final keysToDelete = entries.take(removeCount).map((e) => e.key).toList();
    _box.deleteAll(keysToDelete);
  }
}

/// 缓存条目（用于管理页展示）
class TmdbCacheEntry {
  final String siteKey;
  final String vodId;
  final TmdbMatchRecord record;

  TmdbCacheEntry({
    required this.siteKey,
    required this.vodId,
    required this.record,
  });
}