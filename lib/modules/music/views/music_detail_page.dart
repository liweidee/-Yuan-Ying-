// lib/modules/music/views/music_detail_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/core/constants/app_constants.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/modules/music/widgets/music_list_tile.dart';
import 'package:yuanying/modules/music/views/music_player_view.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/utils/toast_utils.dart';
import 'package:yuanying/common/widgets/image_viewer/gallery_viewer.dart';
import 'package:yuanying/common/widgets/image_viewer/hero.dart';

const int kGroupSize = 50;

class MusicDetailPage extends StatefulWidget {
  const MusicDetailPage({super.key});

  @override
  State<MusicDetailPage> createState() => _MusicDetailPageState();
}

class _MusicDetailPageState extends State<MusicDetailPage> {
  late String _vodId;
  late String _pwd;
  Map<String, dynamic>? _site;

  bool _loading = true;
  String? _error;
  VideoDetail? _detail;
  String _playSourceName = '';    // 播放源名称（线路名称）
  String _currentSiteName = '';   // 当前爬虫源名称（首页显示的源名）

  late final MusicPlayerController _controller;

  // ===== 列表状态 =====
  bool _desc = false;
  bool _isGrid = false;
  int? _selectedGroup;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map?;
    _vodId = args?['vodId'] ?? '';
    _pwd = args?['pwd'] ?? 'tinydust';
    _site = args?['site'] as Map<String, dynamic>?;

    _controller = Get.find<MusicPlayerController>();
    _controller.onPlayCompleted = _onPlayCompleted;
    _loadDetail();
  }

  // ===== 加载详情（保持状态逻辑） =====
  Future<void> _loadDetail() async {
    try {
      // 获取当前站点名称（爬虫源）
      final sourceManager = Get.find<SourceManager>();
      final currentSite = sourceManager.currentSite.value;
      _currentSiteName = currentSite?['name']?.toString() ?? '未知源';

      if (_controller.currentVodId == _vodId && _controller.playlist.isNotEmpty) {
        final api = _site != null
            ? sourceManager.createIndependentService(_site!)
            : sourceManager.currentApiService;

        final detail = await api.getDetail(vodId: _vodId, pwd: _pwd);
        if (detail != null && detail.playSources.isNotEmpty) {
          setState(() {
            _detail = detail;
            _playSourceName = detail.playSources.first.name;
            _loading = false;
          });
          _controller.updateSongInfo(
            cover: detail.vodPic,
            author: detail.vodActor ?? '',
            album: detail.vodName,
          );
          _loadFavoriteStatus();
        } else {
          setState(() {
            _error = '未获取到歌曲列表';
            _loading = false;
          });
        }
        return;
      }

      final api = _site != null
          ? sourceManager.createIndependentService(_site!)
          : sourceManager.currentApiService;

      final detail = await api.getDetail(vodId: _vodId, pwd: _pwd);

      if (detail != null && detail.playSources.isNotEmpty) {
        setState(() {
          _detail = detail;
          _playSourceName = detail.playSources.first.name;
          _loading = false;
        });

        final episodes = detail.playSources.first.episodes;
        _controller.setPlaylist(episodes, initialIndex: 0, vodId: _vodId);
        _controller.updateSongInfo(
          cover: detail.vodPic,
          author: detail.vodActor ?? '',
          album: detail.vodName,
        );
        _loadFavoriteStatus();
        _playSong(_controller.currentIndex.value);
      } else {
        setState(() {
          _error = '未获取到歌曲列表';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  void _onPlayCompleted() {
    final index = _controller.currentIndex.value;
    if (index < _controller.playlist.length) {
      _playSong(index);
    }
  }

  Future<void> _playSong(int index) async {
    final episodes = _controller.playlist;
    if (_detail == null || episodes.isEmpty || index >= episodes.length) return;

    final api = _site != null
        ? Get.find<SourceManager>().createIndependentService(_site!)
        : Get.find<SourceManager>().currentApiService;

    try {
      final playUrl = await api.getPlayUrl(
        playParams: episodes[index].url,
        flag: _playSourceName,
        pwd: _pwd,
      );

      if (playUrl == null) {
        ToastUtils.show('获取播放地址失败');
        return;
      }
      await _controller.playWithUrl(playUrl, index: index);
    } catch (e) {
      ToastUtils.show('播放失败: $e');
    }
  }

  // ===== 获取可见索引（倒序 + 分组） =====
  List<int> _getVisibleIndices(int total) {
    List<int> indices = List.generate(total, (i) => i);
    if (_desc) indices = indices.reversed.toList();
    if (_selectedGroup != null) {
      final start = _selectedGroup! * kGroupSize;
      final end = (start + kGroupSize).clamp(0, total);
      indices = indices.where((i) => i >= start && i < end).toList();
    }
    return indices;
  }

  /// 从本地存储加载当前歌曲的收藏状态
  void _loadFavoriteStatus() {
    // 触发 UI 刷新（通过版本号）
    _controller.favoriteVersion.value++;
  }

  /// 切换收藏状态
  void _toggleFavorite() {
    if (_detail == null || _vodId.isEmpty) {
      ToastUtils.show('无法获取歌曲信息');
      return;
    }
    final detail = _detail!;
    final sourceManager = Get.find<SourceManager>();
    final site = _site ?? sourceManager.currentSite.value;
    final sourceName = site?['name']?.toString() ?? (detail.typeName ?? '音乐');
    final apiUrl = site?['api']?.toString() ?? '';
    final siteKey = site?['key']?.toString() ?? '';
    final configKey = sourceManager.currentConfigKey.value;
    const detailType = DetailType.audio;

    // 先读取当前状态
    final favorites = GStorage.getFavorites();
    final isFav = favorites.any((item) => item['vod_id'] == _vodId);

    if (isFav) {
      GStorage.removeFavorite(_vodId);
      ToastUtils.show('已取消收藏');
    } else {
      final item = {
        'vod_id': _vodId,
        'vod_name': detail.vodName,
        'vod_pic': detail.vodPic,
        'vod_remarks': detail.vodRemarks ?? '',
        'vod_tag': detail.vodTag ?? '',
        'type_name': sourceName,
        'api_url': apiUrl,
        'site_key': siteKey,
        'config_key': configKey,
        'detail_type': detailType,
      };
      GStorage.addFavorite(item);
      ToastUtils.show('已收藏');
    }
    // 通知所有界面刷新
    _controller.notifyFavoriteChanged();
  }

  // ===== 简介详情底部弹窗（完全复用小说详情页） =====
  void _showIntroDetailPanel(BuildContext context, String title, String content) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        content,
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?.vodName ?? '音乐详情'),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        actions: [
          Obx(() {
            // 依赖版本号触发重建
            final _ = _controller.favoriteVersion.value;
            final favorites = GStorage.getFavorites();
            final isFav = favorites.any((item) => item['vod_id'] == _vodId);
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(colorScheme)
              : Stack(
                  children: [
                    Column(
                      children: [
                        _buildHeader(colorScheme),
                        _buildListHeader(colorScheme),
                        Expanded(
                          child: _buildPlaylist(colorScheme),
                        ),
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

  // ===== 头部信息（封面点击放大 + 主播 + 描述 + 来源） =====
  Widget _buildHeader(ColorScheme colorScheme) {
    if (_detail == null) return const SizedBox.shrink();

    final detail = _detail!;
    final hasContent = detail.vodContent != null && detail.vodContent!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              if (detail.vodPic.isNotEmpty) {
                showImageViewer(context, detail.vodPic, tag: detail.vodPic);
              }
            },
            child: fromHero(
              tag: detail.vodPic,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: detail.vodPic.isNotEmpty
                    ? Image.network(
                        detail.vodPic,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80,
                          height: 80,
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.music_note,
                            color: colorScheme.outline,
                            size: 40,
                          ),
                        ),
                      )
                    : Container(
                        width: 80,
                        height: 80,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.music_note,
                          color: colorScheme.outline,
                          size: 40,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.vodName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (detail.vodActor != null && detail.vodActor!.isNotEmpty)
                  Text(
                    '主播/歌手：${detail.vodActor}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.outline,
                    ),
                  ),
                const SizedBox(height: 4),
                if (hasContent)
                  GestureDetector(
                    onTap: () => _showIntroDetailPanel(context, '简介', detail.vodContent!),
                    child: Text(
                      detail.vodContent!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.outline,
                        height: 1.7,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '来源：$_currentSiteName',
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
  }

  // ===== 播放列表标题栏 =====
  Widget _buildListHeader(ColorScheme colorScheme) {
    final total = _controller.playlist.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                icon: _desc ? Icons.vertical_align_top : Icons.vertical_align_bottom,
                tooltip: _desc ? '正序' : '倒序',
                isActive: _desc,
                onTap: () => setState(() => _desc = !_desc),
              ),
              _CatalogIconButton(
                icon: _isGrid ? Icons.grid_view_rounded : Icons.view_list_rounded,
                tooltip: _isGrid ? '网格' : '列表',
                isActive: _isGrid,
                onTap: () {
                  setState(() => _isGrid = !_isGrid);
                  ToastUtils.show(_isGrid ? '网格视图' : '列表视图');
                },
              ),
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

  // ===== 播放列表构建（支持列表/网格切换，网格一行4列） =====
  Widget _buildPlaylist(ColorScheme colorScheme) {
    return Obx(() {
      final episodes = _controller.playlist.value;
      final currentIdx = _controller.currentIndex.value;
      final isPlayingNow = _controller.playing.value;

      final total = episodes.length;
      final indices = _getVisibleIndices(total);

      if (_isGrid) {
        // ===== 网格模式（4列，与小说一致） =====
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.2,
          ),
          itemCount: indices.length,
          itemBuilder: (context, i) {
            final originalIndex = indices[i];
            final visibleIndex = i;
            final episode = episodes[originalIndex];
            final isCurrent = currentIdx == originalIndex;
            final isPlaying = isCurrent && isPlayingNow;

            return InkWell(
              onTap: () => _playSong(originalIndex),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: isCurrent
                      ? Border.all(color: colorScheme.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${visibleIndex + 1}. ${episode.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          },
        );
      } else {
        // ===== 列表模式（原有样式） =====
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: indices.length,
          itemBuilder: (context, i) {
            final originalIndex = indices[i];
            final visibleIndex = i;
            final episode = episodes[originalIndex];
            final isCurrent = currentIdx == originalIndex;
            final isPlaying = isCurrent && isPlayingNow;

            return MusicListTile(
              episode: episode,
              index: visibleIndex,
              isPlaying: isPlaying,
              isCurrent: isCurrent,
              onTap: () => _playSong(originalIndex),
              onMore: () => _showMoreMenu(context, originalIndex),
            );
          },
        );
      }
    });
  }

  // ===== 错误页面 =====
  Widget _buildError(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: colorScheme.error),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: colorScheme.outline),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _loadDetail();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  // ===== 更多菜单 =====
  void _showMoreMenu(BuildContext context, int index) {
    final episodes = _controller.playlist;
    if (index >= episodes.length) return;
    final episode = episodes[index];
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: Style.bottomSheetRadius),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  episode.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('播放'),
                onTap: () {
                  Navigator.pop(ctx);
                  _playSong(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('添加到待播放列表'),
                onTap: () {
                  Navigator.pop(ctx);
                  ToastUtils.show('已添加到待播放列表');
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: const Text('收藏'),
                onTap: () {
                  Navigator.pop(ctx);
                  ToastUtils.show('已收藏');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ===== 辅助组件：目录图标按钮（从小说详情页复用） =====
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
            color: isActive ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

// ===== 辅助组件：分组按钮（从小说详情页复用） =====
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
    final n = (total / kGroupSize).ceil();
    for (int g = 0; g < n; g++) {
      final start = g * kGroupSize + 1;
      final end = ((g + 1) * kGroupSize).clamp(0, total);
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
          final RenderBox button = context.findRenderObject() as RenderBox;
          final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
          final Rect rect = Rect.fromPoints(
            button.localToGlobal(Offset.zero, ancestor: overlay),
            button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
          );
          final result = await showMenu<int?>(
            context: context,
            position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
            items: _buildMenuItems(context),
            color: colorScheme.surface,
          );
          onChanged(result);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selectedGroup != null ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.more_vert,
            size: 20,
            color: selectedGroup != null ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}