import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/lx_music/controllers/lx_board_controller.dart';
import 'package:yuanying/modules/lx_music/models/lx_board_model.dart';
import 'package:yuanying/modules/lx_music/models/lx_music_model.dart';
import 'package:yuanying/modules/lx_music/services/lx_board_service.dart';
import 'package:yuanying/modules/lx_music/utils/lx_player_helper.dart';

/// 洛雪音乐榜单 Tab
///
/// 布局：
/// ┌──────────────────────────────────────┐
/// │ [酷我] [酷狗] [QQ] [网易]            │  第一行：平台
/// ├──────────────────────────────────────┤
/// │ [飙升榜] [热歌榜] [新歌榜] ...        │  第二行：榜单分类（横向滚动）
/// ├──────────────────────────────────────┤
/// │  歌曲列表                             │
/// │  ...                                  │
/// └──────────────────────────────────────┘
class LxBoardTab extends StatefulWidget {
  const LxBoardTab({super.key});

  @override
  State<LxBoardTab> createState() => _LxBoardTabState();
}

class _LxBoardTabState extends State<LxBoardTab> {
  final ScrollController _scrollController = ScrollController();

  LxBoardController get _controller => Get.find<LxBoardController>();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _controller.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ===== 第一行：平台选择 =====
        _buildSourceBar(colorScheme),
        // ===== 第二行：榜单分类 =====
        _buildBoardBar(colorScheme),
        // ===== 歌曲列表 =====
        Expanded(child: _buildContent(colorScheme)),
      ],
    );
  }

  // ==================== 平台选择栏 ====================

  Widget _buildSourceBar(ColorScheme colorScheme) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surface,
      child: Obx(() {
        final current = _controller.source.value;
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _controller.supportedSources.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final src = _controller.supportedSources[index];
            final name = LxBoardService.sourceNames[src] ?? src;
            final selected = src == current;

            return GestureDetector(
              onTap: () => _controller.setSource(src),
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
                  name,
                  style: TextStyle(
                    color: selected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }

  // ==================== 榜单分类栏 ====================

  Widget _buildBoardBar(ColorScheme colorScheme) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: colorScheme.surface,
      child: Obx(() {
        final boards = _controller.boards;
        final currentId = _controller.currentBoard.value?.id;

        if (boards.isEmpty) {
          return Center(
            child: Text(
              '该源暂无榜单',
              style: TextStyle(color: colorScheme.outline, fontSize: 12),
            ),
          );
        }

        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: boards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final board = boards[index];
            final selected = board.id == currentId;

            return Center(
              child: GestureDetector(
                onTap: () => _controller.selectBoard(board),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primaryContainer
                            .withValues(alpha: 0.6)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      width: selected ? 1.2 : 0.8,
                    ),
                  ),
                  child: Text(
                    board.name,
                    style: TextStyle(
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      fontSize: 11.5,
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

  // ==================== 内容区 ====================

  Widget _buildContent(ColorScheme colorScheme) {
    return Obx(() {
      // 加载中（首次）
      if (_controller.isLoading.value && _controller.songs.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      // 错误
      if (_controller.error.value.isNotEmpty &&
          _controller.songs.isEmpty) {
        return _buildError(colorScheme);
      }

      // 空
      if (_controller.songs.isEmpty) {
        return Center(
          child: Text(
            '暂无数据',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        );
      }

      // 列表
      return _buildList(colorScheme);
    });
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: colorScheme.error),
          const SizedBox(height: 12),
          Obx(() => Text(
                _controller.error.value,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _controller.refresh(),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme colorScheme) {
    return Obx(() {
      final songs = _controller.songs;
      final loadingMore = _controller.isLoadingMore.value;
      final hasMore = _controller.hasMore;

      return RefreshIndicator(
        onRefresh: () => _controller.refresh(),
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: songs.length + 1,
          itemBuilder: (context, index) {
            if (index == songs.length) {
              return _buildFooter(
                  colorScheme, loadingMore, hasMore, songs.length);
            }

            final music = songs[index];
            return _buildMusicItem(music, index, songs, colorScheme);
          },
        ),
      );
    });
  }

  Widget _buildFooter(ColorScheme colorScheme, bool loadingMore, bool hasMore,
      int songCount) {
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            songCount > 0 ? '已经到底了' : '',
            style: TextStyle(color: colorScheme.outline, fontSize: 12),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          '上滑加载更多',
          style: TextStyle(color: colorScheme.outline, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildMusicItem(
    LxMusic music,
    int index,
    List<LxMusic> playlist,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => LxPlayerHelper.playList(playlist, index),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // ===== 封面 =====
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: music.imgUrl != null && music.imgUrl!.isNotEmpty
                          ? Image.network(
                              music.imgUrl!,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _coverPlaceholder(colorScheme),
                            )
                          : _coverPlaceholder(colorScheme),
                    ),
                    // 排名徽章（左上角）
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _rankColor(index, colorScheme),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: index < 3
                                ? Colors.white
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // ===== 歌曲信息 =====
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        music.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        music.singer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (music.album.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          music.album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.outline,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // ===== 菜单 =====
                PopupMenuButton<String>(
                  tooltip: '',
                  icon: Icon(Icons.more_vert_rounded,
                      color: colorScheme.outline, size: 20),
                  onSelected: (v) =>
                      _handleMenuAction(v, music, playlist, index),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'play', child: Text('播放')),
                    const PopupMenuItem(
                        value: 'next', child: Text('下一首播放')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 封面占位图
  Widget _coverPlaceholder(ColorScheme colorScheme) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: colorScheme.primary,
        size: 24,
      ),
    );
  }

  Color _rankColor(int index, ColorScheme colorScheme) {
    if (index == 0) return const Color(0xFFE8B34B);
    if (index == 1) return const Color(0xFFB8BFC8);
    if (index == 2) return const Color(0xFFC89B6C);
    return colorScheme.surfaceContainerHighest;
  }

  void _handleMenuAction(
    String action,
    LxMusic music,
    List<LxMusic> playlist,
    int index,
  ) {
    switch (action) {
      case 'play':
        LxPlayerHelper.playList(playlist, index);
        break;
      case 'next':
        LxPlayerHelper.playList([music], 0);
        break;
    }
  }
}