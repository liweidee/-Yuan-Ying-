// lib/modules/plugin_center/widgets/service_import_export.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/utils/platform_utils.dart';

/// 导出所有服务配置到 JSON 文件
Future<void> exportAllServices() async {
  try {
    final all = ServiceManager.instance.getAll();
    if (all.isEmpty) {
      SmartDialog.showToast('暂无服务可导出');
      return;
    }
    final list = all.map((e) => e.toJson()).toList();
    final json = const JsonEncoder.withIndent('  ').convert(list);
    final bytes = Uint8List.fromList(utf8.encode(json));

    final uri = await FilePicker.saveFile(
      fileName: 'services.json',
      bytes: PlatformUtils.isDesktop ? Uint8List(0) : bytes,
    );
    if (uri == null) return;
    if (PlatformUtils.isDesktop) {
      await File(uri.toFilePath()).writeAsBytes(bytes, flush: true);
    }
    SmartDialog.showToast('已导出 ${all.length} 个服务');
  } catch (e) {
    SmartDialog.showToast('导出失败：$e');
  }
}

/// 从 JSON 文件导入服务配置
Future<void> importServices() async {
  try {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null || file.path == null) return;

    final content = await File(file.path!).readAsString();
    final decoded = jsonDecode(content);

    List<dynamic> rawList;
    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map && decoded['services'] is List) {
      rawList = decoded['services'] as List;
    } else {
      SmartDialog.showToast('格式错误：期望服务数组');
      return;
    }

    final existing = ServiceManager.instance.getAll();
    final existingIds = existing.map((e) => e.id).toSet();
    int added = 0;
    int skipped = 0;

    for (final item in rawList) {
      if (item is! Map) continue;
      try {
        final cfg = ServiceConfig.fromJson(Map<String, dynamic>.from(item));
        if (cfg.id.isEmpty) continue;
        if (existingIds.contains(cfg.id)) {
          skipped++;
          continue;
        }
        // 导入时给新 id，避免冲突（用户可能已删除同 id 服务）
        final newId = 'svc-${DateTime.now().millisecondsSinceEpoch}-${added}';
        final copy = ServiceConfig(
          id: newId,
          name: cfg.name,
          port: cfg.port,
          runtime: cfg.runtime,
          args: cfg.args,
          cwd: cfg.cwd,
          autostart: false,
          keepForeground: false,
          env: cfg.env,
          maxRestart: cfg.maxRestart,
          executable: cfg.executable,
          healthType: cfg.healthType,
          healthPath: cfg.healthPath,
          pidFile: cfg.pidFile,
        );
        await ServiceManager.instance.addOrUpdate(copy);
        added++;
      } catch (_) {
        skipped++;
      }
    }

    if (added > 0) {
      SmartDialog.showToast('已导入 $added 个服务${skipped > 0 ? "，跳过 $skipped 个" : ""}');
    } else {
      SmartDialog.showToast('没有可导入的服务');
    }
  } catch (e) {
    SmartDialog.showToast('导入失败：$e');
  }
}