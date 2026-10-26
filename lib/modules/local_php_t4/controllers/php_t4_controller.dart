// lib/modules/local_php_t4/controllers/php_t4_controller.dart

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/plugin_center/widgets/service_log_sheet.dart';

import '../models/php_t4_source.dart';
import '../services/php_t4_scanner.dart';
import '../services/php_t4_service.dart';

class PhpT4Controller extends GetxController {
  final RxList<PhpT4Source> sources = <PhpT4Source>[].obs;
  final RxBool loading = false.obs;
  final RxBool uploading = false.obs;
  final RxBool starting = false.obs;
  final RxBool stopping = false.obs;
  final RxString search = ''.obs;
  final RxBool hasSkeleton = false.obs;
  final RxList<String> missingFiles = <String>[].obs;

  /// 用户指定端口（0 = 自动分配）
  final RxInt preferredPort = 0.obs;

  @override
  void onInit() {
    super.onInit();
    preferredPort.value = PhpT4Service.getPreferredPort() ?? 0;
    refresh();
  }

  /// 刷新列表 + 骨架完整性 + 端口设置
  Future<void> refresh() async {
    loading.value = true;
    try {
      sources.assignAll(await PhpT4Scanner.scan());
      final missing = await PhpT4Scanner.missingSkeletonFiles();
      missingFiles.assignAll(missing);
      hasSkeleton.value = missing.isEmpty;
      preferredPort.value = PhpT4Service.getPreferredPort() ?? 0;
    } catch (e) {
      SmartDialog.showToast('扫描失败：$e');
    } finally {
      loading.value = false;
    }
  }

  /// 搜索结果
  List<PhpT4Source> get filtered {
    final q = search.value.trim().toLowerCase();
    if (q.isEmpty) return sources;
    return sources
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.fileName.toLowerCase().contains(q))
        .toList();
  }

  /// 设置用户指定端口（传 null = 自动分配）
  Future<void> setPreferredPort(int? port) async {
    await PhpT4Service.setPreferredPort(port);
    preferredPort.value = port ?? 0;
  }

  // ===== 目录 / 上传 / 删除 =====

  Future<String> dirPath() async {
    try {
      return (await PhpT4Scanner.dir()).path;
    } catch (_) {
      return '';
    }
  }

  Future<void> openDir() async {
    final path = await dirPath();
    if (path.isEmpty) return;
    try {
      if (Platform.isAndroid) {
        SmartDialog.showToast('目录：$path');
        return;
      }
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      SmartDialog.showToast('打开目录失败：$e');
    }
  }

  Future<void> pickAndUpload() async {
    if (uploading.value) return;

    final missing = await PhpT4Scanner.missingSkeletonFiles();
    if (missing.isNotEmpty) {
      missingFiles.assignAll(missing);
      hasSkeleton.value = false;
      SmartDialog.showToast(
        'PHP-T4 骨架未安装或缺失 ${missing.length} 个文件'
        '（${missing.take(3).join('、')}${missing.length > 3 ? '…' : ''}），'
        '请先把完整骨架包放入源目录后再上传源文件',
      );
      return;
    }

    uploading.value = true;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['php'],
      );
      if (picked == null || picked.path == null) return;
      final path = picked.path!;
      final bytes = await File(path).readAsBytes();
      final saved = await PhpT4Scanner.saveBytes(
        File(path).uri.pathSegments.last,
        bytes,
      );
      SmartDialog.showToast(
          '已上传到 ${saved.split(Platform.pathSeparator).last}');
      await refresh();
    } catch (e) {
      SmartDialog.showToast('上传失败：$e');
    } finally {
      uploading.value = false;
    }
  }

  Future<void> deleteSource(PhpT4Source s) async {
    try {
      await PhpT4Scanner.delete(s.path);
      await refresh();
      SmartDialog.showToast('已删除 ${s.fileName}');
    } catch (e) {
      SmartDialog.showToast('删除失败：$e');
    }
  }

  // ===== 服务控制 =====

  Future<void> startService() async {
    if (starting.value || PhpT4Service.isRunning) return;

    final err = PhpT4Service.checkRuntime();
    if (err != null) {
      SmartDialog.showToast(err);
      return;
    }

    final missing = await PhpT4Scanner.missingSkeletonFiles();
    if (missing.isNotEmpty) {
      missingFiles.assignAll(missing);
      hasSkeleton.value = false;
      SmartDialog.showToast(
        'PHP-T4 骨架包不完整（缺少 ${missing.length} 个文件），无法启动服务',
      );
      return;
    }

    starting.value = true;
    try {
      final port = await PhpT4Service.start();
      SmartDialog.showToast('PHP-T4 服务已启动（端口 $port）');
    } catch (e) {
      SmartDialog.showToast('$e');
    } finally {
      starting.value = false;
    }
  }

  Future<void> stopService() async {
    if (stopping.value || !PhpT4Service.isRunning) return;
    stopping.value = true;
    try {
      await PhpT4Service.stop();
      SmartDialog.showToast('PHP-T4 服务已停止');
    } catch (e) {
      SmartDialog.showToast('停止失败：$e');
    } finally {
      stopping.value = false;
    }
  }

  Future<void> copyConfigUrl() async {
    final port = PhpT4Service.currentPort;
    if (!PhpT4Service.isRunning || port == null) {
      SmartDialog.showToast('服务未运行，无法获取地址');
      return;
    }
    try {
      final ip = await PhpT4Service.localIp();
      final url = PhpT4Service.configUrl(ip: ip, port: port);
      await Clipboard.setData(ClipboardData(text: url));
      SmartDialog.showToast('已复制：$url');
    } catch (e) {
      SmartDialog.showToast('复制失败：$e');
    }
  }

  /// 显示服务日志（复用插件中心的日志弹窗）
  Future<void> showLogs() async {
    final context = Get.context;
    if (context == null) return;
    final config = await PhpT4Service.buildConfigForLog();
    await showServiceLogSheet(context, config);
  }
}