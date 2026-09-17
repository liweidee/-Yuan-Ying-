import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/common/widgets/loading_widget/m3e_loading_indicator.dart';
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/utils/emby_converter.dart';
import '../controllers/emby_history_controller.dart';
import '../models/emby_media_item.dart';
import '../services/emby_api_service.dart';

const Widget _loadingWidget = Center(child: M3ELoadingIndicator());

class EmbyHistoryPage extends StatelessWidget {
  const EmbyHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<EmbyHistoryController>()) {
      Get.put(EmbyHistoryController());
    }
    final ctrl = Get.find<EmbyHistoryController>();
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
                        Icon(Icons.history,
                            size: 64, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          '暂无播放记录',
                          style:
                              TextStyle(color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '播放过的视频会出现在这里',
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

              // 卡片本体 + 右上角删除按钮
              return Stack(
                children: [
                  VideoCardV(
                    videoItem: videoItem,
                    onTap: () => _openDetail(item),
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
                            _confirmRemoveOne(context, ctrl, item),
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.close,
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

  /// 删除单条历史（带确认弹窗）
  Future<void> _confirmRemoveOne(
    BuildContext context,
    EmbyHistoryController ctrl,
    EmbyMediaItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('将「${item.name}」从播放历史中删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ctrl.removeOne(item);
      SmartDialog.showToast('已删除');
    } catch (e) {
      SmartDialog.showToast('删除失败: $e');
    }
  }

  /// 从历史打开详情：
  /// - Episode → 打开 Series 详情 + 定位到该集
  /// - Audio   → 打开 Album 详情 + 定位到该曲
  /// - 其他    → 直接打开自身详情
  void _openDetail(EmbyMediaItem item) {
    // Episode：优先 seriesId 追溯到 Series
    if (item.isEpisode &&
        item.seriesId != null &&
        item.seriesId!.isNotEmpty) {
      Get.toNamed(
        AppPages.embyDetail,
        arguments: {
          'itemId': item.seriesId!,
          'initialEpisodeId': item.id,
        },
      );
      return;
    }

    // Audio：优先 albumId 追溯到 Album
    if (item.isAudio &&
        item.albumId != null &&
        item.albumId!.isNotEmpty) {
      Get.toNamed(
        AppPages.embyDetail,
        arguments: {
          'itemId': item.albumId!,
          'initialEpisodeId': item.id,
        },
      );
      return;
    }

    // 其他：直接打开
    Get.toNamed(
      AppPages.embyDetail,
      arguments: {'itemId': item.id},
    );
  }
}