import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/common/widgets/loading_widget/m3e_loading_indicator.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import '../controllers/fnos_favorite_controller.dart';
import '../controllers/fnos_server_controller.dart';
import '../models/fnos_media_item.dart';
import '../services/fnos_api_service.dart';
import '../widgets/fnos_media_card.dart';

const Widget _loadingWidget = Center(child: M3ELoadingIndicator());

class FnosFavoritePage extends StatelessWidget {
  const FnosFavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<FnosFavoriteController>()) {
      Get.put(FnosFavoriteController());
    }
    final ctrl = Get.find<FnosFavoriteController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // ===== Tab 行 =====
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withOpacity(0.3),
                width: 0.5,
              ),
            ),
          ),
          child: Obx(() {
            final current = ctrl.currentTabIndex.value;
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: FnosFavoriteController.tabs.length,
              itemBuilder: (_, i) {
                final isSelected = i == current;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: InkWell(
                    onTap: () => ctrl.switchTab(i),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary.withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        FnosFavoriteController.tabs[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ),

        // ===== 内容区 =====
        Expanded(
          child: Obx(() {
            // 依赖 version 触发刷新
            // ignore: unused_local_variable
            final _ = ctrl.version;
            final idx = ctrl.currentTabIndex.value;
            final items = ctrl.itemsOf(idx);
            final loading = ctrl.loadingOf(idx);
            final error = ctrl.errorOf(idx);
            final hasMore = ctrl.hasMoreOf(idx);

            if (loading && items.isEmpty) {
              return _loadingWidget;
            }
            if (error.isNotEmpty && items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: colorScheme.error),
                    const SizedBox(height: 12),
                    Text(error,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.error)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ctrl.loadTab(idx, refresh: true),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            if (items.isEmpty) {
              return RefreshIndicator(
                onRefresh: ctrl.refreshCurrent,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height:
                          MediaQuery.sizeOf(context).height * 0.6,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.favorite_border_rounded,
                              size: 64,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '暂无收藏',
                              style: TextStyle(
                                  color: colorScheme.outline),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '在详情页点心形图标可收藏',
                              style: TextStyle(
                                color: colorScheme.outline,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: ctrl.refreshCurrent,
              child: _FnosFavoriteGrid(
                ctrl: ctrl,
                items: items,
                hasMore: hasMore,
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _FnosFavoriteGrid extends StatelessWidget {
  final FnosFavoriteController ctrl;
  final List<FnosPlayListItem> items;
  final bool hasMore;

  const _FnosFavoriteGrid({
    required this.ctrl,
    required this.items,
    required this.hasMore,
  });

  @override
  Widget build(BuildContext context) {
    final serverCtrl = Get.find<FnosServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return _loadingWidget;

    final token = serverCtrl.getToken(server.id);
    final headers = FnosApiService().imageHeaders(token: token);

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount =
        screenWidth > 1200 ? 6 : screenWidth > 800 ? 5 : screenWidth > 600 ? 4 : 3;

    return NotificationListener<ScrollNotification>(
      onNotification: (info) {
        if (info.metrics.pixels >= info.metrics.maxScrollExtent - 200) {
          if (hasMore) ctrl.loadMore();
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.55,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: items.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final item = items[index];
          final imageUrl = FnosApiService.imageUrl(
            server.baseUrl,
            item.poster ?? '',
            width: 300,
          );

          return Stack(
            children: [
              FnosMediaCard(
                item: item,
                imageUrl: imageUrl,
                headers: headers,
                onTap: () => _openDetail(item),
              ),
              // 右上角取消收藏按钮
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: Colors.black.withOpacity(0.55),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _confirmRemove(item),
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.favorite_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openDetail(FnosPlayListItem item) {
    // Episode/Season 需要跳到其父级详情
    final guid = _resolveDetailGuid(item);
    Get.toNamed(
      AppPages.fnosDetail,
      arguments: {
        'itemGuid': guid,
        'initialEpisodeGuid': item.guid,
        'poster': item.poster,
        'title': item.title,
        'tvTitle': item.tvTitle,
        'type': item.type,
        'overview': item.overview,
      },
    );
  }

  String _resolveDetailGuid(FnosPlayListItem item) {
    if ((item.type == 'Episode' || item.type == 'Season') &&
        item.parentGuid != null &&
        item.parentGuid!.isNotEmpty) {
      return item.parentGuid!;
    }
    return item.guid;
  }

  Future<void> _confirmRemove(FnosPlayListItem item) async {
    final confirmed = await showDialog<bool>(
      context: Get.context!,
      builder: (ctx) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('将「${item.title ?? ''}」从收藏中移除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await ctrl.removeFavorite(item);
    if (ok) {
      SmartDialog.showToast('已取消收藏');
    } else {
      SmartDialog.showToast('操作失败');
    }
  }
}