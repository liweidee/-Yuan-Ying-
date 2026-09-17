import 'dart:io';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

import '../models/ftp_entry.dart';
import '../services/ftp_service.dart';
import 'ftp_server_controller.dart';

enum FtpDownloadStatus { queued, downloading, completed, failed, cancelled }

class FtpDownloadItem {
  final String id;
  final String name;
  final String remotePath;
  final String serverId;
  FtpDownloadStatus status;
  double progress;
  int receivedBytes;
  int totalBytes;
  String? filePath;
  String? error;
  final DateTime createdAt;

  FtpDownloadItem({
    required this.id,
    required this.name,
    required this.remotePath,
    required this.serverId,
    this.status = FtpDownloadStatus.queued,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.filePath,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

class FtpDownloadController extends GetxController {
  final serverCtl = Get.find<FtpServerController>();

  final RxList<FtpDownloadItem> items = <FtpDownloadItem>[].obs;
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
    final dir = Directory('${doc.path}/ftp_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> addDownload(FtpEntry entry) async {
    final server = serverCtl.current;
    if (server == null) return;

    final id = '${server.id}_${entry.path}';
    if (items.any((i) => i.id == id)) {
      SmartDialog.showToast('已存在相同下载任务');
      return;
    }

    // 提前计算下载路径，赋给 filePath，
    //   让「取消 / 失败 / 清空」都能通过 filePath 找到待删文件
    final dlDir = await _resolveDownloadDir();
    final safe = entry.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final localPath = '$dlDir/$safe';

    final item = FtpDownloadItem(
      id: id,
      name: entry.name,
      remotePath: entry.path,
      serverId: server.id,
      totalBytes: entry.size,
      filePath: localPath,
    );
    items.insert(0, item);
    _start(item, server);
  }

  Future<void> _start(FtpDownloadItem item, dynamic server) async {
    item.status = FtpDownloadStatus.downloading;
    items.refresh();

    try {
      // 使用 addDownload 提前赋值的路径
      final localPath = item.filePath!;

      _cancelFlags[item.id] = false;

      await FtpService.instance.download(
        server: server,
        remotePath: item.remotePath,
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

      item.status = FtpDownloadStatus.completed;
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
        item.status = FtpDownloadStatus.cancelled;
      } else {
        item.status = FtpDownloadStatus.failed;
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

    // 手动查找（不依赖 collection 包）
    FtpDownloadItem? item;
    for (final i in items) {
      if (i.id == id) {
        item = i;
        break;
      }
    }

    if (item == null) {
      _cancelFlags.remove(id);
      return;
    }

    // 如果任务已经结束（completed/failed/cancelled），直接删文件和移除列表项
    if (item.status != FtpDownloadStatus.downloading &&
        item.status != FtpDownloadStatus.queued) {
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
  }

  Future<void> remove(FtpDownloadItem item) async {
    if (item.filePath != null) {
      try {
        final f = File(item.filePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    items.removeWhere((i) => i.id == item.id);
  }

  Future<void> retry(FtpDownloadItem item) async {
    try {
      final server =
          serverCtl.servers.firstWhere((s) => s.id == item.serverId);
      item.status = FtpDownloadStatus.queued;
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
      if (_cancelFlags.isNotEmpty) return;
      // 保守做法：不主动扫描全目录（避免误删用户手动放入的文件），
      // 只依赖每个任务的 catch 分支自行清理。
    });
  }

  List<FtpDownloadItem> get completedItems => items
      .where((i) =>
          i.status == FtpDownloadStatus.completed &&
          i.filePath != null &&
          File(i.filePath!).existsSync())
      .toList();
}