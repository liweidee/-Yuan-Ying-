import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/source_filter_sheet.dart';
import 'package:yuanying/modules/search_result/controllers/search_result_controller.dart';
import 'package:yuanying/t4/models/video_item.dart';

class SearchResultPage extends StatefulWidget {
  const SearchResultPage({super.key});

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  late final SearchResultController controller;
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    controller = Get.put(SearchResultController());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Row(
          children: [
            // ===== 左侧边栏 =====
            _buildLeftSidebar(context),

            // ===== 右侧内容区 =====
            Expanded(
              child: Column(
                children: [
                  _buildTopBar(context),
                  Expanded(
                    child: Obx(() {
                      if (controller.isLoading.value && controller.currentItems.isEmpty) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      if (controller.isError.value) {
                        return _buildErrorView(context);
                      }
                      if (controller.currentItems.isEmpty) {
                        return _buildEmptyView(context);
                      }
                      return _isGridView
                          ? _buildGridView(context)
                          : _buildListView(context);
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 顶部导航栏 =====
  Widget _buildTopBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // 返回按钮
          GestureDetector(
            onTap: controller.goBack,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: Icon(Icons.arrow_back_ios, color: colorScheme.onSurface, size: 20),
            ),
          ),
          const SizedBox(width: 8),

          // 搜索关键词
          Expanded(
            child: Text(
              controller.keyword,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 关闭按钮
          GestureDetector(
            onTap: controller.closePage,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: Icon(Icons.close, color: colorScheme.onSurface, size: 20),
            ),
          ),
          const SizedBox(width: 4),

          // 筛选按钮
          GestureDetector(
            onTap: () => SourceFilterSheet.show(context),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: Icon(Icons.filter_list, color: colorScheme.onSurface, size: 22),
            ),
          ),
          const SizedBox(width: 4),

          // 搜索按钮（重新搜索）
          GestureDetector(
            onTap: controller.reSearch,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: Icon(Icons.search, color: colorScheme.onSurface, size: 22),
            ),
          ),
          const SizedBox(width: 4),

          // 视图切换按钮
          GestureDetector(
            onTap: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: Icon(
                _isGridView ? Icons.grid_view : Icons.list,
                color: colorScheme.onSurface,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== 左侧边栏 =====
  Widget _buildLeftSidebar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 120,
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              // 访问 observable 触发更新
              final currentKey = controller.currentSourceKey.value;
              final options = controller.sourceOptions;
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final key = options[index];
                  final isSelected = key == currentKey;
                  final name = controller.getSourceName(key);
                  final countDisplay = controller.getSourceCountDisplay(key);

                  return _buildSidebarItem(
                    context: context,
                    name: name,
                    countDisplay: countDisplay,
                    isSelected: isSelected,
                    onTap: () => controller.switchSource(key),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required BuildContext context,
    required String name,
    required String countDisplay,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check,
                    size: 16,
                    color: colorScheme.onPrimary,
                  ),
              ],
            ),
            Text(
              countDisplay,
              style: textTheme.bodySmall?.copyWith(
                color: isSelected ? colorScheme.onPrimary.withOpacity(0.8) : colorScheme.outline,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 列表视图 =====
  Widget _buildListView(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100) {
            controller.loadMore();
          }
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: controller.currentItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = controller.currentItems[index];
          return _buildResultCard(context, item);
        },
      ),
    );
  }

  // ===== 网格视图 =====
  Widget _buildGridView(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // 根据屏幕宽度自适应列数，限定卡片最大宽度
    double maxCrossAxisExtent;
    if (screenWidth < 600) {
      // 手机：双列，卡片约 170px
      maxCrossAxisExtent = 180.0;
    } else if (screenWidth < 900) {
      // 平板：三列
      maxCrossAxisExtent = 200.0;
    } else {
      // 桌面：四列或更多，卡片 220px 左右
      maxCrossAxisExtent = 200.0;
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100) {
            controller.loadMore();
          }
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxCrossAxisExtent,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          childAspectRatio: 0.65, // 卡片高度/宽度，值越小卡片越高
        ),
        itemCount: controller.currentItems.length,
        itemBuilder: (context, index) {
          final item = controller.currentItems[index];
          return _buildGridCard(context, item);
        },
      ),
    );
  }

  // ===== 单个结果卡片（列表模式） =====
  Widget _buildResultCard(BuildContext context, VideoItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final sourceName = controller.getSourceName(item.vodSource);
    final updateInfo = item.vodRemarks ?? '';

    return GestureDetector(
      onTap: () => controller.onItemTap(item),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item.vodPic,
                width: 90,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 90,
                  height: 120,
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.movie,
                    size: 32,
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 文本信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.vodName,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // 来源
                  Row(
                    children: [
                      Icon(
                        Icons.source,
                        size: 14,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        sourceName,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // 更新标签
                  if (updateInfo.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        updateInfo,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onPrimary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 单个结果卡片（网格模式） =====
  Widget _buildGridCard(BuildContext context, VideoItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final updateInfo = item.vodRemarks ?? '';

    return GestureDetector(
      onTap: () => controller.onItemTap(item),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图片 - 占大部分空间
            Expanded(
              flex: 4,
              child: Image.network(
                item.vodPic,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.movie,
                    size: 32,
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ),
            // 文字 - 紧凑显示
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.vodName,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  if (updateInfo.isNotEmpty)
                    Text(
                      updateInfo,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 错误视图 =====
  Widget _buildErrorView(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            controller.errorMsg.value.isNotEmpty ? controller.errorMsg.value : '加载失败',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: controller.retry,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  // ===== 空视图 =====
  Widget _buildEmptyView(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            '没有找到相关结果',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}