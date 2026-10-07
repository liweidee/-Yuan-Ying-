import 'dart:async'; // ★ 新增：StreamSubscription

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
  // 由 late final 改为 late：didUpdateWidget 里会重新赋值，
  // late final 二次赋值会抛 LateInitializationError（原代码已有此隐患）
  late CategoryController ctrl;
  final HomeController homeController = Get.find<HomeController>();

  // ===== 自动补齐分页相关状态 =====
  /// 防止同一帧内重复排队 postFrame 回调
  bool _postFrameScheduled = false;

  /// 连续自动补齐计数器（用户手动滚动时复位）
  int _autoLoadCount = 0;

  /// 连续自动补齐上限，避免极少数源每页只返回 1 条时无限请求
  static const int _maxAutoLoad = 10;

  /// videoList 的响应式订阅句柄（RxList 不支持 addListener，
  /// 必须用 listen() 返回 StreamSubscription 才能 cancel）
  StreamSubscription<List<VideoItem>>? _videoListSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ctrl = widget.controller;
    // 只保留加载更多监听，不再处理顶部栏隐藏
    _bindListeners(ctrl);
  }

  @override
  void didUpdateWidget(CategoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果 controller 变了，重新绑定
    if (oldWidget.controller != widget.controller) {
      _unbindListeners(ctrl);
      ctrl = widget.controller;
      _autoLoadCount = 0; // 换控制器时复位计数器
      _bindListeners(ctrl);
    }
  }

  // ===== 监听器绑定 / 解绑统一管理 =====

  void _bindListeners(CategoryController c) {
    c.scrollController.addListener(_onScrollForLoadMore);
    // RxList 用 listen 订阅（返回 StreamSubscription），不是 addListener。
    // 先取消旧订阅，防止 controller 复用时遗留订阅。
    _videoListSub?.cancel();
    _videoListSub = c.videoList.listen((_) => _checkAutoLoadMore());
  }

  void _unbindListeners(CategoryController c) {
    c.scrollController.removeListener(_onScrollForLoadMore);
    // 取消订阅，避免内存泄漏
    _videoListSub?.cancel();
    _videoListSub = null;
  }

  // 仅用于加载更多
  void _onScrollForLoadMore() {
    // 用户手动滚动 → 页面已可滚动，复位自动补齐计数器
    _autoLoadCount = 0;

    if (ctrl.isLoadingMore.value || ctrl.isLoading.value) return;
    if (ctrl.scrollController.position.pixels >=
        ctrl.scrollController.position.maxScrollExtent - 200) {
      ctrl.loadMore();
    }
  }

  /// 列表数据变化后检测"当前不可滚动且还没到底"，主动补齐下一页。
  ///
  /// 场景：部分源第一页只返回少数几条，卡片视图下一屏就能显示完，
  ///      maxScrollExtent == 0，永远不会触发滚动加载。此时主动补下一页。
  void _checkAutoLoadMore() {
    if (_postFrameScheduled) return; // 同帧去重
    _postFrameScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameScheduled = false;
      if (!mounted) return;

      // ===== 门禁（全部必须通过，顺序可任意）=====
      if (_autoLoadCount >= _maxAutoLoad) return; // 上限保护
      if (ctrl.isLoading.value || ctrl.isLoadingMore.value) return;
      if (ctrl.isEnd) return;                     // 已到底
      if (ctrl.videoList.isEmpty) return;         // 空列表交由原逻辑处理
      if (ctrl.scrollController.positions.isEmpty) return;

      final pos = ctrl.scrollController.position;
      // 内容不足以滚动 → 主动加载下一页
      if (pos.maxScrollExtent <= 0) {
        _autoLoadCount++;
        ctrl.loadMore();
      }
    });
  }

  @override
  void dispose() {
    _unbindListeners(ctrl);
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),  // 左右留白
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  errorMsg.isNotEmpty ? errorMsg : '加载失败，请重试',
                  style: TextStyle(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: ctrl.refreshData,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                  child: const Text('重试'),
                ),
              ],
            ),
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