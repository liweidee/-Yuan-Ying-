import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/lx_music/models/lx_music_model.dart';
import 'package:yuanying/modules/lx_music/models/lx_songlist_model.dart';
import 'package:yuanying/modules/lx_music/services/lx_songlist_service.dart';
import 'package:yuanying/modules/lx_music/storage/lx_storage.dart';
import 'package:yuanying/modules/lx_music/utils/lx_player_helper.dart';
import 'package:yuanying/modules/lx_music/utils/lx_playlist_helper.dart';

/// 我的歌单页
///
/// 每项独立卡片，与设置页风格一致
class LxPlaylistPage extends StatefulWidget {
  const LxPlaylistPage({super.key});

  @override
  State<LxPlaylistPage> createState() => _LxPlaylistPageState();
}

class _LxPlaylistPageState extends State<LxPlaylistPage> {
  List<Map<String, dynamic>> _allPlaylists = [];
  List<LxSonglistInfo> _qqRecommendations = [];
  bool _loading = true;
  bool _loadingRecommend = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadQQRecommendations();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _allPlaylists = await LxStorage.instance.getPlaylists();
    } catch (_) {
      _allPlaylists = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadQQRecommendations() async {
    if (_loadingRecommend) return;
    setState(() => _loadingRecommend = true);
    try {
      final page = DateTime.now().millisecondsSinceEpoch % 6;
      final lists = await LxSonglistService.instance
          .getQQRecommendSonglists(page: page, pageSize: 20);
      if (mounted && lists.isNotEmpty) {
        setState(() => _qqRecommendations = lists);
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingRecommend = false);
    }
  }

  // ==================== 分组 ====================

  List<Map<String, dynamic>> get _importedPlaylists => _allPlaylists
      .where((p) => (p['id']?.toString() ?? '').startsWith('import_'))
      .toList();

  List<Map<String, dynamic>> get _customPlaylists => _allPlaylists
      .where((p) {
        final id = p['id']?.toString() ?? '';
        return id.startsWith('userlist_') ||
            (!id.startsWith('import_') && !id.startsWith('fav_'));
      })
      .toList();

  // ==================== 操作 ====================

  Future<void> _createPlaylist() async {
    final name = await LxPlaylistHelper.showCreateDialog(context);
    if (name == null || name.isEmpty) return;
    try {
      await LxStorage.instance.createPlaylist(name);
      await _load();
      SmartDialog.showToast('已创建「$name」');
    } catch (e) {
      SmartDialog.showToast('创建失败: $e');
    }
  }

  Future<void> _importPlaylist() async {
    final result = await LxPlaylistHelper.showImportDialog(context);
    if (result != null) {
      await _load();
    }
  }

  Future<void> _deletePlaylist(Map<String, dynamic> playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerLow,
          title: const Text('删除歌单'),
          content: Text('确定要删除「${playlist['name']}」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text('删除', style: TextStyle(color: colorScheme.error)),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    try {
      await LxStorage.instance.deletePlaylist(playlist['id'].toString());
      await _load();
      SmartDialog.showToast('已删除');
    } catch (e) {
      SmartDialog.showToast('删除失败: $e');
    }
  }

  Future<void> _renamePlaylist(Map<String, dynamic> playlist) async {
    final name = await _showRenameDialog(playlist['name']?.toString() ?? '');
    if (name == null || name.isEmpty) return;
    try {
      await LxStorage.instance
          .renamePlaylist(playlist['id'].toString(), name);
      await _load();
      SmartDialog.showToast('已重命名');
    } catch (e) {
      SmartDialog.showToast('重命名失败: $e');
    }
  }

  Future<String?> _showRenameDialog(String initial) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerLow,
          title: const Text('重命名'),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: colorScheme.onSurface),
            decoration: const InputDecoration(
              hintText: '输入新名称',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text('保存',
                  style: TextStyle(color: colorScheme.primary)),
            ),
          ],
        );
      },
    ).then((v) {
      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          controller.dispose();
        } catch (_) {}
      });
      return v;
    });
  }

  void _openPlaylistDetail(Map<String, dynamic> playlist) {
    Get.to(() => _LxPlaylistDetailPage(
          playlistId: playlist['id'].toString(),
          playlistName: playlist['name']?.toString() ?? '歌单',
        ))?.then((_) => _load());
  }

  void _openFavorites() {
    Get.toNamed('/lx_favorites')?.then((_) => _load());
  }

  void _openRecent() {
    Get.toNamed('/lx_recent')?.then((_) => _load());
  }

  void _openSonglistDetail(LxSonglistInfo info) {
    Get.toNamed('/lx_songlist_detail', arguments: {
      'songlistId': info.id,
      'songlistName': info.name,
      'source': info.source,
    });
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('我的歌单', style: TextStyle(fontSize: 18)),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '导入歌单',
            icon: const Icon(Icons.download_rounded, size: 22),
            onPressed: _importPlaylist,
          ),
          IconButton(
            tooltip: '新建歌单',
            icon: const Icon(Icons.add_rounded, size: 26),
            onPressed: _createPlaylist,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _load();
                await _loadQQRecommendations();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ===== 默认列表 =====
                  _sectionTitle('默认列表', colorScheme),

                  _tile(
                    colorScheme,
                    icon: Icons.favorite_rounded,
                    title: '我喜欢',
                    subtitle: '收藏的歌曲',
                    onTap: _openFavorites,
                  ),
                  const SizedBox(height: 8),

                  _tile(
                    colorScheme,
                    icon: Icons.history_rounded,
                    title: '最近播放',
                    subtitle: '播放历史',
                    onTap: _openRecent,
                  ),

                  // ===== 收藏歌单 =====
                  if (_importedPlaylists.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionTitle('收藏歌单', colorScheme),
                    ..._importedPlaylists.map((p) {
                      final tile = _playlistTile(p, colorScheme);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: tile,
                      );
                    }),
                  ],

                  // ===== 自定义列表 =====
                  if (_customPlaylists.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionTitle('自定义列表', colorScheme),
                    ..._customPlaylists.map((p) {
                      final tile = _playlistTile(p, colorScheme);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: tile,
                      );
                    }),
                  ],

                  // 空态
                  if (_importedPlaylists.isEmpty &&
                      _customPlaylists.isEmpty) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(Icons.queue_music_rounded,
                                size: 32, color: colorScheme.primary),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '点击右上角 + 新建，或从下方推荐导入',
                            style: TextStyle(
                                color: colorScheme.outline, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ===== 在线推荐 =====
                  const SizedBox(height: 24),
                  _buildQQRecommendSection(colorScheme),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ==================== 通用小组件 ====================

  Widget _sectionTitle(String text, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: colorScheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 默认项（我喜欢 / 最近播放）—— 独立卡片
  Widget _tile(
    ColorScheme colorScheme, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: colorScheme.onSurfaceVariant, size: 20),
        ),
        title: Text(title,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 12))
            : null,
        trailing: onTap != null
            ? Icon(Icons.chevron_right_rounded,
                color: colorScheme.outline, size: 20)
            : null,
      ),
    );
  }

  /// 用户歌单项 —— 独立卡片
  Widget _playlistTile(Map<String, dynamic> p, ColorScheme colorScheme) {
    final songs = (p['songs'] as List?)?.length ?? 0;
    final cover = p['coverUrl']?.toString();

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: cover != null && cover.isNotEmpty
              ? Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                      Icons.queue_music_rounded,
                      color: colorScheme.primary,
                      size: 22),
                )
              : Icon(Icons.queue_music_rounded,
                  color: colorScheme.primary, size: 22),
        ),
        title: Text(
          p['name']?.toString() ?? '未命名',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
        ),
        subtitle: Text(
          '$songs 首',
          style: TextStyle(
              color: colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded,
              color: colorScheme.outline, size: 20),
          tooltip: '',
          onSelected: (v) {
            if (v == 'rename') _renamePlaylist(p);
            if (v == 'delete') _deletePlaylist(p);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'rename', child: Text('重命名')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: () => _openPlaylistDetail(p),
      ),
    );
  }

  // ==================== 在线推荐 ====================

  Widget _buildQQRecommendSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.explore_rounded,
                color: colorScheme.primary, size: 18),
            const SizedBox(width: 6),
            Text(
              '在线歌单推荐',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _loadQQRecommendations,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        color: colorScheme.primary, size: 14),
                    const SizedBox(width: 4),
                    Text('换一批',
                        style: TextStyle(
                            color: colorScheme.primary, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingRecommend)
          SizedBox(
            height: 160,
            child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: colorScheme.primary)),
          )
        else if (_qqRecommendations.isEmpty)
          Container(
            height: 120,
            alignment: Alignment.center,
            child: Text('推荐加载失败，点击"换一批"重试',
                style:
                    TextStyle(color: colorScheme.outline, fontSize: 12)),
          )
        else
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _qqRecommendations.length,
              itemBuilder: (context, index) {
                final info = _qqRecommendations[index];
                return GestureDetector(
                  onTap: () => _openSonglistDetail(info),
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: info.imgUrl.isNotEmpty
                                  ? Image.network(
                                      info.imgUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _playlistCoverPlaceholder(
                                              colorScheme),
                                    )
                                  : _playlistCoverPlaceholder(colorScheme),
                            ),
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: GestureDetector(
                                onTap: () => _quickImport(info),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add_rounded,
                                      color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          info.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _playlistCoverPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Icon(Icons.queue_music_rounded,
          color: colorScheme.primary, size: 32),
    );
  }

  Future<void> _quickImport(LxSonglistInfo info) async {
    final id = 'import_tx_${info.id}';
    final existing = await LxStorage.instance.getPlaylists();
    if (existing.any((p) => p['id'] == id)) {
      SmartDialog.showToast('「${info.name}」已在列表中');
      return;
    }
    final now = DateTime.now().toIso8601String();
    existing.insert(0, {
      'id': id,
      'name': info.name,
      'createTime': now,
      'updateTime': now,
      'coverUrl': info.imgUrl.isNotEmpty ? info.imgUrl : null,
      'songs': <Map<String, dynamic>>[],
    });
    await LxStorage.instance.savePlaylists(existing);
    await _load();
    SmartDialog.showToast('已收藏歌单「${info.name}」');
  }
}

// ==================== 歌单详情页（内嵌） ====================

class _LxPlaylistDetailPage extends StatefulWidget {
  final String playlistId;
  final String playlistName;

  const _LxPlaylistDetailPage({
    required this.playlistId,
    required this.playlistName,
  });

  @override
  State<_LxPlaylistDetailPage> createState() => _LxPlaylistDetailPageState();
}

class _LxPlaylistDetailPageState extends State<_LxPlaylistDetailPage> {
  List<LxMusic> _songs = [];
  bool _loading = true;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _title = widget.playlistName;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await LxStorage.instance.getPlaylists();
      final playlist = list.firstWhere(
        (p) => p['id'] == widget.playlistId,
        orElse: () => {},
      );
      final songs = (playlist['songs'] as List?) ?? [];
      _songs = songs
          .whereType<Map>()
          .map((e) => LxMusic.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (playlist['name'] != null) {
        _title = playlist['name'].toString();
      }

      if (_songs.isEmpty &&
          (widget.playlistId.startsWith('import_tx_') ||
              widget.playlistId.startsWith('import_wy_'))) {
        await _autoFetchSongs();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _autoFetchSongs() async {
    try {
      String source = 'tx';
      String id = '';
      if (widget.playlistId.startsWith('import_tx_')) {
        source = 'tx';
        id = widget.playlistId.replaceFirst('import_tx_', '');
      } else if (widget.playlistId.startsWith('import_wy_')) {
        source = 'wy';
        id = widget.playlistId.replaceFirst('import_wy_', '');
      } else {
        return;
      }

      final service = LxSonglistService.instance;
      final detail = source == 'wy'
          ? await service.getWYPlaylistDetail(id)
          : await service.getQQPlaylistDetail(id);
      if (detail == null) return;

      final list = await LxStorage.instance.getPlaylists();
      final idx = list.indexWhere((p) => p['id'] == widget.playlistId);
      if (idx >= 0) {
        list[idx]['songs'] = detail.songs.map((m) => m.toJson()).toList();
        if (detail.name.isNotEmpty) list[idx]['name'] = detail.name;
        if (detail.imgUrl.isNotEmpty) {
          list[idx]['coverUrl'] = detail.imgUrl;
        }
        list[idx]['updateTime'] = DateTime.now().toIso8601String();
        await LxStorage.instance.savePlaylists(list);
      }
      _songs = detail.songs;
      if (detail.name.isNotEmpty) _title = detail.name;
    } catch (_) {}
  }

  Future<void> _removeSong(LxMusic music) async {
    await LxStorage.instance
        .removeSongFromPlaylist(widget.playlistId, music.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text('$_title (${_songs.length})',
            style: const TextStyle(fontSize: 18)),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          if (_songs.isNotEmpty)
            IconButton(
              tooltip: '播放全部',
              icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
              onPressed: () => LxPlayerHelper.playList(_songs, 0),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
              ? Center(
                  child: Text('歌单为空',
                      style: TextStyle(color: colorScheme.outline)))
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 2),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: song.imgUrl != null &&
                                    song.imgUrl!.isNotEmpty
                                ? Image.network(song.imgUrl!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _thumb(colorScheme))
                                : _thumb(colorScheme),
                          ),
                          title: Text(
                            song.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: colorScheme.onSurface, fontSize: 14),
                          ),
                          subtitle: Text(
                            song.singer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert_rounded,
                                color: colorScheme.outline, size: 20),
                            tooltip: '',
                            onSelected: (v) {
                              if (v == 'remove') _removeSong(song);
                              if (v == 'add') {
                                LxPlaylistHelper.showAddToPlaylistSheet(
                                    context, song);
                              }
                              if (v == 'play') {
                                LxPlayerHelper.playList(_songs, index);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                  value: 'play', child: Text('播放')),
                              const PopupMenuItem(
                                  value: 'add', child: Text('添加到其它歌单')),
                              const PopupMenuItem(
                                  value: 'remove', child: Text('从列表移除')),
                            ],
                          ),
                          onTap: () =>
                              LxPlayerHelper.playList(_songs, index),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _thumb(ColorScheme colorScheme) {
    return Container(
      width: 48,
      height: 48,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Icon(Icons.music_note_rounded,
          color: colorScheme.primary, size: 20),
    );
  }
}