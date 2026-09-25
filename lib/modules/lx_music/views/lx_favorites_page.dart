import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../models/lx_music_model.dart';
import '../storage/lx_storage.dart';
import '../utils/lx_player_helper.dart';

/// 我喜欢（洛雪收藏）
class LxFavoritesPage extends StatefulWidget {
  const LxFavoritesPage({super.key});

  @override
  State<LxFavoritesPage> createState() => _LxFavoritesPageState();
}

class _LxFavoritesPageState extends State<LxFavoritesPage> {
  List<LxMusic> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await LxStorage.instance.getFavorites();
      _favorites = list.map((e) => LxMusic.fromJson(e)).toList();
    } catch (_) {
      _favorites = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(LxMusic music) async {
    try {
      final list = await LxStorage.instance.getFavorites();
      list.removeWhere((e) => e['id'] == music.id);
      await LxStorage.instance.saveFavorites(list);
      await _load();
      SmartDialog.showToast('已移除「${music.name}」');
    } catch (e) {
      SmartDialog.showToast('操作失败: $e');
    }
  }

  void _playAll() {
    if (_favorites.isEmpty) return;
    LxPlayerHelper.playList(_favorites, 0);
  }

  void _playOne(int index) {
    if (_favorites.isEmpty) return;
    LxPlayerHelper.playList(_favorites, index);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text('我喜欢 (${_favorites.length})',
            style: const TextStyle(fontSize: 18)),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          if (_favorites.isNotEmpty) ...[
            IconButton(
              tooltip: '随机播放',
              icon: const Icon(Icons.shuffle_rounded, size: 20),
              onPressed: () {
                final shuffled = List<LxMusic>.from(_favorites)..shuffle();
                LxPlayerHelper.playList(shuffled, 0);
              },
            ),
            IconButton(
              tooltip: '播放全部',
              icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
              onPressed: _playAll,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? _buildEmpty(colorScheme)
              : _buildList(colorScheme),
    );
  }

  Widget _buildEmpty(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.favorite_rounded,
                size: 40, color: colorScheme.primary),
          ),
          const SizedBox(height: 20),
          Text('暂无收藏',
              style: TextStyle(
                  color: colorScheme.onSurfaceVariant, fontSize: 15)),
          const SizedBox(height: 8),
          Text('在歌曲菜单中点击"我喜欢"收藏',
              style: TextStyle(color: colorScheme.outline, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _favorites.length,
      itemBuilder: (context, index) {
        final song = _favorites[index];
        return Dismissible(
          key: Key('fav_${song.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: colorScheme.error.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline_rounded,
                    color: Colors.white, size: 22),
                SizedBox(height: 2),
                Text('移除',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
          onDismissed: (_) => _remove(song),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: song.imgUrl != null && song.imgUrl!.isNotEmpty
                      ? Image.network(song.imgUrl!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _thumb(colorScheme))
                      : _thumb(colorScheme),
                ),
                title: Text(song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colorScheme.onSurface, fontSize: 14)),
                subtitle: Text(song.singer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 12)),
                trailing: IconButton(
                  icon: Icon(Icons.more_vert_rounded,
                      color: colorScheme.outline, size: 20),
                  onPressed: () => _showActions(song, index, colorScheme),
                ),
                onTap: () => _playOne(index),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _thumb(ColorScheme colorScheme) {
    return Container(
      width: 44,
      height: 44,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Icon(Icons.music_note_rounded,
          color: colorScheme.primary, size: 20),
    );
  }

  void _showActions(LxMusic song, int index, ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(song.name,
                  style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: Icon(Icons.play_arrow_rounded,
                  color: colorScheme.primary, size: 20),
              title: const Text('从这首播放'),
              onTap: () {
                Navigator.pop(ctx);
                _playOne(index);
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_add_rounded,
                  color: colorScheme.primary, size: 20),
              title: const Text('添加到歌单'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylist(song, colorScheme);
              },
            ),
            ListTile(
              leading: Icon(Icons.favorite_rounded,
                  color: colorScheme.error, size: 20),
              title: const Text('取消喜欢'),
              onTap: () {
                Navigator.pop(ctx);
                _remove(song);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAddToPlaylist(LxMusic song, ColorScheme colorScheme) async {
    final playlists = await LxStorage.instance.getPlaylists();
    if (playlists.isEmpty) {
      SmartDialog.showToast('还没有歌单，先去创建吧');
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择歌单',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            ...playlists.map((p) => ListTile(
                  leading: Icon(Icons.queue_music_rounded,
                      color: colorScheme.primary, size: 20),
                  title: Text(p['name']?.toString() ?? '未命名'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await LxStorage.instance.addSongToPlaylist(
                        p['id'].toString(), song.toJson());
                    SmartDialog.showToast('已添加到「${p['name']}」');
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}