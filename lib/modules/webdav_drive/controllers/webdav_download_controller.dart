import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

import '../models/webdav_entry.dart';
import '../services/webdav_service.dart';
import 'webdav_server_controller.dart';

enum WebDavDownloadStatus { queued, downloading, completed, failed, cancelled }

class WebDavDownloadItem {
  final String id;
  final String name;
  final String remotePath;
  final String serverId;
  WebDavDownloadStatus status;
  double progress;
  int receivedBytes;
  int totalBytes;
  String? filePath;
  String? error;
  final DateTime createdAt;

  WebDavDownloadItem({
    required this.id,
    required this.name,
    required this.remotePath,
    required this.serverId,
    this.status = WebDavDownloadStatus.queued,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.filePath,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

class WebDavDownloadController extends GetxController {
  final serverCtl = Get.find<WebDavServerController>();

  final RxList<WebDavDownloadItem> items = <WebDavDownloadItem>[].obs;
  final Map<String, CancelToken> _tokens = {};

  /// 解析下载目录：优先用设置中的自定义路径，否则用应用文档目录
  Future<String> _resolveDownloadDir() async {
    final custom = StorageManager.getSetting<String>(
      SettingBoxKey.downloadPath,
    );
    if (custom != null && custom.isNotEmpty) {
      final dir = Directory(custom);
      if (!await dir.exists()) await dir.create(recursive: true);
      return custom;
    }
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory('${doc.path}/webdav_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// 加入下载队列
  Future<void> addDownload(WebDavEntry entry) async {
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

    final item = WebDavDownloadItem(
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

  Future<void> _start(WebDavDownloadItem item, dynamic server) async {
    item.status = WebDavDownloadStatus.downloading;
    items.refresh();

    try {
      // 使用 addDownload 提前赋值的路径
      final localPath = item.filePath!;

      final token = CancelToken();
      _tokens[item.id] = token;

      await WebDavService.instance.download(
        server: server,
        remotePath: item.remotePath,
        localPath: localPath,
        cancelToken: token,
        onProgress: (received, total) {
          item.receivedBytes = received;
          if (total > 0) {
            item.totalBytes = total;
            item.progress = received / total;
          }
          items.refresh();
        },
      );

      item.status = WebDavDownloadStatus.completed;
      item.progress = 1;
      items.refresh();
    } catch (e) {
      // 关键：无论取消还是失败，都要清理已写入的部分文件
      //   此时下载流已关闭（Dio 已释放连接），删除能成功
      try {
        final f = File(item.filePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      if (e is DioException && e.type == DioExceptionType.cancel) {
        item.status = WebDavDownloadStatus.cancelled;
      } else {
        item.status = WebDavDownloadStatus.failed;
        item.error = '$e';
      }
      items.refresh();
    } finally {
      _tokens.remove(item.id);
    }
  }

  /// 取消单个任务
  ///
  /// 分两种情况：
  /// - **下载中**：调用 token.cancel()，让 Dio 抛取消异常，
  ///   由 _start 的 catch 统一清理文件 + 更新状态（避免文件仍被占用时删除失败）
  /// - **已结束**（completed/failed/cancelled）：直接删文件 + 移除列表项
  Future<void> cancel(String id) async {
    // 手动查找
    WebDavDownloadItem? item;
    for (final i in items) {
      if (i.id == id) {
        item = i;
        break;
      }
    }

    if (item == null) {
      // 任务已经不在列表，但可能 token 还残留
      _tokens.remove(id)?.cancel();
      return;
    }

    // ---- 下载中：交给 _start 的 catch 处理 ----
    if (item.status == WebDavDownloadStatus.downloading ||
        item.status == WebDavDownloadStatus.queued) {
      _tokens[id]?.cancel();
      // 不在这里删除文件，因为文件仍被 Dio 写入流占用，
      // 交给 _start 的 catch 统一处理
      return;
    }

    // ---- 已结束：直接清理 ----
    _tokens.remove(id)?.cancel(); // 兜底：万一 token 还在
    if (item.filePath != null) {
      try {
        final f = File(item.filePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    items.removeWhere((i) => i.id == id);
  }

  /// 移除单个已完成/失败项（会删除已下载的文件）
  Future<void> remove(WebDavDownloadItem item) async {
    if (item.filePath != null) {
      try {
        final f = File(item.filePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    items.removeWhere((i) => i.id == item.id);
  }

  /// 重试失败的任务
  Future<void> retry(WebDavDownloadItem item) async {
    try {
      final server =
          serverCtl.servers.firstWhere((s) => s.id == item.serverId);
      item.status = WebDavDownloadStatus.queued;
      item.progress = 0;
      item.receivedBytes = 0;
      item.error = null;
      items.refresh();
      await _start(item, server);
    } catch (_) {
      SmartDialog.showToast('服务器已被删除');
    }
  }

  /// 清空所有下载任务，并删除已下载的文件
  Future<void> clearAll() async {
    // 1. 取消所有进行中的任务（让它们的协程抛取消异常，走 catch 清理）
    final activeTokens = Map<String, CancelToken>.from(_tokens);
    for (final t in activeTokens.values) {
      t.cancel();
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
    _tokens.clear();

    // 4. 稍等片刻再清理一次 —— 覆盖"正在下载"的任务：
    //    这些任务的 Dio 请求被取消后会走 catch，
    //    那里也会删一次文件；但 catch 是异步的，此处的清理
    //    在它们之前执行可能失败（文件占用），等它们跑完再试一次。
    Future.delayed(const Duration(milliseconds: 800), () async {
      if (_tokens.isNotEmpty) return;
      // 保守做法：不主动扫描全目录（避免误删用户手动放入的文件），
      // 只依赖每个任务的 catch 分支自行清理。
    });
  }

  /// 已下载成功的本地文件列表（用于详情页剧集面板）
  List<WebDavDownloadItem> get completedItems => items
      .where((i) =>
          i.status == WebDavDownloadStatus.completed &&
          i.filePath != null &&
          File(i.filePath!).existsSync())
      .toList();

  @override
  void onClose() {
    for (final t in _tokens.values) {
      t.cancel();
    }
    super.onClose();
  }
}