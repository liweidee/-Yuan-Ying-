import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/lx_songlist_controller.dart';
import '../models/lx_songlist_model.dart';
import 'lx_songlist_detail_page.dart';

class LxSonglistTab extends StatefulWidget {
  const LxSonglistTab({super.key});

  @override
  State<LxSonglistTab> createState() => _LxSonglistTabState();
}

class _LxSonglistTabState extends State<LxSonglistTab> {
  final TextEditingController _searchController = TextEditingController();

  LxSonglistController get _controller => Get.find<LxSonglistController>();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 歌单源选择
        _buildSourceSelector(colorScheme),
        // 搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (q) => _controller.searchSonglists(q),
              decoration: InputDecoration(
                hintText: '搜索歌单',
                hintStyle:
                    TextStyle(color: colorScheme.outline, fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded,
                    color: colorScheme.outline, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        // 内容
        Expanded(
          child: Obx(() {
            if (_controller.isSearching.value) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_controller.searchError.value.isNotEmpty) {
              return Center(
                child: Text(_controller.searchError.value,
                    style: TextStyle(color: colorScheme.onSurfaceVariant)),
              );
            }
            if (_controller.searchResults.isNotEmpty) {
              return _buildSearchResultList(colorScheme);
            }
            return _buildRecommendList(colorScheme);
          }),
        ),
      ],
    );
  }

  Widget _buildSourceSelector(ColorScheme colorScheme) {
    const options = [
      ('tx', '小秋音乐'),
      ('kw', '小蜗音乐'),
      ('wy', '小芸音乐'),
      ('all', '聚合'),
    ];
    return SizedBox(
      height: 48,
      child: Obx(() {
        final current = _controller.searchSource.value;
        return ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: options.map((opt) {
            final selected = current == opt.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  _controller.setSearchSource(opt.$1);
                  if (_searchController.text.trim().isNotEmpty) {
                    _controller.searchSonglists(_searchController.text);
                  } else {
                    // 触发刷新
                    _controller.searchResults.clear();
                  }
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

  Widget _buildSearchResultList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _controller.searchResults.length,
      itemBuilder: (context, index) =>
          _buildPlaylistItem(_controller.searchResults[index], colorScheme),
    );
  }

  Widget _buildRecommendList(ColorScheme colorScheme) {
    return Obx(() {
      if (_controller.isLoadingRecommend.value &&
          _controller.recommendPlaylists.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      return RefreshIndicator(
        onRefresh: () => _controller.loadRecommend(),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _controller.recommendPlaylists.length,
          itemBuilder: (context, index) => _buildPlaylistItem(
              _controller.recommendPlaylists[index], colorScheme),
        ),
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
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: info.imgUrl.isNotEmpty
                ? Image.network(
                    info.imgUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _defaultThumb(colorScheme),
                  )
                : _defaultThumb(colorScheme),
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

  Widget _defaultThumb(ColorScheme colorScheme) {
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
    if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
  }
}