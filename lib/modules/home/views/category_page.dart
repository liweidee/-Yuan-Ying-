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

  // ===== 移除 _lastScrollOffset 和 _isScrollingDown =====

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ctrl = widget.controller;
    ctrl.scrollController.addListener(_onScrollUpdate);
  }

  // ===== 简化后的滚动监听 =====
  void _onScrollUpdate() {
    final offset = ctrl.scrollController.position.pixels;

    mainController.updateBottomBarOffset(offset);
    mainController.updateTopBarOffset(offset);

    // 触发加载更多
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
      } else if (isError && videoList.isEmpty) {
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
      } else if (videoList.isEmpty) {
        content = Center(
          child: Text(
            '暂无数据',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        );
      } else {
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
          // 固定间距
          if (shouldShowFilter) const SizedBox(height: 4),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: contentWithRefresh,
            ),
          ),
        ],
      );
    });
  }

  Widget _buildFilterBar(ThemeData theme, List<FilterGroup> groups) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
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