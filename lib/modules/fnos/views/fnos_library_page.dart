import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/loading_widget/m3e_loading_indicator.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import '../controllers/fnos_library_controller.dart';
import '../controllers/fnos_server_controller.dart';
import '../models/fnos_media_item.dart';
import '../services/fnos_api_service.dart';
import '../widgets/fnos_media_card.dart';

const Widget _loadingWidget = Center(child: M3ELoadingIndicator());

class FnosLibraryPage extends StatelessWidget {
  const FnosLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    final libraryId = args['libraryId'] as String?;
    final libraryName = args['libraryName'] as String? ?? '媒体库';

    // ============================================================
    // 无 libraryId → Tab 内嵌模式
    // 外层 FnosMainShell 已有 AppBar，这里只返回内容，避免双头部
    // ============================================================
    if (libraryId == null || libraryId.isEmpty) {
      return const _FnosLibraryListContent();
    }

    // ============================================================
    // 有 libraryId → 独立路由模式（从首页"查看全部"或库列表点击进入）
    // 需要 Scaffold + AppBar
    // ============================================================
    final tag = 'fnos_lib_$libraryId';
    if (!Get.isRegistered<FnosLibraryController>(tag: tag)) {
      Get.put(
        FnosLibraryController(
          libraryId: libraryId,
          libraryName: libraryName,
        ),
        tag: tag,
      );
    }
    final ctrl = Get.find<FnosLibraryController>(tag: tag);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        title: Obx(() => Text(
              ctrl.isFolderMode.value
                  ? ctrl.currentFolderName.value
                  : libraryName,
            )),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (ctrl.isFolderMode.value) {
              ctrl.exitFolder();
            } else {
              Get.back();
            }
          },
        ),
        // ===== 排序筛选 =====
        actions: [
          Obx(() {
            final currentKey =
                '${ctrl.sortColumn.value}:${ctrl.sortType.value}';
            final isDefault = currentKey == 'create_time:DESC';
            return PopupMenuButton<String>(
              icon: Icon(
                Icons.sort_rounded,
                color: isDefault
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.primary,
              ),
              tooltip: '排序',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: colorScheme.surface,
              elevation: 8,
              onSelected: (value) {
                final parts = value.split(':');
                if (parts.length == 2) {
                  ctrl.setSort(parts[0], parts[1]);
                }
              },
              itemBuilder: (context) => [
                _buildSortItem(
                  value: 'create_time:DESC',
                  label: '最新添加',
                  icon: Icons.schedule_rounded,
                  currentKey: currentKey,
                  colorScheme: colorScheme,
                ),
                _buildSortItem(
                  value: 'create_time:ASC',
                  label: '最早添加',
                  icon: Icons.history_rounded,
                  currentKey: currentKey,
                  colorScheme: colorScheme,
                ),
                const PopupMenuDivider(),
                _buildSortItem(
                  value: 'release_date:DESC',
                  label: '年份最新',
                  icon: Icons.trending_up_rounded,
                  currentKey: currentKey,
                  colorScheme: colorScheme,
                ),
                _buildSortItem(
                  value: 'release_date:ASC',
                  label: '年份最旧',
                  icon: Icons.trending_down_rounded,
                  currentKey: currentKey,
                  colorScheme: colorScheme,
                ),
                const PopupMenuDivider(),
                _buildSortItem(
                  value: 'vote_average:DESC',
                  label: '评分最高',
                  icon: Icons.star_rounded,
                  currentKey: currentKey,
                  colorScheme: colorScheme,
                ),
                _buildSortItem(
                  value: 'vote_average:ASC',
                  label: '评分最低',
                  icon: Icons.star_outline_rounded,
                  currentKey: currentKey,
                  colorScheme: colorScheme,
                ),
                const PopupMenuDivider(),
                _buildSortItem(
                  value: 'sort_title:ASC',
                  label: '标题 A-Z',
                  icon: Icons.sort_by_alpha_rounded,
                  currentKey: currentKey,
                  colorScheme: colorScheme,
                ),
                _buildSortItem(
                  value: 'sort_title:DESC',
                  label: '标题 Z-A',
                  icon: Icons.sort_by_alpha_rounded,
                  currentKey: currentKey,
                  colorScheme: colorScheme,
                ),
              ],
            );
          }),
          const SizedBox(width: 4),
        ],
      ),
      body: _FnosLibraryGrid(ctrl: ctrl),
    );
  }

  PopupMenuItem<String> _buildSortItem({
    required String value,
    required String label,
    required IconData icon,
    required String currentKey,
    required ColorScheme colorScheme,
  }) {
    final selected = value == currentKey;
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: selected ? colorScheme.primary : colorScheme.onSurface,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (selected)
            Icon(
              Icons.check_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
        ],
      ),
    );
  }
}

// ============================================================
// 媒体库条目网格（独立路由页 + Tab 内页共用）
// ============================================================
class _FnosLibraryGrid extends StatelessWidget {
  final FnosLibraryController ctrl;

  const _FnosLibraryGrid({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      if (ctrl.isLoading.value && ctrl.items.isEmpty) {
        return _loadingWidget;
      }
      if (ctrl.error.isNotEmpty && ctrl.items.isEmpty) {
        return Center(
          child: Text(ctrl.error.value,
              style: TextStyle(color: colorScheme.error)),
        );
      }
      if (ctrl.items.isEmpty) {
        return Center(
          child: Text('暂无内容',
              style: TextStyle(color: colorScheme.outline)),
        );
      }

      final serverCtrl = Get.find<FnosServerController>();
      final server = serverCtrl.currentServer!;
      final token = serverCtrl.getToken(server.id);
      final headers = FnosApiService().imageHeaders(token: token);

      final screenWidth = MediaQuery.of(context).size.width;
      final crossAxisCount =
          screenWidth > 800 ? 5 : screenWidth > 600 ? 4 : 3;

      return GridView.builder(
        controller: ctrl.scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.55,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: ctrl.items.length + (ctrl.hasMore.value ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == ctrl.items.length) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final item = ctrl.items[index];
          final imageUrl = FnosApiService.imageUrl(
            server.baseUrl,
            item.poster ?? '',
            width: 300,
          );
          return FnosMediaCard(
            item: item,
            imageUrl: imageUrl,
            headers: headers,
            onTap: () => _onTapItem(ctrl, item),
          );
        },
      );
    });
  }

  void _onTapItem(FnosLibraryController ctrl, FnosPlayListItem item) {
    if (item.isFolder) {
      ctrl.enterFolder(item.guid, item.title ?? '');
      return;
    }
    Get.toNamed(
      AppPages.fnosDetail,
      arguments: {
        'itemGuid': item.guid,
        'poster': item.poster,
        'title': item.title,
        'tvTitle': item.tvTitle,
        'type': item.type,
        'overview': item.overview,
      },
    );
  }
}

// ============================================================
// Tab 内嵌：媒体库列表内容（无 Scaffold / 无 AppBar）
// 外层由 FnosMainShell 提供 AppBar
// ============================================================
class _FnosLibraryListContent extends StatelessWidget {
  const _FnosLibraryListContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final serverCtrl = Get.find<FnosServerController>();
    final server = serverCtrl.currentServer;

    if (server == null) {
      return const Center(child: Text('未选择服务器'));
    }

    return FutureBuilder(
      future: FnosApiService().getMediaDbList(
        baseUrl: server.baseUrl,
        token: serverCtrl.getToken(server.id) ?? '',
      ),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingWidget;
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Text('暂无媒体库',
                style: TextStyle(color: colorScheme.outline)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(Style.safeSpace),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final lib = list[i];
            return Card(
              color: colorScheme.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: Style.mdRadius),
              child: ListTile(
                leading: Icon(
                  lib.category == 'TV'
                      ? Icons.tv_rounded
                      : Icons.movie_rounded,
                  color: colorScheme.primary,
                ),
                title: Text(lib.title),
                subtitle: Text(
                  lib.category ?? '影视库',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.outline),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Get.toNamed(
                  AppPages.fnosLibrary,
                  arguments: {
                    'libraryId': lib.guid,
                    'libraryName': lib.title,
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}