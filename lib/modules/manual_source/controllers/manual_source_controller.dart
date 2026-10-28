// lib/modules/manual_source/controllers/manual_source_controller.dart

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../models/manual_source_item.dart';
import '../services/manual_source_scanner.dart';
import '../services/manual_source_store.dart';

class ManualSourceController extends GetxController {
  final RxList<ManualSourceItem> all = <ManualSourceItem>[].obs;
  final RxBool loading = false.obs;
  final RxBool uploading = false.obs;
  final RxString search = ''.obs;

  final Rx<ManualSourceType?> filterType = Rx<ManualSourceType?>(null);

  final RxBool selectionMode = false.obs;
  final RxSet<String> selectedIds = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    refresh();
  }

  Future<void> refresh() async {
    loading.value = true;
    try {
      all.assignAll(await ManualSourceScanner.scanAll());
      selectedIds.removeWhere((id) => !all.any((e) => e.id == id));
    } catch (e) {
      SmartDialog.showToast('扫描失败: $e');
    } finally {
      loading.value = false;
    }
  }

  // ===== 筛选 & 排序 =====
  List<ManualSourceItem> get filtered {
    final q = search.value.trim().toLowerCase();
    final t = filterType.value;
    return all.where((e) {
      if (t != null && e.type != t) return false;
      if (q.isEmpty) return true;
      return e.name.toLowerCase().contains(q) ||
          e.path.toLowerCase().contains(q);
    }).toList();
  }

  bool get canReorder =>
      filterType.value == null && !selectionMode.value;

  int countOf(ManualSourceType? t) {
    if (t == null) return all.length;
    return all.where((e) => e.type == t).length;
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (!canReorder) return;
    final list = all.toList();
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex < 0) newIndex = 0;
    if (newIndex >= list.length) newIndex = list.length - 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    all.assignAll(list);
    await ManualSourceStore.saveOrder(list.map((e) => e.id).toList());
  }

  void setFilterType(ManualSourceType? t) {
    if (filterType.value == t) return;
    filterType.value = t;
    search.value = '';
  }

  // ===== 添加 T4 源 =====
  Future<void> addT4Source({
    required String name,
    required String api,
    int searchable = 1,
    int filterable = 1,
    int quickSearch = 1,
    String ext = '',
  }) async {
    if (name.isEmpty || api.isEmpty) return;
    final id = _generateT4Id(name);
    await ManualSourceStore.write(
      id,
      ManualSourceMeta(
        name: name,
        api: api,
        searchable: searchable,
        filterable: filterable,
        quickSearch: quickSearch,
        ext: ext,
      ),
    );
    await refresh();
    SmartDialog.showToast('已添加 $name');
  }

  String _generateT4Id(String name) {
    final base = 'manual_t4_$name';
    final metas = ManualSourceStore.readAll();
    if (!metas.containsKey(base)) return base;
    int i = 1;
    while (metas.containsKey('${base}_$i')) {
      i++;
    }
    return '${base}_$i';
  }

  Future<void> updateSourceById(String id, ManualSourceMeta meta) async {
    await ManualSourceStore.write(id, meta);
  }

  // ===== 编辑 =====
  Future<void> updateSource(ManualSourceItem item, ManualSourceMeta meta) async {
    await ManualSourceStore.write(item.id, meta);
    await refresh();
    SmartDialog.showToast('已保存');
  }

  // ===== 禁用/启用 =====
  Future<void> toggleDisabled(ManualSourceItem item) async {
    final meta = ManualSourceStore.read(item.id) ?? const ManualSourceMeta();
    await ManualSourceStore.write(
      item.id,
      meta.copyWith(disabled: !item.disabled),
    );
    await refresh();
  }

  // ===== 删除 =====
  Future<void> deleteItem(ManualSourceItem item) async {
    if (item.type.isFileBased) {
      await ManualSourceScanner.deleteFile(item);
    }
    await ManualSourceStore.remove(item.id);
    // 兼容清理旧 id
    if (item.type == ManualSourceType.html) {
      await ManualSourceStore.remove('manual_web_${item.name}');
    }
    await refresh();
    SmartDialog.showToast('已删除 ${item.name}');
  }

  Future<void> deleteSelected() async {
    final ids = List<String>.from(selectedIds);
    int ok = 0;
    for (final id in ids) {
      ManualSourceItem? item;
      for (final e in all) {
        if (e.id == id) {
          item = e;
          break;
        }
      }
      if (item == null) continue;
      try {
        if (item.type.isFileBased) {
          await ManualSourceScanner.deleteFile(item);
        }
        await ManualSourceStore.remove(item.id);
        if (item.type == ManualSourceType.html) {
          await ManualSourceStore.remove('manual_web_${item.name}');
        }
        ok++;
      } catch (_) {}
    }
    selectedIds.clear();
    selectionMode.value = false;
    await refresh();
    SmartDialog.showToast('已删除 $ok 个源');
  }

  Future<void> batchDisable(bool disabled) async {
    final items = selectedItems;
    for (final item in items) {
      final meta = ManualSourceStore.read(item.id) ?? const ManualSourceMeta();
      await ManualSourceStore.write(
        item.id,
        meta.copyWith(disabled: disabled),
      );
    }
    await refresh();
    SmartDialog.showToast('已${disabled ? "禁用" : "启用"} ${items.length} 个源');
  }

  // ===== 多选 =====
  void enterSelection(String id) {
    selectionMode.value = true;
    if (id.isNotEmpty) selectedIds.add(id);
  }

  void exitSelection() {
    selectionMode.value = false;
    selectedIds.clear();
  }

  void toggleSelection(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    if (selectedIds.isEmpty) selectionMode.value = false;
  }

  void selectAll() {
    selectedIds.assignAll(filtered.map((e) => e.id).toList());
  }

  List<ManualSourceItem> get selectedItems =>
      all.where((e) => selectedIds.contains(e.id)).toList();

  // ===== 生成 Site 列表（html 不进 SourceManager）=====
  List<Map<String, dynamic>> buildSites() {
    final result = <Map<String, dynamic>>[];
    for (final item in all) {
      if (item.disabled) continue;
      if (item.type == ManualSourceType.html) continue;
      result.add(_toSite(item));
    }
    return result;
  }

  Map<String, dynamic> _toSite(ManualSourceItem item) {
    final key = 'manual_${item.type.name}_${item.name}';
    switch (item.type) {
      case ManualSourceType.py:
        return {
          'key': key,
          'name': '${item.name}(PY)',
          'api': item.path,
          'type': 3,
          'searchable': item.searchable,
          'filterable': item.filterable,
          'quickSearch': item.quickSearch,
          'lang': 'hipy',
          'ext': '',
        };
      case ManualSourceType.dr2:
        return {
          'key': key,
          'name': '${item.name}(DR2)',
          'api': 'assets://js/lib/drpy2/drpy2.min.js',
          'type': 3,
          'searchable': item.searchable,
          'filterable': item.filterable,
          'quickSearch': item.quickSearch,
          'lang': 'dr2',
          'ext': item.path,
        };
      case ManualSourceType.dr3:
        return {
          'key': key,
          'name': '${item.name}(DR3)',
          'api': item.path,
          'type': 3,
          'searchable': item.searchable,
          'filterable': item.filterable,
          'quickSearch': item.quickSearch,
          'lang': 'dr3',
          'ext': item.path,
        };
      case ManualSourceType.js:
        return {
          'key': 'catvod_$key',
          'name': '${item.name}(JS)',
          'api': item.path,
          'type': 3,
          'searchable': item.searchable,
          'filterable': item.filterable,
          'quickSearch': item.quickSearch,
          'lang': 'js',
          'ext': '',
        };
      case ManualSourceType.html:
        // 不会走到（buildSites 已过滤）
        return {
          'key': key,
          'name': '${item.name}(HTML)',
          'api': item.path,
          'type': 4,
          'searchable': 0,
          'filterable': 0,
          'quickSearch': 0,
          'lang': 'html',
          'ext': '',
        };
      case ManualSourceType.xbpq:
        return {
          'key': key,
          'name': '${item.name}(XBPQ)',
          'api': 'csp_XBPQ',
          'type': 3,
          'searchable': item.searchable,
          'filterable': item.filterable,
          'quickSearch': item.quickSearch,
          'lang': 'xbpq',
          'ext': item.path,
        };
      case ManualSourceType.xyq:
        return {
          'key': key,
          'name': '${item.name}(XYQ)',
          'api': 'csp_XYQHiker',
          'type': 3,
          'searchable': item.searchable,
          'filterable': item.filterable,
          'quickSearch': item.quickSearch,
          'lang': 'xyq',
          'ext': item.path,
        };
      case ManualSourceType.t4:
        return {
          'key': key,
          'name': '${item.name}(T4)',
          'api': item.path,
          'type': 4,
          'searchable': item.searchable,
          'filterable': item.filterable,
          'quickSearch': item.quickSearch,
          'lang': 't4',
          'ext': item.ext,
        };
    }
  }
}