import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../controllers/alist_file_list_controller.dart';
import '../controllers/alist_server_controller.dart';
import '../models/alist_favorite.dart';
import '../services/alist_file_utils.dart';
import '../services/alist_open_helper.dart';

class AlistFavoritePage extends StatefulWidget {
  const AlistFavoritePage({super.key});

  @override
  State<AlistFavoritePage> createState() => _AlistFavoritePageState();
}

class _AlistFavoritePageState extends State<AlistFavoritePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<AlistFavorite> _loadFavorites() {
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return [];

    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.favorites,
        ) ??
        [];
    return raw
        .map((e) => AlistFavorite.fromJson(Map<String, dynamic>.from(e)))
        .where((f) => f.serverId == server.id)
        .toList();
  }

  Future<void> _removeFavorite(AlistFavorite fav) async {
    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.favorites,
        ) ??
        [];
    final list = raw
        .map((e) => AlistFavorite.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    list.removeWhere((e) => e.id == fav.id);
    await StorageManager.setSetting(
      AlistStorageKeys.favorites,
      list.map((e) => e.toJson()).toList(),
    );
    alistFavoritesRefreshTick.value++;
  }

  bool _isImageName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic');
  }

  /// 单行卡片（与最近浏览页一致）
  Widget _buildRow(BuildContext context, AlistFavorite f) {
    final cs = Theme.of(context).colorScheme;
    final icon = AlistFileUtils.getFileIcon(f.isDir, f.name);
    final thumbnail = AlistFileUtils.getCompleteThumbnail(f.thumb);
    // 只有图片且 thumb 有效时才显示缩略图，其他都显示图标
    final showThumb = !f.isDir &&
        thumbnail != null &&
        thumbnail.isNotEmpty &&
        _isImageName(f.name);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          child: InkWell(
            onTap: () {
              AlistOpenHelper.openItem(
                context: context,
                name: f.name,
                path: f.path,
                sign: f.sign,
                thumb: f.thumb,
                isDir: f.isDir,
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  // ---- 缩略图 / 主题色图标 ----
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: showThumb
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              thumbnail,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                icon,
                                color: cs.primary,
                                size: 24,
                              ),
                            ),
                          )
                        : Icon(icon, color: cs.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  // ---- 名称 + 路径 ----
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          f.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ---- 取消收藏（主题色心形） ----
                  IconButton(
                    icon: Icon(
                      Icons.favorite,
                      color: cs.primary,
                      size: 20,
                    ),
                    tooltip: '取消收藏',
                    onPressed: () => _removeFavorite(f),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) {
      return const Scaffold(
        body: Center(child: Text('未选择服务器')),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('收藏'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      body: Obx(() {
        alistFavoritesRefreshTick.value;
        final favorites = _loadFavorites();

        if (favorites.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.star_outline_rounded,
                  size: 72,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无收藏',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '长按文件选择「收藏」即可添加',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          itemCount: favorites.length,
          itemBuilder: (ctx, i) => _buildRow(ctx, favorites[i]),
        );
      }),
    );
  }
}