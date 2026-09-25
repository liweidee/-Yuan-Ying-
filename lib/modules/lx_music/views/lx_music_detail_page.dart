import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../../../t4/models/play_url.dart';
import '../../../t4/models/video_detail.dart';
import '../../music/controllers/music_player_controller.dart';
import '../../music/views/music_player_view.dart';
import '../../music/widgets/music_list_tile.dart';
import '../models/lx_music_model.dart';
import '../services/lx_lyric_api_service.dart';
import '../services/lx_music_url_service.dart';
import '../storage/lx_storage.dart';
import '../utils/lx_logger.dart';
import 'package:yuanying/modules/lx_music/storage/lx_settings_storage.dart';
import 'package:yuanying/modules/lx_music/utils/lx_playlist_helper.dart';
import 'package:yuanying/modules/lx_music/utils/lx_player_helper.dart';
import 'package:yuanying/modules/lx_music/controllers/lx_download_controller.dart';

/// 每页分组的大小（每 50 首一组，与音乐详情页一致）
const int _kGroupSize = 50;

/// 洛雪音乐详情页
class LxMusicDetailPage extends StatefulWidget {
  const LxMusicDetailPage({super.key});

  @override
  State<LxMusicDetailPage> createState() => _LxMusicDetailPageState();
}

class _LxMusicDetailPageState extends State<LxMusicDetailPage> {
  late final List<LxMusic> _musics;
  late final MusicPlayerController _controller;

  bool _desc = false;
  bool _isGrid = false;

  /// 当前选中的分组（null = 全部）
  int? _selectedGroup;

  final Set<String> _favCache = {};

  @override
  void initState() {
    super.initState();

    // 延后到首帧后置位，避免 build 期改 Rx
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      LxPlayerHelper.hasPlayedInSession.value = true;
    });

    final args = Get.arguments as Map?;
    final rawMusics = args?['musics'];
    if (rawMusics is List) {
      _musics = rawMusics.whereType<LxMusic>().toList();
    } else {
      _musics = [];
    }

    _controller = Get.isRegistered<MusicPlayerController>()
        ? Get.find<MusicPlayerController>()
        : Get.put(MusicPlayerController(), permanent: true);

    // 接管 onPlayCompleted
    _controller.onPlayCompleted = _onPlayCompleted;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshFavCache();
  }

  @override
  void dispose() {
    if (_controller.onPlayCompleted == _onPlayCompleted) {
      _controller.onPlayCompleted = null;
    }
    super.dispose();
  }

  /// 曲目播放完成 → 切下一曲
  void _onPlayCompleted() {
    final idx = _controller.currentIndex.value;
    if (idx >= 0 && idx < _musics.length) {
      _playSong(idx);
    }
  }

  /// 获取可见索引（倒序 + 分组）
  ///
  /// 返回的是「原始索引」列表：
  /// - _desc 倒序时，原列表反转
  /// - _selectedGroup 非空时，按原始索引范围 [start, end) 过滤
  List<int> _getVisibleIndices(int total) {
    List<int> indices = List.generate(total, (i) => i);
    if (_desc) indices = indices.reversed.toList();
    if (_selectedGroup != null) {
      final start = _selectedGroup! * _kGroupSize;
      final end = (start + _kGroupSize).clamp(0, total);
      indices = indices.where((i) => i >= start && i < end).toList();
    }
    return indices;
  }

  /// 播放列表第 index 首
  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _musics.length) return;

    final music = _musics[index];
    LxPlayerHelper.currentLxMusic = music;
    LxLogger.info('洛雪详情页切歌: ${music.name} - ${music.singer}');

    _controller.currentIndex.value = index;

    _controller.updateSongInfo(
      cover: music.imgUrl,
      author: music.singer,
      album: music.album,
    );

    final url = await _fetchUrl(music);
    if (url == null || url.isEmpty) {
      SmartDialog.showToast('无法获取播放地址');
      return;
    }

    final playUrl = PlayUrl(
      parse: 0,
      qualities: [PlayQuality(label: '洛雪', url: url)],
    );

    _fetchLyric(music);

    await _controller.playWithUrl(playUrl, index: index);
    _saveToLxHistory(music);
  }

  Future<String?> _fetchUrl(LxMusic music) async {
    try {
      final quality = await LxSettingsStorage.instance.getQuality();
      return await LxMusicUrlService.instance.getMusicUrl(
        music: music,
        quality: quality,
      );
    } catch (e) {
      LxLogger.error('取 URL 失败: $e');
      return null;
    }
  }

  void _fetchLyric(LxMusic music) {
    LxLyricApiService.instance.getLyric(music).then((lyricData) {
      if (lyricData == null) return;
      final lrc = lyricData['lyric'];
      if (lrc != null && lrc.isNotEmpty) {
        _controller.setLyric(lrc);
      }
    }).catchError((_) {});
  }

  Future<void> _saveToLxHistory(LxMusic music) async {
    try {
      await LxStorage.instance.addPlayHistory({
        'id': music.id,
        'name': music.name,
        'singer': music.singer,
        'album': music.album,
        'imgUrl': music.imgUrl,
        'source': music.source,
        'songId': music.songId,
        'songmid': music.songmid,
        'hash': music.hash,
        'songUrl': music.songUrl,
        'duration': music.duration,
        'playTime': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  Future<void> _refreshFavCache() async {
    try {
      final list = await LxStorage.instance.getFavorites();
      _favCache
        ..clear()
        ..addAll(list.map((e) => e['id']?.toString() ?? ''));
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final vodId = _controller.currentVodId;
    if (vodId == null || vodId.isEmpty) {
      SmartDialog.showToast('无法获取歌曲ID');
      return;
    }

    try {
      final list = await LxStorage.instance.getFavorites();
      final idx = list.indexWhere((item) => item['id'] == vodId);

      if (idx >= 0) {
        list.removeAt(idx);
        await LxStorage.instance.saveFavorites(list);
        SmartDialog.showToast('已取消收藏');
      } else {
        final episode = _controller.currentEpisode;
        list.insert(0, {
          'id': vodId,
          'name': episode?.name ?? '',
          'singer': _controller.author.value,
          'album': _controller.albumName.value,
          'imgUrl': _controller.coverUrl.value,
          'source': 'lx',
          'addTime': DateTime.now().millisecondsSinceEpoch,
        });
        await LxStorage.instance.saveFavorites(list);
        SmartDialog.showToast('已收藏');
      }
      await _refreshFavCache();
      _controller.notifyFavoriteChanged();
    } catch (e) {
      SmartDialog.showToast('操作失败: $e');
    }
  }

  void _handleSongMenu(String action, LxMusic music, int index) {
    switch (action) {
      case 'play':
        _playSong(index);
        break;
      case 'next':
        LxPlayerHelper.playList([music], 0);
        SmartDialog.showToast('已添加到下一首播放');
        break;
      case 'add':
        LxPlaylistHelper.showAddToPlaylistSheet(context, music);
        break;
      case 'fav':
        _addToFavorites(music);
        break;
      case 'download':
        _downloadSong(music);
        break;
      case 'remove':
        _removeFromList(music);
        break;
    }
  }

  Future<void> _addToFavorites(LxMusic music) async {
    try {
      final list = await LxStorage.instance.getFavorites();
      final exists = list.any((item) => item['id'] == music.id);
      if (exists) {
        SmartDialog.showToast('已经在「我喜欢」里了');
        return;
      }
      list.insert(0, {
        'id': music.id,
        'name': music.name,
        'singer': music.singer,
        'album': music.album,
        'imgUrl': music.imgUrl,
        'source': music.source,
        'addTime': DateTime.now().millisecondsSinceEpoch,
      });
      await LxStorage.instance.saveFavorites(list);
      SmartDialog.showToast('已添加到「我喜欢」');
    } catch (e) {
      SmartDialog.showToast('添加失败: $e');
    }
  }

  Future<void> _downloadSong(LxMusic music) async {
    try {
      SmartDialog.showToast('正在获取下载地址...');
      final url =
          await LxMusicUrlService.instance.getMusicUrl(music: music);
      if (url == null || url.isEmpty) {
        SmartDialog.showToast('无法获取下载地址');
        return;
      }

      final downloadCtrl = Get.isRegistered<LxDownloadController>()
          ? Get.find<LxDownloadController>()
          : Get.put(LxDownloadController());

      await downloadCtrl.download(music.copyWith(songUrl: url));
      SmartDialog.showToast('已加入下载队列');
    } catch (e) {
      SmartDialog.showToast('下载失败: $e');
    }
  }

  Future<void> _removeFromList(LxMusic music) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerLow,
          title: const Text('移除'),
          content: Text('从当前列表移除「${music.name}」？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('移除',
                  style: TextStyle(color: colorScheme.error)),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    setState(() {
      _musics.removeWhere((m) => m.id == music.id);
    });
    SmartDialog.showToast('已移除');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('洛雪音乐'),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          Obx(() {
            final _ = _controller.favoriteVersion.value;
            final vodId = _controller.currentVodId;
            final isFav = vodId != null &&
                vodId.isNotEmpty &&
                _favCache.contains(vodId);
            return IconButton(
              icon: Icon(
                isFav ? Icons.star : Icons.star_border,
                color: isFav ? colorScheme.primary : colorScheme.outline,
              ),
              onPressed: _toggleFavorite,
              tooltip: isFav ? '取消收藏' : '收藏',
            );
          }),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(colorScheme),
              _buildListHeader(colorScheme),
              Expanded(child: _buildPlaylist(colorScheme)),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: const MusicPlayerView(cancelMargin: true),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Obx(() {
      final idx = _controller.currentIndex.value;
      final music =
          (idx >= 0 && idx < _musics.length) ? _musics[idx] : null;
      if (music == null) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: music.imgUrl != null && music.imgUrl!.isNotEmpty
                  ? Image.network(
                      music.imgUrl!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _coverPlaceholder(colorScheme),
                    )
                  : _coverPlaceholder(colorScheme),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    music.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (music.singer.isNotEmpty)
                    Text(
                      '歌手：${music.singer}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.outline,
                      ),
                    ),
                  if (music.album.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '专辑：${music.album}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '来源：洛雪音乐',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _coverPlaceholder(ColorScheme colorScheme) {
    return Container(
      width: 80,
      height: 80,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, color: colorScheme.outline, size: 40),
    );
  }

  Widget _buildListHeader(ColorScheme colorScheme) {
    final total = _musics.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '播放列表',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$total 首',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CatalogIconButton(
                icon: _desc
                    ? Icons.vertical_align_top
                    : Icons.vertical_align_bottom,
                tooltip: _desc ? '正序' : '倒序',
                isActive: _desc,
                onTap: () => setState(() => _desc = !_desc),
              ),
              _CatalogIconButton(
                icon: _isGrid
                    ? Icons.grid_view_rounded
                    : Icons.view_list_rounded,
                tooltip: _isGrid ? '网格' : '列表',
                isActive: _isGrid,
                onTap: () => setState(() => _isGrid = !_isGrid),
              ),
              // 分组按钮
              _CatalogGroupButton(
                total: total,
                selectedGroup: _selectedGroup,
                onChanged: (v) => setState(() => _selectedGroup = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylist(ColorScheme colorScheme) {
    return Obx(() {
      final currentIdx = _controller.currentIndex.value;
      final isPlayingNow = _controller.playing.value;
      final total = _musics.length;

      // 用统一的可见索引计算
      final displayIndices = _getVisibleIndices(total);

      if (_isGrid) {
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.2,
          ),
          itemCount: displayIndices.length,
          itemBuilder: (context, i) {
            final originalIndex = displayIndices[i];
            final music = _musics[originalIndex];
            final isCurrent = currentIdx == originalIndex;
            return InkWell(
              onTap: () => _playSong(originalIndex),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: isCurrent
                      ? Border.all(color: colorScheme.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${i + 1}. ${music.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isCurrent
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          },
        );
      }

      // 列表模式
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 80, left: 12, right: 12),
        itemCount: displayIndices.length,
        itemBuilder: (context, i) {
          final originalIndex = displayIndices[i];
          final music = _musics[originalIndex];
          final isCurrent = currentIdx == originalIndex;
          final isPlaying = isCurrent && isPlayingNow;

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: isCurrent
                  ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _playSong(originalIndex),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Center(
                          child: isCurrent
                              ? Icon(
                                  isPlaying
                                      ? Icons.equalizer_rounded
                                      : Icons.pause_rounded,
                                  color: colorScheme.primary,
                                  size: 18,
                                )
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: colorScheme.outline,
                                    fontSize: 13,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              music.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              music.singer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded,
                            color: colorScheme.outline, size: 20),
                        tooltip: '',
                        onSelected: (v) =>
                            _handleSongMenu(v, music, originalIndex),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                              value: 'play', child: Text('播放')),
                          const PopupMenuItem(
                              value: 'next', child: Text('下一首播放')),
                          const PopupMenuItem(
                              value: 'add', child: Text('添加到歌单')),
                          const PopupMenuItem(
                              value: 'fav', child: Text('我喜欢')),
                          const PopupMenuItem(
                              value: 'download', child: Text('下载')),
                          const PopupMenuItem(
                              value: 'remove',
                              child: Text('从列表移除')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

// ==================== 辅助组件：目录图标按钮 ====================

class _CatalogIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;
  const _CatalogIconButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

// ==================== 辅助组件：分组按钮 ====================

class _CatalogGroupButton extends StatelessWidget {
  final int total;
  final int? selectedGroup;
  final ValueChanged<int?> onChanged;
  const _CatalogGroupButton({
    required this.total,
    required this.selectedGroup,
    required this.onChanged,
  });

  List<PopupMenuEntry<int?>> _buildMenuItems(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = <PopupMenuEntry<int?>>[
      PopupMenuItem<int?>(
        value: null,
        child: Text(
          '全部',
          style: TextStyle(
            fontSize: 13,
            color: selectedGroup == null ? colorScheme.primary : null,
          ),
        ),
      ),
    ];
    if (total <= 0) return items;

    final n = (total / _kGroupSize).ceil();
    for (int g = 0; g < n; g++) {
      final start = g * _kGroupSize + 1;
      final end = ((g + 1) * _kGroupSize).clamp(0, total);
      final isSel = selectedGroup == g;
      items.add(PopupMenuItem<int?>(
        value: g,
        child: Text(
          '$start-$end',
          style: TextStyle(
            fontSize: 13,
            color: isSel ? colorScheme.primary : null,
          ),
        ),
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '分组',
      child: InkWell(
        onTap: () async {
          final RenderBox button =
              context.findRenderObject() as RenderBox;
          final RenderBox overlay = Overlay.of(context)
              .context
              .findRenderObject() as RenderBox;
          final Rect rect = Rect.fromPoints(
            button.localToGlobal(Offset.zero, ancestor: overlay),
            button.localToGlobal(
                button.size.bottomRight(Offset.zero),
                ancestor: overlay),
          );
          final result = await showMenu<int?>(
            context: context,
            position:
                RelativeRect.fromRect(rect, Offset.zero & overlay.size),
            items: _buildMenuItems(context),
            color: colorScheme.surfaceContainerLow,
          );
          onChanged(result);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selectedGroup != null
                ? colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.segment_rounded,
            size: 20,
            color: selectedGroup != null
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}