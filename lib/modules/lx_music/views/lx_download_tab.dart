import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/lx_download_controller.dart';
import '../models/lx_download_model.dart';
import '../models/lx_music_model.dart';
import '../utils/lx_player_helper.dart';

/// 下载 Tab
class LxDownloadTab extends StatefulWidget {
  const LxDownloadTab({super.key});

  @override
  State<LxDownloadTab> createState() => _LxDownloadTabState();
}

class _LxDownloadTabState extends State<LxDownloadTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  LxDownloadController get _controller =>
      Get.find<LxDownloadController>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          color: colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: [
              Obx(() => Tab(
                  text: '下载中 (${_controller.downloadingCount})')),
              Obx(() => Tab(
                  text: '已完成 (${_controller.downloadedSongs.length})')),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDownloadingList(colorScheme),
              _buildDownloadedList(colorScheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadingList(ColorScheme colorScheme) {
    return Obx(() {
      if (_controller.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      final active = _controller.queue
          .where((t) =>
              t.status == LxDownloadStatus.downloading ||
              t.status == LxDownloadStatus.pending)
          .toList();
      final failed = _controller.queue
          .where((t) => t.status == LxDownloadStatus.failed)
          .toList();

      if (active.isEmpty && failed.isEmpty) {
        return _emptyState(
            '暂无下载任务', Icons.download_outlined, colorScheme);
      }

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...active.map((t) => _buildActiveItem(t, colorScheme)),
          ...failed.map((t) => _buildFailedItem(t, colorScheme)),
        ],
      );
    });
  }

  Widget _buildActiveItem(
      LxDownloadTask task, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _thumb(task.music, colorScheme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.music.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: task.progress / 100,
                        backgroundColor: colorScheme.outlineVariant,
                        color: colorScheme.primary,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${task.quality} · ${task.progress}%',
                        style: TextStyle(
                            color: colorScheme.outline, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    color: colorScheme.outline, size: 20),
                onPressed: () => _controller.cancel(task.music.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFailedItem(
      LxDownloadTask task, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.errorContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _thumb(task.music, colorScheme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.music.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colorScheme.onSurface, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(task.error ?? '下载失败',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colorScheme.error, fontSize: 11)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _controller.retry(task.music.id),
                child: const Text('重试'),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    color: colorScheme.outline, size: 18),
                onPressed: () => _controller.remove(task.music.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadedList(ColorScheme colorScheme) {
    return Obx(() {
      final songs = _controller.downloadedSongs;
      if (songs.isEmpty) {
        return _emptyState('暂无已下载歌曲', Icons.music_off_outlined,
            colorScheme);
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: _thumb(song, colorScheme),
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
                trailing: PopupMenuButton<String>(
                  tooltip: '',
                  icon: Icon(Icons.more_vert_rounded,
                      color: colorScheme.outline, size: 20),
                  onSelected: (v) {
                    if (v == 'play') {
                      LxPlayerHelper.playList(songs, index);
                    } else if (v == 'delete') {
                      _controller.deleteDownloaded(song);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'play', child: Text('播放')),
                    const PopupMenuItem(
                        value: 'delete', child: Text('删除')),
                  ],
                ),
                onTap: () => LxPlayerHelper.playList(songs, index),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _thumb(LxMusic music, ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: music.imgUrl != null && music.imgUrl!.isNotEmpty
          ? Image.network(
              music.imgUrl!,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _defaultThumb(colorScheme),
            )
          : _defaultThumb(colorScheme),
    );
  }

  Widget _defaultThumb(ColorScheme colorScheme) {
    return Container(
      width: 44,
      height: 44,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Icon(Icons.music_note_rounded,
          color: colorScheme.primary, size: 20),
    );
  }

  Widget _emptyState(
      String text, IconData icon, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: colorScheme.outline),
          const SizedBox(height: 12),
          Text(text,
              style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}