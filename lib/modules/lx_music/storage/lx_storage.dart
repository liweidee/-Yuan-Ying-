import 'package:hive_ce/hive.dart';

import '../../../core/constants/storage_keys.dart';
import '../models/lx_script_model.dart';

/// 洛雪音乐本地存储（Hive）
///
/// 两个 box：
/// - `lx_music`：脚本、激活ID、搜索历史、收藏
/// - `lx_download`：下载队列、已下载列表
class LxStorage {
  LxStorage._();
  static final LxStorage instance = LxStorage._();

  Box? _box;
  Box? _downloadBox;

  Future<Box> get _main async {
    _box ??= await Hive.openBox(LxMusicStorageKeys.box);
    return _box!;
  }

  Future<Box> get _download async {
    _downloadBox ??= await Hive.openBox(LxMusicStorageKeys.downloadBox);
    return _downloadBox!;
  }

  // ==================== 脚本 ====================

  Future<List<LxScript>> loadScripts() async {
    try {
      final box = await _main;
      final raw = box.get(LxMusicStorageKeys.scripts);
      if (raw is! List) return [];
      final list = <LxScript>[];
      for (final item in raw) {
        try {
          if (item is Map) {
            list.add(LxScript.fromJson(Map<String, dynamic>.from(item)));
          }
        } catch (_) {}
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveScripts(List<LxScript> scripts) async {
    final box = await _main;
    await box.put(
      LxMusicStorageKeys.scripts,
      scripts.map((s) => s.toJson()).toList(),
    );
  }

  Future<String?> getActiveScriptId() async {
    final box = await _main;
    final v = box.get(LxMusicStorageKeys.activeScriptId);
    return v?.toString();
  }

  Future<void> setActiveScriptId(String? id) async {
    final box = await _main;
    if (id == null || id.isEmpty) {
      await box.delete(LxMusicStorageKeys.activeScriptId);
    } else {
      await box.put(LxMusicStorageKeys.activeScriptId, id);
    }
  }

  // ==================== 搜索历史 ====================

  Future<List<String>> getSearchHistory() async {
    try {
      final box = await _main;
      final raw = box.get(LxMusicStorageKeys.searchHistory);
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> addSearchHistory(String keyword) async {
    if (keyword.trim().isEmpty) return;
    final history = await getSearchHistory();
    history.remove(keyword);
    history.insert(0, keyword);
    if (history.length > 20) history.removeLast();
    final box = await _main;
    await box.put(LxMusicStorageKeys.searchHistory, history);
  }

  Future<void> clearSearchHistory() async {
    final box = await _main;
    await box.put(LxMusicStorageKeys.searchHistory, <String>[]);
  }

  // ==================== 收藏 ====================

  Future<List<Map<String, dynamic>>> getFavorites() async {
    try {
      final box = await _main;
      final raw = box.get(LxMusicStorageKeys.favorites);
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveFavorites(List<Map<String, dynamic>> favorites) async {
    final box = await _main;
    await box.put(LxMusicStorageKeys.favorites, favorites);
  }

  // ==================== 下载队列 ====================

  Future<List<String>> getDownloadQueue() async {
    try {
      final box = await _download;
      final raw = box.get(LxMusicStorageKeys.downloadQueue);
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDownloadQueue(List<String> jsonList) async {
    final box = await _download;
    await box.put(LxMusicStorageKeys.downloadQueue, jsonList);
    await box.flush();
  }

  Future<List<String>> getDownloadedSongs() async {
    try {
      final box = await _download;
      final raw = box.get(LxMusicStorageKeys.downloadedSongs);
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDownloadedSongs(List<String> jsonList) async {
    final box = await _download;
    await box.put(LxMusicStorageKeys.downloadedSongs, jsonList);
    await box.flush();
  }

  // ==================== 播放历史 ====================
  static const String _historyKey = 'play_history';

  /// 洛雪播放历史（最近 100 条）
  Future<List<Map<String, dynamic>>> getPlayHistory() async {
    try {
      final box = await _main;
      final raw = box.get(_historyKey);
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 写入一条播放历史（同 id 去重，置顶，限 100 条）
  Future<void> addPlayHistory(Map<String, dynamic> item) async {
    try {
      final list = await getPlayHistory();
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) return;
      list.removeWhere((e) => e['id'] == id);
      list.insert(0, item);
      if (list.length > 100) list.removeRange(100, list.length);
      final box = await _main;
      await box.put(_historyKey, list);
    } catch (_) {}
  }

  /// 删除单条
  Future<void> removePlayHistory(String id) async {
    try {
      final list = await getPlayHistory();
      list.removeWhere((e) => e['id'] == id);
      final box = await _main;
      await box.put(_historyKey, list);
    } catch (_) {}
  }

  /// 清空
  Future<void> clearPlayHistory() async {
    final box = await _main;
    await box.put(_historyKey, <Map<String, dynamic>>[]);
  }

  // ==================== 我的歌单 ====================

  static const String _playlistsKey = 'my_playlists';

  /// 歌单列表（每个歌单形如 {id, name, createTime, updateTime, coverUrl, songs: []}）
  Future<List<Map<String, dynamic>>> getPlaylists() async {
    try {
      final box = await _main;
      final raw = box.get(_playlistsKey);
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 保存整个歌单列表
  Future<void> savePlaylists(List<Map<String, dynamic>> playlists) async {
    final box = await _main;
    await box.put(_playlistsKey, playlists);
  }

  /// 新建歌单
  Future<Map<String, dynamic>> createPlaylist(String name) async {
    final id = 'lxpl_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    final playlist = {
      'id': id,
      'name': name,
      'createTime': now,
      'updateTime': now,
      'coverUrl': null,
      'songs': <Map<String, dynamic>>[],
    };
    final list = await getPlaylists();
    list.insert(0, playlist);
    await savePlaylists(list);
    return playlist;
  }

  /// 重命名
  Future<void> renamePlaylist(String id, String newName) async {
    final list = await getPlaylists();
    for (final p in list) {
      if (p['id'] == id) {
        p['name'] = newName;
        p['updateTime'] = DateTime.now().toIso8601String();
        break;
      }
    }
    await savePlaylists(list);
  }

  /// 删除歌单
  Future<void> deletePlaylist(String id) async {
    final list = await getPlaylists();
    list.removeWhere((p) => p['id'] == id);
    await savePlaylists(list);
  }

  /// 添加歌曲到歌单
  Future<void> addSongToPlaylist(
      String playlistId, Map<String, dynamic> song) async {
    final list = await getPlaylists();
    for (final p in list) {
      if (p['id'] == playlistId) {
        final songs = (p['songs'] as List?)?.cast<Map>() ?? [];
        final exists = songs.any((s) => s['id'] == song['id']);
        if (!exists) {
          songs.add(song);
          p['songs'] = songs;
          p['updateTime'] = DateTime.now().toIso8601String();
        }
        break;
      }
    }
    await savePlaylists(list);
  }

  /// 从歌单移除歌曲
  Future<void> removeSongFromPlaylist(
      String playlistId, String songId) async {
    final list = await getPlaylists();
    for (final p in list) {
      if (p['id'] == playlistId) {
        final songs = (p['songs'] as List?)?.cast<Map>() ?? [];
        songs.removeWhere((s) => s['id'] == songId);
        p['songs'] = songs;
        p['updateTime'] = DateTime.now().toIso8601String();
        break;
      }
    }
    await savePlaylists(list);
  }
}