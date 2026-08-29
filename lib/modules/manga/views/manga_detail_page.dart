// lib/modules/manga/views/manga_detail_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/manga/controllers/manga_detail_controller.dart';
import 'package:yuanying/modules/novel/widgets/book_cover.dart';
import 'package:yuanying/core/theme/style.dart';

const int kGroupSize = 50;

class MangaDetailPage extends StatefulWidget {
  const MangaDetailPage({super.key});

  @override
  State<MangaDetailPage> createState() => _MangaDetailPageState();
}

class _MangaDetailPageState extends State<MangaDetailPage> {
  late final MangaDetailController controller;
  late final String vodId;
  late final String pwd;
  late final Map<String, dynamic>? site;

  bool _desc = false;
  bool _isGrid = false;
  int? _selectedGroup;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map?;
    vodId = args?['vodId']?.toString() ?? '';
    pwd = args?['pwd']?.toString() ?? 'tinydust';
    site = args?['site'] as Map<String, dynamic>?;
    if (vodId.isNotEmpty) {
      controller = Get.put(MangaDetailController(), tag: vodId);
      controller.init(vodId, pwd, site);
    }
  }

  @override
  void dispose() {
    if (vodId.isNotEmpty) {
      Get.delete<MangaDetailController>(tag: vodId);
    }
    super.dispose();
  }

  List<int> _getVisibleIndices() {
    final total = controller.episodes.length;
    List<int> indices = List.generate(total, (i) => i);
    if (_desc) indices = indices.reversed.toList();
    if (_selectedGroup != null) {
      final start = _selectedGroup! * kGroupSize;
      final end = (start + kGroupSize).clamp(0, total);
      indices = indices.where((i) => i >= start && i < end).toList();
    }
    return indices;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (vodId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('详情')),
        body: const Center(child: Text('缺少视频ID')),
      );
    }
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.error.value.isNotEmpty) {
          return _buildError(context, controller);
        }
        if (controller.detail.value == null) {
          return const Center(child: Text('无数据'));
        }
        return _buildContent(context, controller);
      }),
    );
  }

  Widget _buildError(BuildContext context, MangaDetailController controller) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: colorScheme.outline),
          const SizedBox(height: 12),
          Text(controller.error.value, style: TextStyle(color: colorScheme.outline)),
          const SizedBox(height: 16),
          FilledButton(onPressed: controller.loadDetail, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, MangaDetailController controller) {
    final colorScheme = Theme.of(context).colorScheme;
    final detail = controller.detail.value!;
    final episodes = controller.episodes;
    final total = episodes.length;
    final indices = _getVisibleIndices();

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Get.back(),
          ),
          title: Text(detail.vodName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colorScheme.surfaceContainerHighest, colorScheme.surface],
                ),
              ),
            ),
          ),
        ),
        // 信息卡片区域
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 110,
                      height: 154,
                      child: NovelBookCover(coverUrl: detail.vodPic, title: detail.vodName, author: detail.vodActor),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.vodName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                      const SizedBox(height: 6),
                      if (detail.vodActor != null && detail.vodActor!.isNotEmpty)
                        Text('作者：${detail.vodActor}', style: TextStyle(fontSize: 13, color: colorScheme.outline)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Obx(() => Text('书源：${controller.sourceName.value}', style: TextStyle(fontSize: 10.5, color: colorScheme.primary))),
                      ),
                      const SizedBox(height: 8),
                      if (detail.vodContent != null && detail.vodContent!.isNotEmpty)
                        ExpandableIntro(text: detail.vodContent!, colorScheme: colorScheme),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => controller.openReader(0),
                          icon: const Icon(Icons.menu_book, size: 18),
                          label: const Text('开始阅读'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // const SliverToBoxAdapter(child: Divider(height: 1)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 4, height: 16,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('目录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$total 话', style: TextStyle(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CatalogIconButton(
                      icon: _desc ? Icons.vertical_align_top : Icons.vertical_align_bottom,
                      tooltip: _desc ? '正序' : '倒序',
                      isActive: _desc,
                      onTap: () => setState(() => _desc = !_desc),
                    ),
                    _CatalogIconButton(
                      icon: _isGrid ? Icons.grid_view_rounded : Icons.view_list_rounded,
                      tooltip: _isGrid ? '网格' : '列表',
                      isActive: _isGrid,
                      onTap: () => setState(() => _isGrid = !_isGrid),
                    ),
                    _CatalogGroupButton(
                      total: total,
                      selectedGroup: _selectedGroup,
                      onChanged: (v) => setState(() => _selectedGroup = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_isGrid)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 2.2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final idx = indices[i];
                  return InkWell(
                    onTap: () => controller.openReader(idx),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        episodes[idx].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
                      ),
                    ),
                  );
                },
                childCount: indices.length,
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final idx = indices[i];
                return Column(
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(
                        episodes[idx].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, color: colorScheme.onSurface),
                      ),
                      trailing: Icon(Icons.chevron_right, size: 18, color: colorScheme.outline.withValues(alpha: 0.5)),
                      onTap: () => controller.openReader(idx),
                    ),
                    Divider(height: 1, indent: 16, color: colorScheme.outline.withValues(alpha: 0.1)),
                  ],
                );
              },
              childCount: indices.length,
            ),
          ),
      ],
    );
  }
}

// ===== 辅助组件（和小说页一致）=====

class _CatalogIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;
  const _CatalogIconButton({required this.icon, required this.tooltip, required this.isActive, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: isActive ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: isActive ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

class _CatalogGroupButton extends StatelessWidget {
  final int total;
  final int? selectedGroup;
  final ValueChanged<int?> onChanged;
  const _CatalogGroupButton({required this.total, required this.selectedGroup, required this.onChanged});

  List<PopupMenuEntry<int?>> _buildMenuItems(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = <PopupMenuEntry<int?>>[
      PopupMenuItem<int?>(
        value: null,
        child: Text('全部', style: TextStyle(fontSize: 13, color: selectedGroup == null ? colorScheme.primary : null)),
      ),
    ];
    if (total <= 0) return items;
    final n = (total / kGroupSize).ceil();
    for (int g = 0; g < n; g++) {
      final start = g * kGroupSize + 1;
      final end = ((g + 1) * kGroupSize).clamp(0, total);
      final isSel = selectedGroup == g;
      items.add(PopupMenuItem<int?>(
        value: g,
        child: Text('$start-$end', style: TextStyle(fontSize: 13, color: isSel ? colorScheme.primary : null)),
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '分组',
      child: InkWell(
        onTap: () async {
          final RenderBox button = context.findRenderObject() as RenderBox;
          final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
          final Rect rect = Rect.fromPoints(
            button.localToGlobal(Offset.zero, ancestor: overlay),
            button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
          );
          final result = await showMenu<int?>(
            context: context,
            position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
            items: _buildMenuItems(context),
            color: colorScheme.surface,
          );
          onChanged(result);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selectedGroup != null ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.more_vert,
            size: 20,
            color: selectedGroup != null ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class ExpandableIntro extends StatefulWidget {
  final String text;
  final ColorScheme colorScheme;
  const ExpandableIntro({super.key, required this.text, required this.colorScheme});
  @override
  State<ExpandableIntro> createState() => _ExpandableIntroState();
}

class _ExpandableIntroState extends State<ExpandableIntro> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.text,
        maxLines: _expanded ? null : 2,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, color: widget.colorScheme.outline, height: 1.7),
      ),
    );
  }
}