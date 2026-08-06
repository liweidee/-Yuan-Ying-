import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/flutter/refresh_indicator.dart' as custom;
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/common/widgets/video_card/video_card_h.dart';
import 'package:yuanying/modules/home/controllers/category_controller.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';
import 'package:yuanying/utils/grid.dart';
import 'package:yuanying/models/common/card_layout_mode.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';
import 'package:yuanying/t4/models/video_item.dart';

class CategoryPage extends StatefulWidget {
  final CategoryController controller;
  final Function(VideoItem) onVideoTap;

  const CategoryPage({
    Key? key,
    required this.controller,
    required this.onVideoTap,
  }) : super(key: key);

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with AutomaticKeepAliveClientMixin {
  late final CategoryController ctrl;
  final MainController mainController = Get.find<MainController>();
  final HomeController homeController = Get.find<HomeController>();

  double _lastScrollOffset = 0;
  bool _isScrollingDown = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ctrl = widget.controller;
    ctrl.scrollController.addListener(_onScrollUpdate);
  }

  void _onScrollUpdate() {
    final offset = ctrl.scrollController.position.pixels;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    if (delta.abs() > 2) {
      _isScrollingDown = delta > 0;
    }

    // 更新底部栏偏移
    mainController.updateBottomBarOffset(offset);

    // 更新顶部栏偏移
    if (mainController.hideTopBar.value) {
      final maxOffset = 52.0 + MediaQuery.of(context).padding.top;
      if (_isScrollingDown && offset > 20) {
        mainController.updateTopBarOffset(maxOffset);
      } else if (!_isScrollingDown && offset > 20) {
        final newOffset = (maxOffset - offset).clamp(0.0, maxOffset);
        mainController.updateTopBarOffset(newOffset);
      } else {
        mainController.updateTopBarOffset(0);
      }
    }

    // ===== 触发加载更多 =====
    if (ctrl.scrollController.position.pixels >=
        ctrl.scrollController.position.maxScrollExtent - 200) {
      ctrl.loadMore();
    }
  }

  @override
  void dispose() {
    ctrl.scrollController.removeListener(_onScrollUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isRecommend = ctrl.categoryId == 'recommend';

    return Obx(() {
      final isLoading = ctrl.isLoading.value;
      final isLoadingMore = ctrl.isLoadingMore.value;
      final isError = ctrl.isError.value;
      final errorMsg = ctrl.errorMsg.value;
      final videoList = ctrl.videoList;
      final hasLoaded = ctrl.hasLoaded.value;
      final mode = ctrl.layoutMode;
      final hasFilter = ctrl.hasFilter;
      final filterGroups = ctrl.filterGroups;

      final siteKey = ctrl.sourceManager.currentSite.value?['key'] ?? '';
      final showFilter = homeController.getFilterVisibility(siteKey);
      final shouldShowFilter = hasFilter && filterGroups != null && filterGroups.isNotEmpty && showFilter;

      Widget content;

      // ===== 1. 尚未加载完成 或 正在加载（首次加载） → 显示加载圈 =====
      if (!hasLoaded || (isLoading && videoList.isEmpty)) {
        content = Center(
          child: SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
        );
      }
      // ===== 2. 加载完成，有错误 → 显示错误页 =====
      else if (isError && videoList.isEmpty) {
        content = Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                errorMsg.isNotEmpty ? errorMsg : '加载失败，请重试',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: ctrl.refreshData,
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }
      // ===== 3. 加载完成，无数据 → 显示"暂无数据" =====
      else if (videoList.isEmpty) {
        content = Center(
          child: Text(
            '暂无数据',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        );
      }
      // ===== 4. 加载完成，有数据 → 正常列表 =====
      else {
        if (Grid.isListMode(mode)) {
          content = ListView.builder(
            controller: ctrl.scrollController,
            itemCount: videoList.length + 1,
            itemBuilder: (context, index) {
              if (index == videoList.length) {
                if (isLoadingMore) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return const SizedBox(height: 16);
              }
              final item = videoList[index];
              return VideoCardH(
                videoItem: item,
                onTap: () => widget.onVideoTap(item),
              );
            },
          );
        } else {
          final gridDelegate = Grid.videoCardVDelegate(
            context,
            mode: mode,
            minHeight: 25,
          );
          content = GridView.builder(
            controller: ctrl.scrollController,
            gridDelegate: gridDelegate,
            itemCount: videoList.length,
            itemBuilder: (context, index) {
              final item = videoList[index];
              return VideoCardV(
                videoItem: item,
                onTap: () => widget.onVideoTap(item),
              );
            },
          );
        }
      }

      // 非推荐分类才允许下拉刷新
      Widget contentWithRefresh = content;
      if (!isRecommend) {
        contentWithRefresh = custom.RefreshIndicator(
          onRefresh: ctrl.refreshData,
          child: content,
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (shouldShowFilter) _buildFilterBar(theme, filterGroups!),
          Expanded(
            child: contentWithRefresh,
          ),
        ],
      );
    });
  }

  Widget _buildFilterBar(ThemeData theme, List<FilterGroup> groups) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: groups.map((FilterGroup group) {
          final children = group.values.map((value) {
            final isSelected = ctrl.filterValues[group.key] == value.value;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => ctrl.updateFilter(group.key, value.value),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.secondaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    value.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList();

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}