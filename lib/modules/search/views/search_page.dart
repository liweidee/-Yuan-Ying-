import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/source_filter_sheet.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/search/controllers/search_controller.dart';

// ============================================================================
// 热搜布局模式枚举（三种视图）
// ============================================================================
enum HotLayoutMode {
  list,      // T形：左文右数（无图）
  leftImage, // 左图右文（缩略图+标题/描述/播放量）
  grid2,     // 双列网格（竖排卡片）
}

// ============================================================================
// 搜索页主界面
// ============================================================================
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final SearchPageController controller;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // 热搜布局模式：默认左图右文
  final Rx<HotLayoutMode> _hotLayoutMode = HotLayoutMode.leftImage.obs;

  @override
  void initState() {
    super.initState();
    controller = Get.put(SearchPageController());
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    controller.searchKeyword.value = _textController.text;
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Obx(() {
              if (controller.historyList.isEmpty) return const SizedBox.shrink();
              return _buildHistorySection(context);
            }),
            Expanded(
              child: Obx(() {
                if (controller.isLoadingHot.value) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                if (controller.isHotError.value) {
                  return _buildErrorView(context);
                }
                if (controller.hotList.isEmpty) {
                  return _buildEmptyView(context);
                }
                return _buildHotList(context);
              }),
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
            '加载失败，请重试',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: controller.refreshHotData,
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
      child: Text(
        '暂无热搜数据',
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.outline,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 返回按钮
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: Icon(Icons.arrow_back_ios, color: colorScheme.onSurface, size: 20),
            ),
          ),
          const SizedBox(width: 4),

          // 搜索输入框（无背景）
          Expanded(
            child: Container(
              height: 32,
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                onSubmitted: (_) => controller.doSearch(),
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: '搜索视频...',
                  hintStyle: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.5),
                    height: 1.2,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                  suffixIcon: Obx(() {
                    if (controller.searchKeyword.value.isNotEmpty) {
                      return GestureDetector(
                        onTap: () {
                          _textController.clear();
                          controller.clearSearch();
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          child: Icon(Icons.clear, size: 18, color: colorScheme.outline),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                ),
                textInputAction: TextInputAction.search,
                textAlignVertical: TextAlignVertical.center,
              ),
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

          // 搜索按钮
          GestureDetector(
            onTap: () => controller.doSearch(),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: Icon(Icons.search, color: colorScheme.onSurface, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  // ===== 搜索历史区域 =====
  Widget _buildHistorySection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              children: [
                Text(
                  '搜索历史',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: controller.clearHistory,
                  child: Row(
                    children: [
                      Text(
                        '清空',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.clear_all,
                        size: 16,
                        color: colorScheme.outline,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Obx(() {
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: controller.historyList.map((keyword) {
                return GestureDetector(
                  onTap: () => controller.onHistoryTap(keyword),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      keyword,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }

  // ===== 热搜列表（根据布局模式分发） =====
  Widget _buildHotList(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏 + 布局切换按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '热搜',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Obx(() {
                final mode = _hotLayoutMode.value;
                IconData iconData;
                switch (mode) {
                  case HotLayoutMode.list:
                    iconData = Icons.reorder; // T形：点横杠三排
                    break;
                  case HotLayoutMode.leftImage:
                    iconData = Icons.list_alt; // 左图右文：粗体列表
                    break;
                  case HotLayoutMode.grid2:
                    iconData = Icons.grid_view; // 双列网格：四口
                    break;
                  default:
                    iconData = Icons.list_alt;
                }
                return IconButton(
                  icon: Icon(iconData, size: 22, color: colorScheme.onSurface),
                  onPressed: () {
                    // 三种模式循环切换：list → leftImage → grid2 → list
                    final nextMode = switch (_hotLayoutMode.value) {
                      HotLayoutMode.list => HotLayoutMode.leftImage,
                      HotLayoutMode.leftImage => HotLayoutMode.grid2,
                      HotLayoutMode.grid2 => HotLayoutMode.list,
                    };
                    _hotLayoutMode.value = nextMode;
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  splashRadius: 16,
                );
              }),
            ],
          ),
        ),
        // 列表内容
        Expanded(
          child: Obx(() {
            switch (_hotLayoutMode.value) {
              case HotLayoutMode.list:
                return _buildHotListTextOnly(context);
              case HotLayoutMode.leftImage:
                return _buildHotListLeftImage(context);
              case HotLayoutMode.grid2:
                return _buildHotListGrid(context);
              default:
                return const SizedBox.shrink();
            }
          }),
        ),
      ],
    );
  }

  // ============================================================
  // 视图1：T形列表（左文右数，无图）
  // ============================================================
  Widget _buildHotListTextOnly(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: controller.hotList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = controller.hotList[index];
        return GestureDetector(
          onTap: () => controller.onHotItemTap(item),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                // 排名序号
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: index < 3
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 标题
                Expanded(
                  child: Text(
                    item.title,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // 播放量
                Text(
                  '${item.pv}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                // 右箭头
                Text(
                  '›',
                  style: TextStyle(
                    fontSize: 18,
                    color: colorScheme.outline.withOpacity(0.4),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // 视图2：左图右文（缩略图 + 标题/描述/播放量）
  // ============================================================
  Widget _buildHotListLeftImage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: controller.hotList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = controller.hotList[index];
        return GestureDetector(
          onTap: () => controller.onHotItemTap(item),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    item.cover,
                    width: 90,
                    height: 63,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 90,
                      height: 63,
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.movie,
                        size: 28,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.comment,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (item.upinfo.isNotEmpty) ...[
                            Text(
                              item.upinfo,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 2,
                              height: 2,
                              decoration: BoxDecoration(
                                color: colorScheme.outline.withOpacity(0.3),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '${item.pv}',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // 视图3：双列竖排卡片（图片固定高度，文字填满底部）
  // ============================================================
  Widget _buildHotListGrid(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;

    // 双列，桌面端自适应增加列数
    double maxCrossAxisExtent = 200.0;
    if (screenWidth > 600) {
      maxCrossAxisExtent = 180.0;
    }
    if (screenWidth > 900) {
      maxCrossAxisExtent = 200.0;
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: controller.hotList.length,
      itemBuilder: (context, index) {
        final item = controller.hotList[index];
        return GestureDetector(
          onTap: () => controller.onHotItemTap(item),
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
                // 图片占 4/5 空间
                Expanded(
                  flex: 4,
                  child: Image.network(
                    item.cover,
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
                // 文字占 1/5 空间
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Text(
                          item.title,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${item.pv}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}