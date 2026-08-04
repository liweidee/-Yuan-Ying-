import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/history/controllers/history_controller.dart';
import 'package:yuanying/common/widgets/media_card.dart';
import 'package:yuanying/t4/models/video_item.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final HistoryController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(HistoryController());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: colorScheme.onSurface, size: 20),
          onPressed: () => Get.back(),
          splashRadius: 20,
        ),
        title: Text('播放历史', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          if (controller.videoList.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear_all, color: colorScheme.onSurface, size: 22),
              onPressed: () => _showClearConfirmDialog(context),
              splashRadius: 20,
            ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (controller.videoList.isEmpty) {
          return _buildEmptyState(context);
        }
        return _buildContent(context, screenWidth);
      }),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: colorScheme.outline.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text('暂无数据', style: textTheme.bodyMedium?.copyWith(color: colorScheme.outline.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, double screenWidth) {
    final maxCrossAxisExtent = screenWidth < 600 ? 130.0 : 200.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxCrossAxisExtent,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
          childAspectRatio: 0.6,
        ),
        itemCount: controller.videoList.length,
        itemBuilder: (context, index) {
          final item = controller.videoList[index];
          final progress = controller.getProgress(item.vodId) ?? '';
          final watchTime = controller.getWatchTime(item.vodId);
          final timeAgo = watchTime != null ? controller.formatTimeAgo(watchTime) : '';
          return MediaCard(
            videoItem: item,
            onTap: () => controller.navigateToDetail(item),
            showSourceLabel: item.typeName != null && item.typeName!.isNotEmpty,
            sourceLabel: item.typeName ?? '',
            showProgress: progress.isNotEmpty,
            progressText: progress,
            showDeleteButton: true,
            onDelete: () => _showDeleteConfirmDialog(context, item),
            bottomSubText: progress.isNotEmpty ? progress.split(' / ').first : '',
            bottomSubColor: Theme.of(context).colorScheme.outline,
            timeAgo: timeAgo,
          );
        },
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, VideoItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('删除记录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
        content: Text('确定删除这条记录？', style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消', style: TextStyle(color: colorScheme.outline, fontSize: 14))),
          TextButton(
            onPressed: () async { Navigator.pop(ctx); await controller.removeHistory(item.vodId); },
            child: Text('确认', style: TextStyle(color: colorScheme.error, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _showClearConfirmDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('清空历史', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
        content: Text('确定清空所有历史？', style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消', style: TextStyle(color: colorScheme.outline, fontSize: 14))),
          TextButton(
            onPressed: () async { Navigator.pop(ctx); await controller.clearAll(); },
            child: Text('确认', style: TextStyle(color: colorScheme.error, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}