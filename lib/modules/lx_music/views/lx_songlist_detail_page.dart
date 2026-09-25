import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/lx_songlist_controller.dart';
import '../models/lx_music_model.dart';
import '../utils/lx_logger.dart';
import '../utils/lx_player_helper.dart';

class LxSonglistDetailPage extends StatefulWidget {
  final String songlistId;
  final String songlistName;
  final String source;

  const LxSonglistDetailPage({
    super.key,
    required this.songlistId,
    required this.songlistName,
    required this.source,
  });

  @override
  State<LxSonglistDetailPage> createState() => _LxSonglistDetailPageState();
}

class _LxSonglistDetailPageState extends State<LxSonglistDetailPage> {
  final LxSonglistController _controller = Get.find<LxSonglistController>();

  List<LxMusic> _songs = [];
  String _title = '';
  String _imgUrl = '';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = widget.songlistName;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _controller.loadDetail(
        songlistId: widget.songlistId,
        source: widget.source,
      );

      if (result != null && mounted) {
        setState(() {
          _songs = result.songs;
          _title = result.name.isNotEmpty ? result.name : _title;
          _imgUrl = result.imgUrl.isNotEmpty ? result.imgUrl : _imgUrl;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '歌单加载失败';
        });
      }
    } catch (e) {
      LxLogger.error('歌单详情失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(_title, style: const TextStyle(fontSize: 16)),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(colorScheme)
              : _buildBody(colorScheme),
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              color: colorScheme.error, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextButton(onPressed: _loadDetail, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    return Column(
      children: [
        // 头部信息
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _imgUrl.isNotEmpty
                    ? Image.network(_imgUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _thumb(colorScheme))
                    : _thumb(colorScheme),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title,
                        style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('${_songs.length} 首歌曲',
                        style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12)),
                  ],
                ),
              ),
              if (_songs.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => LxPlayerHelper.playList(_songs, 0),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('播放'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: colorScheme.outlineVariant),
        Expanded(
          child: _songs.isEmpty
              ? Center(
                  child: Text('列表为空',
                      style:
                          TextStyle(color: colorScheme.onSurfaceVariant)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: _songs.length,
                  itemBuilder: (context, index) =>
                      _buildItem(_songs[index], index, colorScheme),
                ),
        ),
      ],
    );
  }

  Widget _buildItem(LxMusic music, int index, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: SizedBox(
          width: 32,
          child: Center(
            child: Text(
              '${index + 1}',
              style:
                  TextStyle(color: colorScheme.primary, fontSize: 13),
            ),
          ),
        ),
        title: Text(music.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14)),
        subtitle: Text(music.singer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
        trailing: Icon(Icons.play_arrow_rounded,
            color: colorScheme.primary, size: 20),
        onTap: () => LxPlayerHelper.playList(_songs, index),
      ),
    );
  }

  Widget _thumb(ColorScheme colorScheme) {
    return Container(
      width: 64,
      height: 64,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: Icon(Icons.queue_music_rounded,
          color: colorScheme.primary, size: 28),
    );
  }
}