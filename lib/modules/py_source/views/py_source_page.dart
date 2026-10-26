// lib/modules/py_source/views/py_source_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/py_source/controllers/py_source_controller.dart';
import 'package:yuanying/modules/py_source/models/py_local_source.dart';
import 'package:yuanying/modules/py_source/widgets/batch_settings_dialog.dart';
import 'package:yuanying/modules/py_source/widgets/edit_source_dialog.dart';
import 'package:yuanying/modules/py_source/widgets/reset_meta_dialog.dart';
import 'package:yuanying/t4/services/source_manager.dart';

class PySourcePage extends StatefulWidget {
  const PySourcePage({super.key});

  @override
  State<PySourcePage> createState() => _PySourcePageState();
}

class _PySourcePageState extends State<PySourcePage> {
  final _ctrl = Get.put(PySourceController());
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final sel = _ctrl.selectionMode.value;
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: sel ? _buildSelectionAppBar(colorScheme) : _buildAppBar(colorScheme),
        body: Column(
          children: [
            _buildDirBar(colorScheme),
            _buildSearchBar(colorScheme),
            _buildHeader(colorScheme),
            Expanded(child: _buildList(colorScheme)),
          ],
        ),
        bottomNavigationBar: sel ? _buildBottomBar(colorScheme) : null,
      );
    });
  }

  // ===== AppBar（默认） =====
  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    return AppBar(
      title: const Text('Python 爬虫源',
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
        Obx(() => _ctrl.uploading.value
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                tooltip: '上传 py 文件',
                icon: const Icon(Icons.file_upload_outlined, size: 22),
                onPressed: _ctrl.pickAndUpload,
              )),
        IconButton(
          tooltip: '多选',
          icon: const Icon(Icons.checklist, size: 22),
          onPressed: () {
            _ctrl.enterSelection('');
            _ctrl.selectedNames.clear();
            _ctrl.selectionMode.value = true;
          },
        ),
      ],
    );
  }

  // ===== AppBar（多选） =====
  PreferredSizeWidget _buildSelectionAppBar(ColorScheme colorScheme) {
    final n = _ctrl.selectedNames.length;
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

  // ===== 目录提示 =====
  Widget _buildDirBar(ColorScheme colorScheme) {
    return FutureBuilder<String?>(
      future: _ctrl.dirPath(),
      builder: (context, snap) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        child: Text(
          '目录 ${snap.data ?? '...'}',
          style: TextStyle(fontSize: 11, color: colorScheme.outline),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  // ===== 搜索 =====
  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索本地源名称 / key',
          prefixIcon: const Icon(Icons.search, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) => _ctrl.search.value = v,
      ),
    );
  }

  // ===== 统计头 =====
  Widget _buildHeader(ColorScheme colorScheme) {
    return Obx(() {
      final count = _ctrl.filtered.length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            Text('本地源 (sdcard)',
                style: TextStyle(fontSize: 12, color: colorScheme.outline)),
            const SizedBox(width: 8),
            Text('$count 个',
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    });
  }

  // ===== 列表 =====
  Widget _buildList(ColorScheme colorScheme) {
    return Obx(() {
      if (_ctrl.loading.value && _ctrl.sources.isEmpty) {
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
              Text('暂无 .py 文件',
                  style: TextStyle(color: colorScheme.outline)),
              const SizedBox(height: 8),
              Text('点击右上角上传按钮添加',
                  style:
                      TextStyle(fontSize: 12, color: colorScheme.outline)),
            ],
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(Style.safeSpace),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: Style.cardSpace),
        itemBuilder: (context, i) => _buildCard(context, list[i]),
      );
    });
  }

  Widget _buildCard(BuildContext context, PyLocalSource s) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _ctrl.selectedNames.contains(s.name);
    final sel = _ctrl.selectionMode.value;

    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: () => sel ? _ctrl.toggleSelection(s.name) : _onTapSource(s),
        onLongPress: () {
          if (!sel) {
            _ctrl.enterSelection(s.name);
          } else {
            _ctrl.toggleSelection(s.name);
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
                  onChanged: (_) => _ctrl.toggleSelection(s.name),
                ),
                const SizedBox(width: 4),
              ],
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                  borderRadius: Style.mdRadius,
                ),
                child: Icon(Icons.code, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.effectiveName,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(s.tagLine,
                        style: TextStyle(
                            fontSize: 11, color: colorScheme.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (!sel) ...[
                IconButton(
                  tooltip: '编辑',
                  icon: Icon(Icons.edit_outlined,
                      size: 20, color: colorScheme.outline),
                  onPressed: () => _onEdit(s),
                ),
                IconButton(
                  tooltip: '删除',
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: colorScheme.error),
                  onPressed: () => _confirmDelete(s),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ===== 底部操作栏（多选） =====
  Widget _buildBottomBar(ColorScheme colorScheme) {
    final n = _ctrl.selectedNames.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.15)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: n == 0 ? null : _onBatchSettings,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('设置属性'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: n == 0 ? null : _onResetMeta,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('重置元数据'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: n == 0 ? null : _onDeleteSelected,
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

  // ===== 业务动作 =====

  Future<void> _onTapSource(PyLocalSource s) async {
    final site = {
      'key': s.siteKey,
      'name': s.effectiveName,
      'api': s.path,
      'type': 3,
      'searchable': s.effectiveSearchable,
      'filterable': s.effectiveFilterable,
      'quickSearch': s.effectiveQuickSearch,
      'title': s.effectiveTitle,
      'lang': 'hipy',
      'ext': s.effectiveExt,
    };
    final sm = Get.find<SourceManager>();
    try {
      await sm.switchSite(site);
      SmartDialog.showToast('已切换到 ${s.effectiveName}');
      Get.back();
    } catch (e) {
      SmartDialog.showToast('切换失败: $e');
    }
  }

  Future<void> _onEdit(PyLocalSource s) async {
    final meta = await showEditSourceDialog(context, s);
    if (meta == null) return;
    await _ctrl.saveSingleMeta(s, meta);
  }

  Future<void> _confirmDelete(PyLocalSource s) async {
    final colorScheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        backgroundColor: colorScheme.surface,
        title: const Text('删除源文件'),
        content: Text('确定删除 ${s.name}.py 吗？'),
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
    if (ok == true) await _ctrl.deleteSource(s);
  }

  Future<void> _onBatchSettings() async {
    final targets = _ctrl.selectedSources;
    if (targets.isEmpty) return;
    final result = await showBatchSettingsDialog(context, targets.length);
    if (result == null) return;
    await _ctrl.batchApply(
      targets: targets,
      searchable: result.searchable,
      quickSearch: result.quickSearch,
      filterable: result.filterable,
    );
  }

  Future<void> _onResetMeta() async {
    final targets = _ctrl.selectedSources;
    if (targets.isEmpty) return;
    final ok = await showResetMetaDialog(context, targets.length);
    if (ok != true) return;
    await _ctrl.resetMeta(targets);
  }

  Future<void> _onDeleteSelected() async {
    final n = _ctrl.selectedNames.length;
    if (n == 0) return;
    final colorScheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        backgroundColor: colorScheme.surface,
        title: Text('删除 $n 个源'),
        content: Text('确定删除所选 $n 个 py 文件吗？'),
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