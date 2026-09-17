import 'dart:io';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../services/emby_api_service.dart';

enum DownloadStatus { queued, downloading, completed, failed }

class DownloadItem {
  final String id; // 下载任务唯一ID，用itemId
  final String name;
  final String? imageTag;
  final String serverId;
  final String baseUrl;
  final String token;
  final DownloadStatus status;
  final double progress;
  final String? filePath;
  final int fileSize;
  final DateTime addedAt;

  DownloadItem({
    required this.id,
    required this.name,
    this.imageTag,
    required this.serverId,
    required this.baseUrl,
    required this.token,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.filePath,
    this.fileSize = 0,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageTag': imageTag,
        'serverId': serverId,
        'baseUrl': baseUrl,
        'token': token,
        'status': status.index,
        'progress': progress,
        'filePath': filePath,
        'fileSize': fileSize,
        'addedAt': addedAt.toIso8601String(),
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        id: json['id'] as String,
        name: json['name'] as String,
        imageTag: json['imageTag'] as String?,
        serverId: json['serverId'] as String,
        baseUrl: json['baseUrl'] as String,
        token: json['token'] as String,
        status: DownloadStatus.values[json['status'] as int],
        progress: (json['progress'] as num).toDouble(),
        filePath: json['filePath'] as String?,
        fileSize: json['fileSize'] as int? ?? 0,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}

class EmbyDownloadController extends GetxController {
  final RxList<DownloadItem> items = <DownloadItem>[].obs;
  final RxBool isLoading = false.obs;
  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};

  @override
  void onInit() {
    super.onInit();
    _loadFromStorage();
  }

  void _loadFromStorage() {
    final stored = StorageManager.getSetting<List<dynamic>>(
          EmbyStorageKeys.downloadList,
        ) ??
        [];

    // 不会替换 list 里的元素。改为显式构造新列表。
    // 同时清理残留文件（重启后正在下载的任务必然已中断）
    final newList = <DownloadItem>[];
    for (final e in stored) {
      var item = DownloadItem.fromJson(Map<String, dynamic>.from(e));

      if (item.status == DownloadStatus.downloading) {
        // 清理中断任务残留的部分文件
        if (item.filePath != null) {
          try {
            final f = File(item.filePath!);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
        // 状态降级为 failed
        item = DownloadItem(
          id: item.id,
          name: item.name,
          imageTag: item.imageTag,
          serverId: item.serverId,
          baseUrl: item.baseUrl,
          token: item.token,
          status: DownloadStatus.failed,
          progress: item.progress,
          filePath: item.filePath,
          fileSize: item.fileSize,
          addedAt: item.addedAt,
        );
      }
      newList.add(item);
    }

    items.value = newList;
    _saveToStorage();
  }

  void _saveToStorage() {
    final list = items.map((e) => e.toJson()).toList();
    StorageManager.setSetting(EmbyStorageKeys.downloadList, list);
  }

  Future<void> addDownload({
    required String itemId,
    required String name,
    String? imageTag,
    required String serverId,
    required String baseUrl,
    required String token,
  }) async {
    // 检查是否已存在
    if (items.any((i) => i.id == itemId && i.serverId == serverId)) {
      SmartDialog.showToast('已存在下载任务');
      return;
    }

    final item = DownloadItem(
      id: itemId,
      name: name,
      imageTag: imageTag,
      serverId: serverId,
      baseUrl: baseUrl,
      token: token,
      addedAt: DateTime.now(),
    );
    items.add(item);
    _saveToStorage();

    // 开始下载
    await _startDownload(item);
  }

  Future<void> _startDownload(DownloadItem item) async {
    final index =
        items.indexWhere((i) => i.id == item.id && i.serverId == item.serverId);
    if (index == -1) return;

    // ---- 生成下载路径（带时间戳，无法提前在 addDownload 里算）----
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/emby_downloads');
    if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
    final fileName =
        '${item.id}_${DateTime.now().millisecondsSinceEpoch}.media';
    final filePath = '${downloadDir.path}/$fileName';

    // 立即把 filePath 写入 items
    // 让后续 cancelDownload / clearAll 都能通过 item.filePath 找到文件
    items[index] = DownloadItem(
      id: item.id,
      name: item.name,
      imageTag: item.imageTag,
      serverId: item.serverId,
      baseUrl: item.baseUrl,
      token: item.token,
      status: DownloadStatus.downloading,
      progress: 0.0,
      filePath: filePath, // ← 提前赋值
      fileSize: 0,
      addedAt: item.addedAt,
    );
    _saveToStorage();

    final cancelToken = CancelToken();
    _cancelTokens['${item.id}_${item.serverId}'] = cancelToken;

    try {
      final url =
          EmbyApiService.getFileStreamUrl(item.baseUrl, item.id, item.token);
      await _dio.download(
        url,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            final idx = items.indexWhere(
                (i) => i.id == item.id && i.serverId == item.serverId);
            if (idx != -1) {
              items[idx] = DownloadItem(
                id: item.id,
                name: item.name,
                imageTag: item.imageTag,
                serverId: item.serverId,
                baseUrl: item.baseUrl,
                token: item.token,
                status: DownloadStatus.downloading,
                progress: progress,
                filePath: filePath,
                fileSize: total.toInt(),
                addedAt: item.addedAt,
              );
              _saveToStorage();
            }
          }
        },
      );

      // ---- 下载完成 ----
      final idx = items.indexWhere(
          (i) => i.id == item.id && i.serverId == item.serverId);
      if (idx != -1) {
        final current = items[idx];
        items[idx] = DownloadItem(
          id: current.id,
          name: current.name,
          imageTag: current.imageTag,
          serverId: current.serverId,
          baseUrl: current.baseUrl,
          token: current.token,
          status: DownloadStatus.completed,
          progress: 1.0,
          filePath: filePath,
          fileSize: await File(filePath).length(),
          addedAt: current.addedAt,
        );
        _saveToStorage();
      }
    } on DioException catch (e) {
      // 无论 cancel 还是其他错误，都清理已写入的文件
      // （此时 Dio 已释放文件句柄，删除能成功）
      try {
        final f = File(filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      final idx = items.indexWhere(
          (i) => i.id == item.id && i.serverId == item.serverId);

      // 列表项已被移除（例如用户在 cancelDownload 里已移除）→ 无需更新状态
      if (idx == -1) return;

      if (e.type == DioExceptionType.cancel) {
        // 保底：如果因时序原因没被移除，这里移除
        items.removeAt(idx);
      } else {
        // 其他失败：保留为 failed 状态供重试
        final current = items[idx];
        items[idx] = DownloadItem(
          id: current.id,
          name: current.name,
          imageTag: current.imageTag,
          serverId: current.serverId,
          baseUrl: current.baseUrl,
          token: current.token,
          status: DownloadStatus.failed,
          progress: current.progress,
          filePath: filePath, // 保留路径，便于用户手动检查
          fileSize: current.fileSize,
          addedAt: current.addedAt,
        );
      }
      _saveToStorage();
    } catch (e) {
      // 非 DioException 的其他异常（IO 等）
      try {
        final f = File(filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      final idx = items.indexWhere(
          (i) => i.id == item.id && i.serverId == item.serverId);
      if (idx != -1) {
        final current = items[idx];
        items[idx] = DownloadItem(
          id: current.id,
          name: current.name,
          imageTag: current.imageTag,
          serverId: current.serverId,
          baseUrl: current.baseUrl,
          token: current.token,
          status: DownloadStatus.failed,
          progress: current.progress,
          filePath: filePath,
          fileSize: current.fileSize,
          addedAt: current.addedAt,
        );
        _saveToStorage();
      }
    } finally {
      _cancelTokens.remove('${item.id}_${item.serverId}');
    }
  }

  /// 取消下载
  ///
  /// 只负责取消 token + 从列表移除。
  /// 文件删除交给 _startDownload 的 catch（避免文件仍被 Dio 占用时删除失败）。
  Future<void> cancelDownload(String itemId, String serverId) async {
    final key = '${itemId}_$serverId';
    _cancelTokens[key]?.cancel();
    _cancelTokens.remove(key);

    // 立即从列表移除（用户视觉上任务消失）
    items.removeWhere((i) => i.id == itemId && i.serverId == serverId);
    _saveToStorage();
  }

  Future<void> retryDownload(String itemId, String serverId) async {
    final index =
        items.indexWhere((i) => i.id == itemId && i.serverId == serverId);
    if (index == -1) return;
    final item = items[index];
    if (item.status == DownloadStatus.failed) {
      // 删除旧文件（如果还有残留）
      if (item.filePath != null && await File(item.filePath!).exists()) {
        await File(item.filePath!).delete();
      }
      // 重置状态并重新开始
      final newItem = DownloadItem(
        id: item.id,
        name: item.name,
        imageTag: item.imageTag,
        serverId: item.serverId,
        baseUrl: item.baseUrl,
        token: item.token,
        addedAt: item.addedAt,
      );
      items[index] = newItem;
      _saveToStorage();
      await _startDownload(newItem);
    }
  }

  Future<void> removeCompleted(String itemId, String serverId) async {
    final index =
        items.indexWhere((i) => i.id == itemId && i.serverId == serverId);
    if (index == -1) return;
    final item = items[index];
    if (item.filePath != null && await File(item.filePath!).exists()) {
      await File(item.filePath!).delete();
    }
    items.removeAt(index);
    _saveToStorage();
  }

  /// 清空全部（含下载中的任务，会先取消）
  /// 用于用户明确选择「取消并清空全部」
  Future<void> clearAll() async {
    // 1. 取消所有正在下载的任务
    //    它们的 token.cancel 会让 Dio 抛 cancel 异常，
    //    走 _startDownload 的 catch 里删除对应文件
    final activeTokens = Map<String, CancelToken>.from(_cancelTokens);
    for (final token in activeTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();

    // 2. 遍历删除所有文件（filePath 现在一定有值，
    //    因为 _startDownload 已提前赋值）
    for (final item in items) {
      if (item.filePath != null) {
        try {
          final file = File(item.filePath!);
          if (await file.exists()) await file.delete();
        } catch (_) {
          // 文件可能仍被 Dio 写入流占用，交给 catch 处理
        }
      }
    }

    // 3. 清空列表和存储
    items.clear();
    _saveToStorage();
  }

  /// 只清空已结束的任务（completed / failed）
  /// 用于用户选择「仅清空已完成」，不动正在下载/排队的任务
  Future<void> clearAllFinished() async {
    final toRemove = items
        .where((i) =>
            i.status == DownloadStatus.completed ||
            i.status == DownloadStatus.failed)
        .toList();

    for (final item in toRemove) {
      if (item.filePath != null) {
        try {
          final f = File(item.filePath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }

    items.removeWhere((i) =>
        i.status == DownloadStatus.completed ||
        i.status == DownloadStatus.failed);
    _saveToStorage();
  }

  @override
  void onClose() {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    super.onClose();
  }
}