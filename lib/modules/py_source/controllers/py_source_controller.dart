// lib/modules/py_source/controllers/py_source_controller.dart

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../models/py_local_source.dart';
import '../services/py_source_meta_store.dart';
import '../services/py_source_scanner.dart';

class PySourceController extends GetxController {
  final RxList<PyLocalSource> sources = <PyLocalSource>[].obs;
  final RxBool loading = false.obs;
  final RxBool uploading = false.obs;
  final RxString search = ''.obs;

  final RxBool selectionMode = false.obs;
  final RxSet<String> selectedNames = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    refresh();
  }

  Future<void> refresh() async {
    loading.value = true;
    try {
      await PySourceMetaStore.ensureOpen();
      final metas = PySourceMetaStore.readAll();
      sources.assignAll(await PySourceScanner.scan(metaMap: metas));
      selectedNames.removeWhere(
        (n) => !sources.any((s) => s.name == n),
      );
    } catch (e) {
      SmartDialog.showToast('扫描失败: $e');
    } finally {
      loading.value = false;
    }
  }

  Future<void> pickAndUpload() async {
    if (uploading.value) return;
    uploading.value = true;
    try {
      int ok = 0;
      // 项目封装 pickFile 为单文件接口，一次选一个；如需多选再扩展
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['py'],
      );
      if (picked != null && picked.path != null) {
        final path = picked.path!;
        try {
          final bytes = await File(path).readAsBytes();
          await PySourceScanner.saveBytes(
            File(path).uri.pathSegments.last,
            bytes,
          );
          ok++;
        } catch (e) {
          print('[PySourceController] upload $path failed: $e');
        }
      }
      if (ok > 0) {
        SmartDialog.showToast('已上传 $ok 个 py 文件');
        await refresh();
      } else {
        // 用户取消也走这里，不弹失败提示
      }
    } finally {
      uploading.value = false;
    }
  }

  Future<void> deleteSource(PyLocalSource s) async {
    try {
      await PySourceScanner.delete(s.path);
      await PySourceMetaStore.remove(s.siteKey);
      await refresh();
      SmartDialog.showToast('已删除 ${s.name}.py');
    } catch (e) {
      SmartDialog.showToast('删除失败: $e');
    }
  }

  Future<void> deleteSelected() async {
    final names = List<String>.from(selectedNames);
    int ok = 0;
    for (final n in names) {
      // 手写查找，避免 RxList 与 collection 扩展解析问题
      PyLocalSource? s;
      for (final e in sources) {
        if (e.name == n) {
          s = e;
          break;
        }
      }
      if (s == null) continue;
      try {
        await PySourceScanner.delete(s.path);
        await PySourceMetaStore.remove(s.siteKey);
        ok++;
      } catch (_) {}
    }
    selectedNames.clear();
    selectionMode.value = false;
    await refresh();
    SmartDialog.showToast('已删除 $ok 个源');
  }

  void toggleSelection(String name) {
    if (selectedNames.contains(name)) {
      selectedNames.remove(name);
    } else {
      selectedNames.add(name);
    }
    if (selectedNames.isEmpty) selectionMode.value = false;
  }

  void enterSelection(String name) {
    selectionMode.value = true;
    if (name.isNotEmpty) selectedNames.add(name);
  }

  void exitSelection() {
    selectionMode.value = false;
    selectedNames.clear();
  }

  void selectAll() {
    selectedNames.assignAll(sources.map((s) => s.name).toList());
  }

  Future<void> saveSingleMeta(PyLocalSource s, PySourceMeta meta) async {
    await PySourceMetaStore.write(s.siteKey, meta);
    await refresh();
  }

  Future<void> batchApply({
    required List<PyLocalSource> targets,
    required bool searchable,
    required bool quickSearch,
    required bool filterable,
  }) async {
    for (final s in targets) {
      final base = s.meta ??
          PySourceMeta(
            name: s.name,
            title: s.header.title,
            searchable: s.header.searchable,
            filterable: s.header.filterable,
            quickSearch: s.header.quickSearch,
            ext: s.header.lang == 'hipy' ? '' : null,
          );
      final next = base.copyWith(
        searchable: searchable ? 1 : 0,
        filterable: filterable ? 1 : 0,
        quickSearch: quickSearch ? 1 : 0,
      );
      await PySourceMetaStore.write(s.siteKey, next);
    }
    await refresh();
    SmartDialog.showToast('已应用 ${targets.length} 个源');
  }

  Future<void> resetMeta(List<PyLocalSource> targets) async {
    for (final s in targets) {
      final old = s.meta;
      final next = PySourceMeta(
        name: s.name,
        title: s.header.title ?? s.name,
        searchable: s.header.searchable,
        filterable: s.header.filterable,
        quickSearch: s.header.quickSearch,
        ext: old?.ext,
      );
      await PySourceMetaStore.write(s.siteKey, next);
    }
    await refresh();
    SmartDialog.showToast('已重置 ${targets.length} 个源');
  }

  List<PyLocalSource> get filtered {
    final q = search.value.trim().toLowerCase();
    if (q.isEmpty) return sources;
    return sources.where((s) {
      final n = s.effectiveName.toLowerCase();
      final k = s.siteKey.toLowerCase();
      return n.contains(q) || k.contains(q);
    }).toList();
  }

  List<PyLocalSource> get selectedSources {
    return sources.where((s) => selectedNames.contains(s.name)).toList();
  }

  Future<String?> dirPath() async {
    try {
      final d = await PySourceScanner.hipyDir();
      return d.path;
    } catch (_) {
      return null;
    }
  }
}