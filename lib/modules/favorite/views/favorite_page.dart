import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/favorite/controllers/favorite_controller.dart';
import 'package:yuanying/common/widgets/media_card.dart';
import 'package:yuanying/t4/models/video_item.dart';

class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  late final FavoriteController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(FavoriteController());
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
        title: Text('我的收藏', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
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
      body: Column(
        children: [
          _buildFilterBar(context),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              }
              final list = controller.filteredList;
              if (list.isEmpty) {
                return _buildEmptyState(context);
              }
              return _buildContent(context, screenWidth, list);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Obx(() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          // bottom: BorderSide(
          //   color: colorScheme.outline.withOpacity(0.1),
          //   width: 1,
          // ),
        ),
      ),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'all', label: Text('全部')),
          ButtonSegment(value: 'video', label: Text('视频')),
          ButtonSegment(value: 'novel', label: Text('小说')),
          ButtonSegment(value: 'manga', label: Text('漫画')),
        ],
        selected: {controller.filterType.value},
        onSelectionChanged: (Set<String> newSelection) {
          controller.filterType.value = newSelection.first;
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: colorScheme.surfaceContainerHighest,
          selectedBackgroundColor: colorScheme.primaryContainer,
          selectedForegroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide.none,
          ),
        ),
      ),
    ));
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 64, color: colorScheme.outline.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text('暂无数据', style: textTheme.bodyMedium?.copyWith(color: colorScheme.outline.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, double screenWidth, List<VideoItem> list) {
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
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          return MediaCard(
            videoItem: item,
            onTap: () => controller.navigateToDetail(item),
            showSourceLabel: item.typeName != null && item.typeName!.isNotEmpty,
            sourceLabel: item.typeName ?? '',
            showDeleteButton: true,
            onDelete: () => _showDeleteConfirmDialog(context, item),
            bottomSubText: item.vodRemarks ?? '',
            bottomSubColor: Theme.of(context).colorScheme.primary,
            showProgress: false,
            timeAgo: '',
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
        title: Text('删除收藏', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
        content: Text('确定删除这条收藏？', style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消', style: TextStyle(color: colorScheme.outline, fontSize: 14))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await controller.removeFavorite(item.vodId);
            },
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
        title: Text('清空收藏', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
        content: Text('确定清空所有收藏？', style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消', style: TextStyle(color: colorScheme.outline, fontSize: 14))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await controller.clearAll();
            },
            child: Text('确认', style: TextStyle(color: colorScheme.error, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}