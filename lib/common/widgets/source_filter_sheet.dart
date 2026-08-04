import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/services/search_filter_service.dart';

/// 搜索源筛选弹窗（公共组件）
class SourceFilterSheet extends StatefulWidget {
  /// 弹窗初始高度比例
  final double initialChildSize;

  const SourceFilterSheet({
    super.key,
    this.initialChildSize = 0.7,
  });

  @override
  State<SourceFilterSheet> createState() => _SourceFilterSheetState();

  /// 显示筛选弹窗
  static Future<void> show(BuildContext context, {double initialChildSize = 0.7}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: initialChildSize,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: _SourceFilterSheetContent(
                scrollController: scrollController,
              ),
            );
          },
        );
      },
    );
  }
}

class _SourceFilterSheetState extends State<SourceFilterSheet> {
  @override
  Widget build(BuildContext context) {
    // 此State仅用于保持StatefulWidget结构，实际内容在 _SourceFilterSheetContent 中
    return Container();
  }
}

class _SourceFilterSheetContent extends StatefulWidget {
  final ScrollController scrollController;

  const _SourceFilterSheetContent({required this.scrollController});

  @override
  State<_SourceFilterSheetContent> createState() => _SourceFilterSheetContentState();
}

class _SourceFilterSheetContentState extends State<_SourceFilterSheetContent> {
  late final SearchFilterService filterService;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filterService = Get.find<SearchFilterService>();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    filterService.updateFilterSearch(_searchController.text);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        // 拖拽指示器
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colorScheme.outline.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),

        // 全选/全不选 + 关闭按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                children: [
                  _buildActionChip(
                    label: '全选',
                    onTap: () {
                      setState(() {
                        filterService.selectAllSources();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildActionChip(
                    label: '全不选',
                    onTap: () {
                      setState(() {
                        filterService.deselectAllSources();
                      });
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: colorScheme.outline),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    splashRadius: 16,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 搜索框
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '请输入内容搜索',
                  hintStyle: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  isDense: true,
                ),
                style: textTheme.bodyMedium,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 分隔线
        Container(
          height: 1,
          color: colorScheme.outline.withOpacity(0.1),
        ),

        // 源列表（双列网格）
        Expanded(
          child: Obx(() {
            final query = filterService.filterSearchQuery.value;
            final sites = filterService.getFilteredSites(query);

            if (sites.isEmpty) {
              return Center(
                child: Text(
                  '没有匹配的搜索源',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              );
            }

            return GridView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 0,
                mainAxisSpacing: 0,
                childAspectRatio: 5.5,
              ),
              itemCount: sites.length,
              itemBuilder: (context, index) {
                final site = sites[index];
                final key = site['key']?.toString() ?? '';
                final name = site['name']?.toString() ?? '未命名';
                final enabled = filterService.isSourceEnabled(key);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      right: (index % 2 == 0)
                          ? BorderSide(
                              color: colorScheme.outline.withOpacity(0.1),
                              width: 0.5,
                            )
                          : BorderSide.none,
                      bottom: BorderSide(
                        color: colorScheme.outline.withOpacity(0.1),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        height: 24,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Switch(
                            value: enabled,
                            onChanged: (value) {
                              setState(() {
                                filterService.toggleSourceEnabled(key, value);
                              });
                            },
                            activeColor: colorScheme.primary,
                            inactiveThumbColor: colorScheme.outline,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }),
        ),

        // 底部："只搜默认源"
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colorScheme.outline.withOpacity(0.1),
                width: 0.5,
              ),
            ),
          ),
          child: Obx(() {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '只搜默认源',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '当前只搜索: ${filterService.enabledSites.map((s) => s['name']?.toString() ?? '').join(', ')}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: filterService.onlyDefaultSource.value,
                  onChanged: (value) {
                    filterService.toggleOnlyDefaultSource(value);
                  },
                  activeColor: colorScheme.primary,
                  inactiveThumbColor: colorScheme.outline,
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildActionChip({
    required String label,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}