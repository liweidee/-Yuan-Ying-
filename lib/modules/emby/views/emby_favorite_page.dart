import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/common/widgets/loading_widget/m3e_loading_indicator.dart';
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/utils/emby_converter.dart';
import '../controllers/emby_favorite_controller.dart';
import '../models/emby_media_item.dart';
import '../services/emby_api_service.dart';

const Widget _loadingWidget = Center(child: M3ELoadingIndicator());

class EmbyFavoritePage extends StatelessWidget {
  const EmbyFavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<EmbyFavoriteController>()) {
      Get.put(EmbyFavoriteController());
    }
    final ctrl = Get.find<EmbyFavoriteController>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Obx(() {
        // 首次加载
        if (ctrl.isLoading.value && ctrl.items.isEmpty) {
          return _loadingWidget;
        }
        // 错误
        if (ctrl.error.isNotEmpty && ctrl.items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  ctrl.error.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: ctrl.refreshData,
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        // 空状态
        if (ctrl.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: ctrl.refreshData,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.7,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.favorite_border,
                            size: 64, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          '暂无收藏',
                          style:
                              TextStyle(color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '在详情页点击 ❤ 图标即可收藏',
                          style: TextStyle(
                            color: theme.colorScheme.outline,
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

        final server = ctrl.serverController.currentServer!;
        final screenWidth = MediaQuery.of(context).size.width;
        final crossAxisCount =
            screenWidth > 800 ? 5 : screenWidth > 600 ? 4 : 3;

        return RefreshIndicator(
          onRefresh: ctrl.refreshData,
          child: GridView.builder(
            controller: ctrl.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.6,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: ctrl.items.length + (ctrl.hasMore.value ? 1 : 0),
            itemBuilder: (context, index) {
              // 加载更多的尾部
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
              final imageUrl = EmbyApiService.primaryImage(
                server.baseUrl,
                item.id,
                maxWidth: 300,
              );
              final videoItem = EmbyConverter.toVideoItem(item, imageUrl);

              // ★ Stack 包裹：卡片本体 + 右上角取消收藏按钮
              return Stack(
                children: [
                  VideoCardV(
                    videoItem: videoItem,
                    onTap: () => Get.toNamed(
                      AppPages.embyDetail,
                      arguments: {'itemId': item.id},
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black.withOpacity(0.55),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () =>
                            _confirmUnfavorite(context, ctrl, item),
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.favorite,
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
      }),
    );
  }

  /// 取消收藏（带确认弹窗）
  Future<void> _confirmUnfavorite(
    BuildContext context,
    EmbyFavoriteController ctrl,
    EmbyMediaItem item,
  ) async {
    final server = ctrl.serverController.currentServer;
    if (server == null || server.userId == null) {
      SmartDialog.showToast('服务器未配置');
      return;
    }
    final token = ctrl.serverController.getToken(server.id);
    if (token == null) {
      SmartDialog.showToast('请先登录');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('将「${item.name}」从收藏中移除？'),
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

    try {
      await ctrl.api.unmarkFavorite(
        userId: server.userId!,
        token: token,
        baseUrl: server.baseUrl,
        itemId: item.id,
      );
      // 本地移除
      ctrl.items.removeWhere((i) => i.id == item.id);
      if (ctrl.totalCount.value > 0) {
        ctrl.totalCount.value = ctrl.totalCount.value - 1;
      }
      SmartDialog.showToast('已取消收藏');
    } catch (e) {
      SmartDialog.showToast('操作失败: $e');
    }
  }
}