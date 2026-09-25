import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

import '../models/lx_script_model.dart';
import '../services/lx_js_engine.dart';
import '../utils/lx_logger.dart';

/// 洛雪音乐自定义源控制器
class LxSourceController extends GetxController {
  final LxJsEngine _engine = LxJsEngine.instance;

  final RxList<LxScript> scripts = <LxScript>[].obs;
  final RxString currentScriptId = ''.obs;
  final RxBool isActive = false.obs;
  final RxBool isImporting = false.obs;

  @override
  void onInit() {
    super.onInit();
    // 延后到微任务，避免 initState/build 期间改 Rx 触发
    // "setState() called during build"
    Future.microtask(() => refreshScripts());

    _engine.eventStream.listen((_) => refreshScripts());
    _engine.stateStream.listen((_) {
      isActive.value = _engine.isActive;
      currentScriptId.value = _engine.currentScript?.id ?? '';
    });
  }

  void refreshScripts() {
    scripts.value = _engine.getAllScripts();
    isActive.value = _engine.isActive;
    currentScriptId.value = _engine.currentScript?.id ?? '';
  }

  // ==================== 导入 ====================

  Future<LxScript?> importFromFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['js', 'txt'],
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      if (file.path == null) return null;

      isImporting.value = true;
      final content = await File(file.path!).readAsString();
      final script = await _engine.importScript(content);
      refreshScripts();
      return script;
    } catch (e) {
      LxLogger.error('从文件导入失败: $e');
      rethrow;
    } finally {
      isImporting.value = false;
    }
  }

  Future<LxScript?> importFromContent(String content) async {
    if (content.trim().isEmpty) return null;
    isImporting.value = true;
    try {
      final script = await _engine.importScript(content);
      refreshScripts();
      return script;
    } catch (e) {
      LxLogger.error('从内容导入失败: $e');
      rethrow;
    } finally {
      isImporting.value = false;
    }
  }

  Future<LxScript?> importFromUrl(String url) async {
    if (url.trim().isEmpty) return null;
    isImporting.value = true;
    try {
      final script = await _engine.importScriptFromUrl(url.trim());
      refreshScripts();
      return script;
    } catch (e) {
      LxLogger.error('从 URL 导入失败: $e');
      rethrow;
    } finally {
      isImporting.value = false;
    }
  }

  // ==================== 激活/停用/删除 ====================

  Future<void> activate(String scriptId) async {
    try {
      await _engine.activateScript(scriptId);
      refreshScripts();
    } catch (e) {
      LxLogger.error('激活失败: $e');
      rethrow;
    }
  }

  Future<void> deactivate() async {
    await _engine.deactivateScript();
    refreshScripts();
  }

  Future<void> remove(String scriptId) async {
    await _engine.removeScript(scriptId);
    refreshScripts();
  }

  // ==================== 日志 ====================

  String get debugLogText => LxLogger.text;
  void clearLogs() => LxLogger.clear();
}