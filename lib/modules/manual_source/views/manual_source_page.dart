// lib/modules/manual_source/views/manual_source_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/manual_source/controllers/manual_source_controller.dart';
import 'package:yuanying/modules/manual_source/models/manual_source_item.dart';
import 'package:yuanying/modules/manual_source/services/manual_source_scanner.dart';
import 'package:yuanying/modules/manual_source/widgets/manual_source_edit_dialog.dart';
import 'package:yuanying/t4/services/source_manager.dart';

class ManualSourcePage extends StatefulWidget {
  const ManualSourcePage({super.key});

  @override
  State<ManualSourcePage> createState() => _ManualSourcePageState();
}

class _ManualSourcePageState extends State<ManualSourcePage> {
  final _ctrl = Get.put(ManualSourceController());
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    try {
      Get.find<SourceManager>().reloadManualSites();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Obx(() {
      final sel = _ctrl.selectionMode.value;
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: sel
            ? _buildSelectionAppBar(colorScheme)
            : _buildAppBar(colorScheme),
        body: Column(
          children: [
            _buildFilterBar(colorScheme),
            _buildSearch(colorScheme),
            _buildHeader(colorScheme),
            Expanded(child: _buildList(colorScheme)),
          ],
        ),
        bottomNavigationBar: sel ? _buildBottomBar(colorScheme) : null,
      );
    });
  }

  // ===== AppBar =====
  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    return AppBar(
      title: const Text('手动源管理',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      centerTitle: false,
      elevation: 0,
      actions: [
        Obx(() => _ctrl.loading.value
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh, size: 22),
                onPressed: _ctrl.refresh,
              )),
        IconButton(
          tooltip: '添加源',
          icon: const Icon(Icons.add, size: 22),
          onPressed: _onAdd,
        ),
        IconButton(
          tooltip: '批量操作',
          icon: const Icon(Icons.checklist, size: 22),
          onPressed: () => _ctrl.enterSelection(''),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(ColorScheme colorScheme) {
    final n = _ctrl.selectedIds.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _ctrl.exitSelection,
      ),
      title: Text('已选 $n 项',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      centerTitle: false,
      elevation: 0,
      actions: [
        TextButton(
          onPressed: _ctrl.selectAll,
          child: const Text('全选'),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: _ctrl.exitSelection,
        ),
      ],
    );
  }

  // ===== 筛选 chip =====
  Widget _buildFilterBar(ColorScheme colorScheme) {
    return Obx(() {
      final cur = _ctrl.filterType.value;
      final items = <Widget>[
        _buildFilterChip(
          label: '全部 (${_ctrl.countOf(null)})',
          selected: cur == null,
          onTap: () => _ctrl.setFilterType(null),
          colorScheme: colorScheme,
        ),
        ...ManualSourceType.values.map((t) {
          return _buildFilterChip(
            label: '${t.label} (${_ctrl.countOf(t)})',
            selected: cur == t,
            onTap: () => _ctrl.setFilterType(t),
            colorScheme: colorScheme,
          );
        }),
      ];
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: colorScheme.surface,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: items
                .map((w) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: w,
                    ))
                .toList(),
          ),
        ),
      );
    });
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ===== 搜索 =====
  Widget _buildSearch(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索名称 / 路径',
          prefixIcon: const Icon(Icons.search, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) => _ctrl.search.value = v,
      ),
    );
  }

  // ===== 头部统计 =====
  Widget _buildHeader(ColorScheme colorScheme) {
    return Obx(() {
      final t = _ctrl.filterType.value;
      final count = _ctrl.filtered.length;
      final canDrag = _ctrl.canReorder;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            Text(
              t == null ? '全部' : '${t.label} 筛选',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
            const SizedBox(width: 8),
            Text('$count 个',
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (canDrag && count > 1)
              Text('长按图标拖拽排序',
                  style:
                      TextStyle(fontSize: 11, color: colorScheme.outline)),
          ],
        ),
      );
    });
  }

  // ===== 列表 =====
  Widget _buildList(ColorScheme colorScheme) {
    return Obx(() {
      if (_ctrl.loading.value && _ctrl.all.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      final list = _ctrl.filtered;
      if (list.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description_outlined,
                  size: 64, color: colorScheme.outline),
              const SizedBox(height: 16),
              Text('暂无源', style: TextStyle(color: colorScheme.outline)),
              const SizedBox(height: 8),
              Text('点击右上角 + 添加',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline)),
            ],
          ),
        );
      }

      if (!_ctrl.canReorder) {
        return ListView.separated(
          padding: const EdgeInsets.all(Style.safeSpace),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: Style.cardSpace),
          itemBuilder: (context, i) => _buildCard(context, list[i]),
        );
      }

      return ReorderableListView.builder(
        padding: const EdgeInsets.all(Style.safeSpace),
        buildDefaultDragHandles: false,
        itemCount: list.length,
        onReorder: (oldIndex, newIndex) =>
            _ctrl.reorder(oldIndex, newIndex),
        itemBuilder: (context, i) {
          final item = list[i];
          return Padding(
            key: ValueKey(item.id),
            padding: const EdgeInsets.only(bottom: Style.cardSpace),
            child: _buildCard(context, item, dragIndex: i),
          );
        },
      );
    });
  }

  // ===== 卡片 =====
  Widget _buildCard(BuildContext context, ManualSourceItem item,
      {int? dragIndex}) {
    final colorScheme = Theme.of(context).colorScheme;
    final sel = _ctrl.selectionMode.value;
    final selected = _ctrl.selectedIds.contains(item.id);
    final showDragHandle = dragIndex != null && !sel;

    return Opacity(
      opacity: item.disabled ? 0.55 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: Style.mdRadius,
        child: InkWell(
          borderRadius: Style.mdRadius,
          onTap: () {
            if (sel) _ctrl.toggleSelection(item.id);
          },
          onLongPress: () {
            if (!sel) {
              _ctrl.enterSelection(item.id);
            } else {
              _ctrl.toggleSelection(item.id);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : colorScheme.surface,
              borderRadius: Style.mdRadius,
              border: Border.all(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outline.withValues(alpha: 0.15),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (sel) ...[
                  Checkbox(
                    value: selected,
                    onChanged: (_) => _ctrl.toggleSelection(item.id),
                  ),
                  const SizedBox(width: 4),
                ] else if (showDragHandle) ...[
                  ReorderableDragStartListener(
                    index: dragIndex!,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 20,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ],
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: Style.mdRadius,
                  ),
                  child: Icon(_iconFor(item.type), color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.displayName,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('${item.tagLine} · ${item.path}',
                          style: TextStyle(
                              fontSize: 11, color: colorScheme.outline),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (item.disabled)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('禁用',
                        style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onErrorContainer)),
                  ),
                if (!sel)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: colorScheme.outline),
                    onSelected: (v) {
                      if (v == 'edit') _onEdit(item);
                      if (v == 'toggle') _ctrl.toggleDisabled(item);
                      if (v == 'delete') _confirmDelete(item);
                    },
                    itemBuilder: (ctx) => [
                      if (item.type != ManualSourceType.html)
                        const PopupMenuItem(
                            value: 'edit', child: Text('编辑')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(item.disabled ? '启用' : '禁用'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('删除',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(ManualSourceType t) {
    switch (t) {
      case ManualSourceType.py: return Icons.code;
      case ManualSourceType.dr2:
      case ManualSourceType.dr3: return Icons.javascript;
      case ManualSourceType.js: return Icons.extension;
      case ManualSourceType.html: return Icons.language;
      case ManualSourceType.xbpq: return Icons.code;
      case ManualSourceType.xyq: return Icons.code;
      case ManualSourceType.t4: return Icons.cloud;
    }
  }

  // ===== 底部批量栏 =====
  Widget _buildBottomBar(ColorScheme colorScheme) {
    final n = _ctrl.selectedIds.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
              top: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.15))),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: n == 0 ? null : () => _ctrl.batchDisable(true),
                icon: const Icon(Icons.block, size: 18),
                label: const Text('禁用'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: n == 0 ? null : () => _ctrl.batchDisable(false),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('启用'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: n == 0 ? null : _confirmBatchDelete,
                icon: Icon(Icons.delete_outline,
                    size: 18, color: colorScheme.error),
                label: Text('删除($n)',
                    style: TextStyle(color: colorScheme.error)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 添加（统一走 edit dialog）=====
  Future<void> _onAdd() async {
    final r = await showManualSourceEditDialog(context);
    if (r == null) return;

    // T4
    if (r.type == ManualSourceType.t4) {
      await _ctrl.addT4Source(
        name: r.name,
        api: r.api,
        searchable: r.searchable,
        filterable: r.filterable,
        quickSearch: r.quickSearch,
        ext: r.ext,
      );
      return;
    }

    // 文件类型
    final paths = r.localFilePaths;
    if (paths == null || paths.isEmpty) {
      SmartDialog.showToast('未选择文件');
      return;
    }

    try {
      // 1. 保存所有文件
      final savedFiles = <String>[];
      for (final path in paths) {
        final saved = await ManualSourceScanner.saveBytes(
          r.type,
          File(path).uri.pathSegments.last,
          await File(path).readAsBytes(),
        );
        savedFiles.add(saved);
      }

      // 2. 确定主文件名（用于 id）
      String? mainPath;
      if (r.type == ManualSourceType.html) {
        // 优先 .web.json，其次 .html
        for (final f in savedFiles) {
          if (f.toLowerCase().endsWith('.web.json')) {
            mainPath = f;
            break;
          }
        }
        mainPath ??= savedFiles.firstWhere(
          (f) => f.toLowerCase().endsWith('.html'),
          orElse: () => savedFiles.first,
        );
      } else {
        mainPath = savedFiles.first;
      }

      // 3. 计算 id
      final mainName = File(mainPath).uri.pathSegments.last;
      String baseName;
      if (mainName.toLowerCase().endsWith('.web.json')) {
        baseName =
            mainName.substring(0, mainName.length - '.web.json'.length);
      } else {
        final dot = mainName.lastIndexOf('.');
        baseName = dot > 0 ? mainName.substring(0, dot) : mainName;
      }

      final newId = 'manual_${r.type.name}_$baseName';
      await _ctrl.updateSourceById(
        newId,
        ManualSourceMeta(
          searchable: r.searchable,
          filterable: r.filterable,
          quickSearch: r.quickSearch,
          ext: r.ext,
        ),
      );

      await _ctrl.refresh();
      SmartDialog.showToast('已添加 ${r.name}');
    } catch (e) {
      SmartDialog.showToast('添加失败: $e');
    }
  }

  Future<void> _onEdit(ManualSourceItem item) async {
    final r = await showManualSourceEditDialog(context, existing: item);
    if (r == null) return;
    await _ctrl.updateSource(
      item,
      ManualSourceMeta(
        name: item.type == ManualSourceType.t4 ? r.name : item.name,
        api: item.type == ManualSourceType.t4 ? r.api : item.path,
        searchable: r.searchable,
        filterable: r.filterable,
        quickSearch: r.quickSearch,
        ext: r.ext,
        disabled: item.disabled,
      ),
    );
  }

  Future<void> _confirmDelete(ManualSourceItem item) async {
    final colorScheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        backgroundColor: colorScheme.surface,
        title: const Text('删除源'),
        content: Text(item.type == ManualSourceType.html
            ? '确定删除 ${item.name}（含 .web.json / .html 与配套 .js）吗？'
            : item.type.isFileBased
                ? '确定删除 ${item.name}.${item.type.ext} 吗？'
                : '确定删除 ${item.name} 吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await _ctrl.deleteItem(item);
  }

  Future<void> _confirmBatchDelete() async {
    final n = _ctrl.selectedIds.length;
    if (n == 0) return;
    final colorScheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        backgroundColor: colorScheme.surface,
        title: Text('删除 $n 个源'),
        content: Text('确定删除所选 $n 个源吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await _ctrl.deleteSelected();
  }
}