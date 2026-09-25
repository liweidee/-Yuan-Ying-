import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/modules/lx_music/models/lx_music_model.dart';
import 'package:yuanying/modules/lx_music/services/lx_songlist_service.dart';
import 'package:yuanying/modules/lx_music/storage/lx_storage.dart';
import 'package:yuanying/modules/lx_music/utils/lx_logger.dart';
import 'package:yuanying/modules/lx_music/utils/lx_player_helper.dart';

/// 洛雪歌单公共工具
class LxPlaylistHelper {
  LxPlaylistHelper._();

  // ==================== 添加到歌单弹窗 ====================

  static void showAddToPlaylistSheet(
    BuildContext context,
    LxMusic music, {
    VoidCallback? onAdded,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddToPlaylistSheet(
        music: music,
        onAdded: onAdded,
      ),
    );
  }

  // ==================== 导入歌单 ====================

  static Future<String> importPlaylistFromLink(String input) async {
    final text = input.trim();
    if (text.isEmpty) throw Exception('请输入分享链接');

    final parsed = LxSonglistService.parseShareLink(text);
    if (parsed == null) throw Exception('无法识别链接，请粘贴完整的歌单分享链接');

    String source = parsed.source;
    String id = parsed.id;

    if (source == 'redirect') {
      final resolvedId =
          await LxSonglistService.resolveRedirectId(parsed.id);
      if (resolvedId == null) throw Exception('链接解析失败，请检查链接是否完整');
      id = resolvedId;
      source =
          text.contains('163.com') || text.contains('163cn.tv') ? 'wy' : 'tx';
    }

    final service = LxSonglistService.instance;
    final detail = source == 'wy'
        ? await service.getWYPlaylistDetail(id)
        : await service.getQQPlaylistDetail(id);

    if (detail == null || detail.songs.isEmpty) {
      throw Exception('歌单获取失败（可能不是公开歌单）');
    }

    final playlistId = 'import_${source}_$id';
    final existing = await LxStorage.instance.getPlaylists();
    existing.removeWhere((p) => p['id'] == playlistId);

    final now = DateTime.now().toIso8601String();
    existing.insert(0, {
      'id': playlistId,
      'name': detail.name.isNotEmpty ? detail.name : '导入的歌单',
      'createTime': now,
      'updateTime': now,
      'coverUrl': detail.imgUrl.isNotEmpty ? detail.imgUrl : null,
      'songs': detail.songs.map((m) => m.toJson()).toList(),
    });
    await LxStorage.instance.savePlaylists(existing);

    LxLogger.info('导入歌单成功: ${detail.name} (${detail.songs.length} 首)');
    return '${detail.name}（${detail.songs.length} 首）';
  }

  static Future<String?> showImportDialog(BuildContext context) async {
    final controller = TextEditingController();
    bool importing = false;
    String? message;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            backgroundColor: colorScheme.surfaceContainerLow,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              '导入歌单',
              style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '粘贴 QQ 音乐 / 网易云 歌单分享链接',
                  style: TextStyle(color: colorScheme.outline, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 1,
                  style:
                      TextStyle(color: colorScheme.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://c6.y.qq.com/... 或 music.163.com/playlist?id=...',
                    hintStyle:
                        TextStyle(color: colorScheme.outline, fontSize: 11),
                    filled: true,
                    fillColor: colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                if (importing) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colorScheme.primary),
                      ),
                      const SizedBox(width: 10),
                      Text('正在导入...',
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13)),
                    ],
                  ),
                ],
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    message!,
                    style: TextStyle(
                      color: message!.contains('成功')
                          ? Colors.green
                          : colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed:
                    importing ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: importing
                    ? null
                    : () async {
                        final input = controller.text.trim();
                        if (input.isEmpty) return;
                        setDialogState(() {
                          importing = true;
                          message = null;
                        });
                        try {
                          final name =
                              await importPlaylistFromLink(input);
                          setDialogState(() {
                            importing = false;
                            message = '导入成功：$name';
                          });
                          await Future.delayed(
                              const Duration(milliseconds: 800));
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, name);
                          }
                        } catch (e) {
                          setDialogState(() {
                            importing = false;
                            message = '导入失败: $e';
                          });
                        }
                      },
                child: Text('导入',
                    style: TextStyle(color: colorScheme.primary)),
              ),
            ],
          );
        },
      ),
    ).then((v) {
      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          controller.dispose();
        } catch (_) {}
      });
      return v;
    });
  }

  // ==================== 新建歌单弹窗 ====================

  static Future<String?> showCreateDialog(BuildContext context) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            '新建歌单',
            style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: '输入歌单名称',
              hintStyle: TextStyle(color: colorScheme.outline),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(dialogContext, name);
                }
              },
              child:
                  Text('创建', style: TextStyle(color: colorScheme.primary)),
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

  // ==================== 更多菜单（通用） ====================

  static void showMusicMoreMenu(
    BuildContext context,
    LxMusic music, {
    List<LxMusic>? playlist,
    int? index,
    bool showDownload = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: music.imgUrl != null && music.imgUrl!.isNotEmpty
                        ? Image.network(
                            music.imgUrl!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _smallCoverPlaceholder(colorScheme),
                          )
                        : _smallCoverPlaceholder(colorScheme),
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                ],
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            ListTile(
              leading: Icon(Icons.play_arrow_rounded,
                  color: colorScheme.primary, size: 22),
              title: const Text('播放'),
              onTap: () {
                Navigator.pop(sheetContext);
                if (playlist != null && index != null) {
                  LxPlayerHelper.playList(playlist, index);
                } else {
                  LxPlayerHelper.playList([music], 0);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_play_rounded,
                  color: colorScheme.primary, size: 22),
              title: const Text('下一首播放'),
              onTap: () {
                Navigator.pop(sheetContext);
                LxPlayerHelper.playList([music], 0);
                SmartDialog.showToast('已添加到下一首播放');
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_add_rounded,
                  color: colorScheme.primary, size: 22),
              title: const Text('添加到歌单'),
              onTap: () {
                Navigator.pop(sheetContext);
                showAddToPlaylistSheet(context, music);
              },
            ),
            ListTile(
              leading: Icon(Icons.favorite_border_rounded,
                  color: colorScheme.error, size: 22),
              title: const Text('我喜欢'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _addToFavorites(music);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Future<void> _addToFavorites(LxMusic music) async {
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
}

Widget _smallCoverPlaceholder(ColorScheme colorScheme) {
  return Container(
    width: 40,
    height: 40,
    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
    alignment: Alignment.center,
    child:
        Icon(Icons.music_note_rounded, color: colorScheme.primary, size: 20),
  );
}

// ==================== 添加到歌单底部弹窗 ====================

class _AddToPlaylistSheet extends StatefulWidget {
  final LxMusic music;
  final VoidCallback? onAdded;

  const _AddToPlaylistSheet({required this.music, this.onAdded});

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  List<Map<String, dynamic>> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _playlists = await LxStorage.instance.getPlaylists();
    } catch (_) {
      _playlists = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addTo(int index) async {
    final p = _playlists[index];
    try {
      await LxStorage.instance
          .addSongToPlaylist(p['id'].toString(), widget.music.toJson());
      SmartDialog.showToast('已添加到「${p['name']}」');
      widget.onAdded?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      SmartDialog.showToast('添加失败: $e');
    }
  }

  Future<void> _createAndAdd() async {
    final name = await LxPlaylistHelper.showCreateDialog(context);
    if (name == null || name.isEmpty) return;

    try {
      final newPlaylist = await LxStorage.instance.createPlaylist(name);
      await LxStorage.instance.addSongToPlaylist(
          newPlaylist['id'].toString(), widget.music.toJson());
      SmartDialog.showToast('已创建「$name」并添加');
      widget.onAdded?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      SmartDialog.showToast('创建失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  '添加到歌单',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _createAndAdd,
                  icon: Icon(Icons.add_rounded,
                      size: 18, color: colorScheme.primary),
                  label: Text(
                    '新建',
                    style:
                        TextStyle(color: colorScheme.primary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _playlists.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.queue_music_rounded,
                                size: 48, color: colorScheme.outline),
                            const SizedBox(height: 12),
                            Text('还没有歌单',
                                style: TextStyle(color: colorScheme.outline)),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _createAndAdd,
                              child: const Text('创建第一个歌单'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _playlists.length,
                        itemBuilder: (context, index) {
                          final p = _playlists[index];
                          final songs = (p['songs'] as List?)?.length ?? 0;
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.queue_music_rounded,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              p['name']?.toString() ?? '未命名',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '$songs 首',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () => _addTo(index),
                          );
                        },
                      ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}