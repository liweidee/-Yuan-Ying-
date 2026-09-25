import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../models/lx_music_model.dart';
import '../storage/lx_storage.dart';
import '../utils/lx_player_helper.dart';

/// 最近播放（洛雪历史）
class LxRecentPage extends StatefulWidget {
  const LxRecentPage({super.key});

  @override
  State<LxRecentPage> createState() => _LxRecentPageState();
}

class _LxRecentPageState extends State<LxRecentPage> {
  List<LxMusic> _recent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await LxStorage.instance.getPlayHistory();
      _recent = list.map((e) => LxMusic.fromJson(e)).toList();
    } catch (_) {
      _recent = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerLow,
          title: const Text('清空历史'),
          content: const Text('确定要清空洛雪播放历史吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('清空',
                  style: TextStyle(color: colorScheme.error)),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    await LxStorage.instance.clearPlayHistory();
    await _load();
    SmartDialog.showToast('已清空');
  }

  Future<void> _removeOne(LxMusic music) async {
    await LxStorage.instance.removePlayHistory(music.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text('最近播放 (${_recent.length})',
            style: const TextStyle(fontSize: 18)),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          if (_recent.isNotEmpty) ...[
            IconButton(
              tooltip: '随机播放',
              icon: const Icon(Icons.shuffle_rounded, size: 20),
              onPressed: () {
                final shuffled = List<LxMusic>.from(_recent)..shuffle();
                LxPlayerHelper.playList(shuffled, 0);
              },
            ),
            IconButton(
              tooltip: '播放全部',
              icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
              onPressed: () => LxPlayerHelper.playList(_recent, 0),
            ),
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: _clear,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _recent.isEmpty
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
            child: Icon(Icons.history_rounded,
                size: 40, color: colorScheme.primary),
          ),
          const SizedBox(height: 20),
          Text('暂无播放记录',
              style: TextStyle(
                  color: colorScheme.onSurfaceVariant, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _recent.length,
      itemBuilder: (context, index) {
        final song = _recent[index];
        return Padding(
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
                  style:
                      TextStyle(color: colorScheme.onSurface, fontSize: 14)),
              subtitle: Text(song.singer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 12)),
              trailing: IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    color: colorScheme.outline, size: 20),
                onPressed: () => _removeOne(song),
              ),
              onTap: () => LxPlayerHelper.playList(_recent, index),
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
}