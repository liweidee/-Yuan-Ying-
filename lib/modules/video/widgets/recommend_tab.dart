// lib/modules/video/widgets/recommend_tab.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/utils/grid.dart';
import 'package:yuanying/modules/action/widgets/action_renderer.dart';
import 'package:yuanying/t4/services/source_manager.dart';

class RecommendTab extends StatefulWidget {
  final String controllerTag;

  const RecommendTab({super.key, required this.controllerTag});

  @override
  State<RecommendTab> createState() => _RecommendTabState();
}

class _RecommendTabState extends State<RecommendTab> {
  late final DetailController _detailController;
  late final HomeController _homeController;
  final List<VideoItem> _recommendList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _detailController = Get.find<DetailController>(tag: widget.controllerTag);
    _homeController = Get.find<HomeController>();
    _loadRecommendData();
  }

  Future<void> _loadRecommendData() async {
    setState(() => _isLoading = true);

    try {
      final detail = _detailController.introController.videoDetail.value;
      final items = await _fetchRecommendItems(detail?.typeName);

      setState(() {
        _recommendList.clear();
        _recommendList.addAll(items);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<List<VideoItem>> _fetchRecommendItems(String? currentTypeName) async {
    // 1. 优先从 HomeController 获取推荐列表（通过公开方法）
    final recommendItems = _homeController.getRecommendCachedItems();
    if (recommendItems.isNotEmpty) {
      return recommendItems;
    }

    // 2. 备选：根据当前视频分类名匹配分类 ID，从对应缓存截取最多 6 条
    if (currentTypeName != null && currentTypeName.isNotEmpty) {
      // 使用 firstWhere + orElse 替代 firstWhereOrNull
      final matched = _homeController.categories.firstWhere(
        (c) => c.typeName == currentTypeName && c.typeId != 'recommend',
        orElse: () => Category(typeId: '', typeName: ''),
      );
      if (matched.typeId.isNotEmpty) {
        final items = _homeController.getCachedItemsByCategory(
          matched.typeId,
          maxCount: 6,
        );
        if (items.isNotEmpty) return items;
      }
    }

    // 3. 最终备选：取第一个非推荐分类的缓存
    return _homeController.getFirstNonRecommendCachedItems(maxCount: 6);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    if (_recommendList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library, size: 48, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text('暂无推荐内容', style: TextStyle(fontSize: 14, color: colorScheme.outline)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        // 移动端（包括 400px）：固定 3 列
        if (availableWidth < 600) {
          return GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
              childAspectRatio: 0.65,
            ),
            itemCount: _recommendList.length,
            itemBuilder: (context, index) {
              final item = _recommendList[index];
              return VideoCardV(
                videoItem: item,
                onTap: () => _navigateToDetail(item),
              );
            },
          );
        }

        // 桌面端：自适应列数，卡片宽度 180~220
        double maxCrossAxisExtent = (availableWidth - 30) / 4;
        if (maxCrossAxisExtent > 220) maxCrossAxisExtent = 220;
        if (maxCrossAxisExtent < 180) maxCrossAxisExtent = 180;

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCrossAxisExtent,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: 0.65,
          ),
          itemCount: _recommendList.length,
          itemBuilder: (context, index) {
            final item = _recommendList[index];
            return VideoCardV(
              videoItem: item,
              onTap: () => _navigateToDetail(item),
            );
          },
        );
      },
    );
  }

  void _navigateToDetail(VideoItem item) {
    final sourceManager = Get.find<SourceManager>();

    // Action 卡片
    if (item.isAction) {
      final config = item.actionConfig;
      if (config != null) {
        final renderer = Get.find<ActionRenderer>();
        renderer.showAction(
          config.toJson(),
          module: sourceManager.currentSite.value?['key'] ?? '',
          extend: sourceManager.currentSite.value?['ext'],
          apiUrl: sourceManager.currentSite.value?['api'],
        );
        return;
      }
      SmartDialog.showToast('Action 配置解析失败');
      return;
    }

    // 文件夹
    if (item.vodTag == 'folder') {
      SmartDialog.showToast('请在首页切换分类');
      return;
    }

    // 普通视频：使用当前源
    final currentSite = sourceManager.currentSite.value;
    final pwd = currentSite?['ext'] is Map
        ? (currentSite!['ext'] as Map)['pwd']?.toString() ?? 'tinydust'
        : 'tinydust';

    // 生成唯一 tag
    final tag = DetailController.generateTag(prefix: 'detail_recommend');

    Get.toNamed(
      '/detail',
      arguments: {
        'vodId': item.vodId,
        'pwd': pwd,
        '_controllerTag': tag,
      },
      preventDuplicates: false,
    );
  }
}