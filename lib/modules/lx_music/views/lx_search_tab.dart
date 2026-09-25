import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/lx_music/controllers/lx_search_controller.dart';
import 'package:yuanying/modules/lx_music/models/lx_music_model.dart';
import 'package:yuanying/modules/lx_music/models/lx_songlist_model.dart';
import 'package:yuanying/modules/lx_music/services/lx_music_search_service.dart';
import 'package:yuanying/modules/lx_music/services/lx_songlist_service.dart';
import 'package:yuanying/modules/lx_music/utils/lx_player_helper.dart';
import 'package:yuanying/modules/lx_music/utils/lx_playlist_helper.dart';
import 'package:yuanying/modules/lx_music/views/lx_songlist_detail_page.dart';

/// 搜索页（歌曲 + 歌单双 Tab）
class LxSearchTab extends StatefulWidget {
  const LxSearchTab({super.key});

  @override
  State<LxSearchTab> createState() => _LxSearchTabState();
}

class _LxSearchTabState extends State<LxSearchTab> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  bool _playlistMode = false;

  final RxString _playlistSource = 'tx'.obs;
  final RxList<LxSonglistInfo> _playlistResults = <LxSonglistInfo>[].obs;
  final RxBool _isSearchingPlaylists = false.obs;
  final RxString _playlistSearchError = ''.obs;

  LxSearchController get _controller => Get.find<LxSearchController>();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_playlistMode) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _controller.loadMore();
    }
  }

  void _onTextChanged() {
    if (_playlistMode) return;
    _controller.onQueryChanged(_searchController.text);
  }

  void _performSearch() {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    _focusNode.unfocus();
    if (_playlistMode) {
      _searchPlaylists(q);
    } else {
      _controller.hideSuggest();
      _controller.search(q);
    }
  }

  Future<void> _searchPlaylists(String keyword) async {
    if (keyword.isEmpty) return;
    _isSearchingPlaylists.value = true;
    _playlistSearchError.value = '';
    try {
      final list = await LxSonglistService.instance.searchSonglists(
        keyword,
        source: _playlistSource.value,
        page: 1,
        pageSize: 30,
      );
      _playlistResults.value = list;
    } catch (e) {
      _playlistResults.value = [];
      _playlistSearchError.value = '歌单搜索失败，请检查网络';
    } finally {
      _isSearchingPlaylists.value = false;
    }
  }

  void _switchMode(bool playlist) {
    if (_playlistMode == playlist) return;
    setState(() => _playlistMode = playlist);
    final q = _searchController.text.trim();
    if (q.isNotEmpty) _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _performSearch(),
                    decoration: InputDecoration(
                      hintText:
                          _playlistMode ? '搜索歌单' : '搜索歌曲、歌手、专辑',
                      hintStyle: TextStyle(
                          color: colorScheme.outline, fontSize: 14),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: colorScheme.outline, size: 20),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchController,
                        builder: (context, value, _) {
                          if (value.text.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return IconButton(
                            icon: Icon(Icons.clear_rounded,
                                color: colorScheme.outline, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              if (!_playlistMode) {
                                _controller.clear();
                              }
                            },
                          );
                        },
                      ),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _performSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildModeTab('歌曲', !_playlistMode, () => _switchMode(false)),
              const SizedBox(width: 8),
              _buildModeTab('歌单', _playlistMode, () => _switchMode(true)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _playlistMode
            ? _buildPlaylistSourceSelector(colorScheme)
            : _buildSourceSelector(colorScheme),
        Expanded(
          child: _playlistMode
              ? _buildPlaylistContent(colorScheme)
              : _buildSongContent(colorScheme),
        ),
      ],
    );
  }

  Widget _buildModeTab(String label, bool selected, VoidCallback onTap) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSourceSelector(ColorScheme colorScheme) {
    final sources = LxMusicSearchService.availableSources
        .map((id) => {
              'id': id,
              'name':
                  LxMusicSearchService.sourceNames[id] ?? id.toUpperCase()
            })
        .toList();

    return SizedBox(
      height: 48,
      child: Obx(() {
        final current = _controller.source.value;
        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: sources.length,
          itemBuilder: (context, index) {
            final s = sources[index];
            final selected = s['id'] == current;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _controller.setSource(s['id']!),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    s['name']!,
                    style: TextStyle(
                      color: selected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildPlaylistSourceSelector(ColorScheme colorScheme) {
    const options = [
      ('tx', '源三'),
      ('kw', '源一'),
      ('wy', '源四'),
      ('all', '聚合'),
    ];

    return SizedBox(
      height: 48,
      child: Obx(() {
        final current = _playlistSource.value;
        return ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: options.map((opt) {
            final selected = current == opt.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  if (_playlistSource.value == opt.$1) return;
                  _playlistSource.value = opt.$1;
                  final q = _searchController.text.trim();
                  if (q.isNotEmpty) _searchPlaylists(q);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    opt.$2,
                    style: TextStyle(
                      color: selected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      }),
    );
  }

  Widget _buildSongContent(ColorScheme colorScheme) {
    return Obx(() {
      final controller = _controller;
      if (controller.showSuggest.value) {
        return _buildSuggestList(colorScheme);
      }
      if (controller.query.value.isEmpty) {
        return _buildSuggestions(colorScheme);
      }
      if (controller.isLoading.value && controller.results.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error.value.isNotEmpty &&
          controller.results.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: colorScheme.error),
              const SizedBox(height: 12),
              Text(controller.error.value,
                  style:
                      TextStyle(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    controller.search(controller.query.value),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }
      return _buildResultList(colorScheme);
    });
  }

  Widget _buildSuggestList(ColorScheme colorScheme) {
    return Obx(() {
      final list = _controller.suggestResults;
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final keyword = list[index];
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              _searchController.text = keyword;
              _performSearch();
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.search_rounded,
                      color: colorScheme.outline, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      keyword,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13),
                    ),
                  ),
                  Icon(Icons.north_west_rounded,
                      color: colorScheme.outline, size: 14),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildSuggestions(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Obx(() {
        final history = _controller.searchHistory;
        final hot = _controller.hotSearches;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (history.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('搜索历史',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      )),
                  GestureDetector(
                    onTap: () => _controller.clearHistory(),
                    child: Text('清空',
                        style: TextStyle(
                            color: colorScheme.outline, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: history.map((keyword) {
                  return GestureDetector(
                    onTap: () {
                      _searchController.text = keyword;
                      _performSearch();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(keyword,
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
            ],
            Text('热门搜索',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: hot.asMap().entries.map((entry) {
                final index = entry.key;
                final keyword = entry.value;
                final isTop3 = index < 3;
                return GestureDetector(
                  onTap: () {
                    _searchController.text = keyword;
                    _performSearch();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isTop3
                          ? colorScheme.primaryContainer
                              .withValues(alpha: 0.4)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isTop3) ...[
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            alignment: Alignment.center,
                            child: Text('${index + 1}',
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                )),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(keyword,
                            style: TextStyle(
                              color: isTop3
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildResultList(ColorScheme colorScheme) {
    return Obx(() {
      final results = _controller.results;
      final loading = _controller.isLoadingMore.value;

      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: results.length + (loading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == results.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _buildMusicItem(
              results[index], index, results, colorScheme);
        },
      );
    });
  }

  Widget _buildMusicItem(
    LxMusic music,
    int index,
    List<LxMusic> playlist,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => LxPlayerHelper.playList(playlist, index),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      music.imgUrl != null && music.imgUrl!.isNotEmpty
                          ? Image.network(
                              music.imgUrl!,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _thumb(colorScheme),
                            )
                          : _thumb(colorScheme),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        music.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${music.singer} - ${music.album}',
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
                      _handleMenuAction(v, music, playlist, index),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'play', child: Text('播放')),
                    const PopupMenuItem(
                        value: 'next', child: Text('下一首播放')),
                    const PopupMenuItem(
                        value: 'add', child: Text('添加到歌单')),
                    const PopupMenuItem(
                        value: 'fav', child: Text('我喜欢')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(ColorScheme colorScheme) {
    return Container(
      width: 52,
      height: 52,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Icon(Icons.music_note_rounded,
          color: colorScheme.primary, size: 22),
    );
  }

  void _handleMenuAction(
      String action, LxMusic music, List<LxMusic> playlist, int index) {
    switch (action) {
      case 'play':
        LxPlayerHelper.playList(playlist, index);
        break;
      case 'next':
        LxPlayerHelper.playList([music], 0);
        SmartDialog.showToast('已添加到下一首播放');
        break;
      case 'add':
        LxPlaylistHelper.showAddToPlaylistSheet(context, music);
        break;
      case 'fav':
        LxPlaylistHelper.showMusicMoreMenu(context, music);
        break;
    }
  }

  Widget _buildPlaylistContent(ColorScheme colorScheme) {
    return Obx(() {
      if (_isSearchingPlaylists.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_playlistSearchError.value.isNotEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_playlistSearchError.value,
                  style:
                      TextStyle(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    _searchPlaylists(_searchController.text.trim()),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }
      if (_playlistResults.isEmpty) {
        return Center(
          child: Text(
            _searchController.text.trim().isEmpty
                ? '输入关键词搜索歌单'
                : '未找到相关歌单',
            style: TextStyle(color: colorScheme.outline, fontSize: 13),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _playlistResults.length,
        itemBuilder: (context, index) {
          final info = _playlistResults[index];
          return _buildPlaylistItem(info, colorScheme);
        },
      );
    });
  }

  Widget _buildPlaylistItem(LxSonglistInfo info, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: info.imgUrl.isNotEmpty
                ? Image.network(
                    info.imgUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _playlistThumb(colorScheme),
                  )
                : _playlistThumb(colorScheme),
          ),
          title: Text(
            info.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
          ),
          subtitle: Text(
            '${info.author}${info.playCount > 0 ? " · ${_fmtCount(info.playCount)}次播放" : ""}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
          trailing: Icon(Icons.chevron_right_rounded,
              color: colorScheme.outline, size: 20),
          onTap: () {
            Get.to(() => LxSonglistDetailPage(
                  songlistId: info.id,
                  songlistName: info.name,
                  source: info.source,
                ));
          },
        ),
      ),
    );
  }

  Widget _playlistThumb(ColorScheme colorScheme) {
    return Container(
      width: 52,
      height: 52,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Icon(Icons.queue_music_rounded,
          color: colorScheme.primary, size: 22),
    );
  }

  String _fmtCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    }
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }
}