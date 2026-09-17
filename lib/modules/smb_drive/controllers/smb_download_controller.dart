import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

import '../models/smb_entry.dart';
import '../services/smb_service.dart';
import 'smb_file_controller.dart';
import 'smb_server_controller.dart';

enum SmbDownloadStatus { queued, downloading, completed, failed, cancelled }

class SmbDownloadItem {
  final String id;
  final String name;
  final String share;
  final String remotePath; // 相对路径
  final String serverId;
  SmbDownloadStatus status;
  double progress;
  int receivedBytes;
  int totalBytes;
  String? filePath;
  String? error;
  final DateTime createdAt;

  SmbDownloadItem({
    required this.id,
    required this.name,
    required this.share,
    required this.remotePath,
    required this.serverId,
    this.status = SmbDownloadStatus.queued,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.filePath,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

class SmbDownloadController extends GetxController {
  final serverCtl = Get.find<SmbServerController>();

  final RxList<SmbDownloadItem> items = <SmbDownloadItem>[].obs;
  final Map<String, bool> _cancelFlags = {};

  Future<String> _resolveDownloadDir() async {
    final custom =
        StorageManager.getSetting<String>(SettingBoxKey.downloadPath);
    if (custom != null && custom.isNotEmpty) {
      final dir = Directory(custom);
      if (!await dir.exists()) await dir.create(recursive: true);
      return custom;
    }
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory('${doc.path}/smb_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> addDownload(SmbEntry entry) async {
    final server = serverCtl.current;
    final fileCtl = Get.find<SmbFileController>();
    if (server == null || fileCtl.atShareList) return;

    final id = '${server.id}_${fileCtl.currentShare.value}_${entry.path}';
    if (items.any((i) => i.id == id)) {
      SmartDialog.showToast('已存在相同下载任务');
      return;
    }

    // 提前计算下载路径，赋给 filePath，
    //   让「取消 / 失败 / 清空」都能通过 filePath 找到待删文件
    final dlDir = await _resolveDownloadDir();
    final safe = entry.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final localPath = '$dlDir/$safe';

    final item = SmbDownloadItem(
      id: id,
      name: entry.name,
      share: fileCtl.currentShare.value,
      remotePath: entry.path,
      serverId: server.id,
      totalBytes: entry.size,
      filePath: localPath,
    );
    items.insert(0, item);
    _start(item, server);
  }

  Future<void> _start(SmbDownloadItem item, dynamic server) async {
    item.status = SmbDownloadStatus.downloading;
    items.refresh();

    try {
      // 使用 addDownload 提前赋值的路径
      final localPath = item.filePath!;

      _cancelFlags[item.id] = false;

      await SmbService.instance.download(
        server: server,
        share: item.share,
        relativePath: item.remotePath,
        localPath: localPath,
        onProgress: (received, total) {
          if (_cancelFlags[item.id] == true) {
            throw Exception('cancelled');
          }
          item.receivedBytes = received;
          if (total > 0) {
            item.totalBytes = total;
            item.progress = received / total;
          }
          items.refresh();
        },
      );

      item.status = SmbDownloadStatus.completed;
      item.progress = 1;
      items.refresh();
    } catch (e) {
      // 关键：无论取消还是失败，都要清理已写入的部分文件
      //   此时下载流已关闭，删除能成功（不会文件占用）
      try {
        final f = File(item.filePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      if (_cancelFlags[item.id] == true) {
        item.status = SmbDownloadStatus.cancelled;
      } else {
        item.status = SmbDownloadStatus.failed;
        item.error = '$e';
      }
      items.refresh();
    } finally {
      _cancelFlags.remove(item.id);
    }
  }

  Future<void> cancel(String id) async {
    // 只设置取消标志，让 _start 的 catch 统一处理文件清理和状态更新
    //   避免在文件仍被占用时删除（Windows 上会失败）
    _cancelFlags[id] = true;

    final item = items.firstWhereOrNull((i) => i.id == id);
    if (item == null) {
      // 任务已经不在列表里（异常情况），清掉标志
      _cancelFlags.remove(id);
      return;
    }

    // 如果任务已经结束（completed/failed/cancelled），直接删文件和移除列表项
    if (item.status != SmbDownloadStatus.downloading &&
        item.status != SmbDownloadStatus.queued) {
      if (item.filePath != null) {
        try {
          final f = File(item.filePath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      items.removeWhere((i) => i.id == id);
      _cancelFlags.remove(id);
    }
    // 下载中的任务：不动列表，由 _start 的 catch 处理（会改为 cancelled 状态）
    // 用户视觉上：任务仍在列表，但状态迅速变为"已取消"
  }

  Future<void> remove(SmbDownloadItem item) async {
    if (item.filePath != null) {
      try {
        final f = File(item.filePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    items.removeWhere((i) => i.id == item.id);
  }

  Future<void> retry(SmbDownloadItem item) async {
    try {
      final server =
          serverCtl.servers.firstWhere((s) => s.id == item.serverId);
      item.status = SmbDownloadStatus.queued;
      item.progress = 0;
      item.receivedBytes = 0;
      item.error = null;
      items.refresh();
      await _start(item, server);
    } catch (_) {
      SmartDialog.showToast('服务器已被删除');
    }
  }

  Future<void> clearAll() async {
    // 1. 标记所有正在下载的任务为取消（让它们的协程抛异常，走 catch 清理）
    for (final id in _cancelFlags.keys.toList()) {
      _cancelFlags[id] = true;
    }

    // 2. 遍历所有 item（filePath 现在总是有值），删除文件
    for (final item in items) {
      if (item.filePath != null) {
        try {
          final f = File(item.filePath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }

    // 3. 清空列表
    items.clear();

    // 4. 稍等片刻再清理一次 —— 覆盖"正在下载"的任务：
    //    这些任务的下载协程被 _cancelFlags 中断后会走 catch，
    //    那里也会删一次文件；但 catch 是异步的，此处的清理
    //    在它们之前执行可能失败（文件占用），等它们跑完再试一次。
    Future.delayed(const Duration(milliseconds: 800), () async {
      // 无人引用的 _cancelFlags 已经清空，说明所有下载协程都已结束
      if (_cancelFlags.isNotEmpty) return;
      // 保守做法：不主动扫描全目录（避免误删用户手动放入的文件），
      // 只依赖每个任务的 catch 分支自行清理。
    });
  }

  List<SmbDownloadItem> get completedItems => items
      .where((i) =>
          i.status == SmbDownloadStatus.completed &&
          i.filePath != null &&
          File(i.filePath!).existsSync())
      .toList();
}