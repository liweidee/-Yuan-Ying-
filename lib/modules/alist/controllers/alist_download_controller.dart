import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../models/alist_download_record.dart';
import '../services/alist_download_manager.dart';
import '../services/alist_download_task_status.dart';
import '../services/alist_file_utils.dart';

/// 下载项 UI 模型
class AlistDownloadItem {
  final AlistDownloadRecord record;
  final RxString status;
  final Rx<AlistDownloadTaskStatus> downloadStatus;
  final RxString savedPath;
  int downloaded;
  int? contentLength;
  final Map<String, dynamic> requestHeaders;

  AlistDownloadItem({
    required this.record,
    required this.status,
    required this.downloadStatus,
    required this.savedPath,
    this.downloaded = 0,
    this.contentLength,
    this.requestHeaders = const {},
  });

  String get name => record.name;
  String? get thumbnail => record.thumbnail;
  String? get remotePath => record.remotePath;
  String? get sign => record.sign;
  int get limitFrequency => record.limitFrequency ?? 0;
  String get id => record.id;
}

class AlistDownloadController extends GetxController {
  final downloadList = <AlistDownloadItem>[].obs;
  late StreamSubscription _progressSub;
  late StreamSubscription _statusSub;
  final isMenuOpen = false.obs;

  @override
  void onInit() {
    super.onInit();
    _findDownloadList();
    _progressSub =
        AlistDownloadManager.instance.listenDownloadProgressChange((task) {
      if (task.status != AlistDownloadTaskStatus.downloading) return;
      final item = downloadList.firstWhereOrNull(
          (e) => e.savedPath.value == task.record.localPath);
      if (item != null) {
        item.downloadStatus.value = task.status;
        item.downloaded = task.downloaded;
        item.contentLength = task.contentLength;
        item.status.value = _statusText(
          '下载中',
          task.downloaded,
          task.contentLength,
        );
      }
    });

    _statusSub =
        AlistDownloadManager.instance.listenDownloadStatusChange((task) {
      final item = downloadList.firstWhereOrNull(
          (e) => e.savedPath.value == task.record.localPath);
      if (item == null) return;
      item.downloadStatus.value = task.status;
      switch (task.status) {
        case AlistDownloadTaskStatus.finished:
          var status = '下载完毕';
          if (File(task.record.localPath).existsSync()) {
            final size = File(task.record.localPath).lengthSync();
            status = '$status - ${AlistFileUtils.formatBytes(size)}';
          }
          item.status.value = status;
          break;
        case AlistDownloadTaskStatus.failed:
          item.status.value = '下载失败(${task.failedReason ?? ""})';
          break;
        case AlistDownloadTaskStatus.paused:
          item.status.value =
              _statusText('已暂停', task.downloaded, task.contentLength);
          break;
        case AlistDownloadTaskStatus.waiting:
          item.status.value =
              _statusText('等待中', task.downloaded, task.contentLength);
          break;
        case AlistDownloadTaskStatus.downloading:
          item.status.value = _statusText(
            '下载中',
            task.downloaded,
            task.contentLength ?? item.contentLength,
          );
          break;
        case AlistDownloadTaskStatus.decompressing:
          item.status.value = '解压中...';
          break;
        case AlistDownloadTaskStatus.canceled:
          item.status.value =
              _statusText('已取消', task.downloaded, task.contentLength);
          break;
      }
    });
  }

  String _statusText(String base, int downloaded, int? total) {
    if (downloaded <= 0) return base;
    if (total != null && total > 0) {
      return '$base - ${AlistFileUtils.formatBytes(downloaded)}/${AlistFileUtils.formatBytes(total)}';
    }
    return '$base - ${AlistFileUtils.formatBytes(downloaded)}';
  }

  @override
  void onClose() {
    _progressSub.cancel();
    _statusSub.cancel();
    super.onClose();
  }

  Future<void> _findDownloadList() async {
    final all = await _loadAllRecords();
    if (all.isEmpty) {
      downloadList.clear();
      return;
    }
    final manager = AlistDownloadManager.instance;
    final list = <AlistDownloadItem>[];
    for (final record in all) {
      final tmpFile = File('${record.localPath}.tmp');
      final infoFile = File('${record.localPath}.downloads');
      int? contentLength;
      int downloaded = 0;
      if (tmpFile.existsSync() || infoFile.existsSync()) {
        contentLength = await _readContentLength(infoFile);
      }
      if (tmpFile.existsSync()) {
        downloaded = tmpFile.lengthSync();
      }

      String status;
      AlistDownloadTaskStatus downloadStatus;
      if (record.finished) {
        downloadStatus = AlistDownloadTaskStatus.finished;
        status = '下载完毕';
        if (File(record.localPath).existsSync()) {
          status =
              '$status - ${AlistFileUtils.formatBytes(File(record.localPath).lengthSync())}';
        }
      } else if (downloaded > 0) {
        downloadStatus = AlistDownloadTaskStatus.paused;
        status = _statusText('已暂停', downloaded, contentLength);
      } else {
        downloadStatus = AlistDownloadTaskStatus.paused;
        status = '已暂停';
      }

      Map<String, dynamic> headers = {};
      if (record.requestHeaders != null && record.requestHeaders!.isNotEmpty) {
        try {
          headers =
              jsonDecode(record.requestHeaders!) as Map<String, dynamic>;
        } catch (_) {}
      }

      list.add(AlistDownloadItem(
        record: record,
        status: status.obs,
        downloadStatus: downloadStatus.obs,
        savedPath: record.localPath.obs,
        downloaded: downloaded,
        contentLength: contentLength,
        requestHeaders: headers,
      ));
    }
    downloadList.value = list;
  }

  Future<List<AlistDownloadRecord>> _loadAllRecords() async {
    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.downloadRecords,
        ) ??
        [];
    return raw
        .map((e) => AlistDownloadRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<int?> _readContentLength(File file) async {
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return json['contentLength'] as int?;
    } catch (_) {
      return null;
    }
  }

  void download(AlistDownloadItem item) {
    AlistDownloadManager.instance.enqueue(
      name: item.name,
      remotePath: item.remotePath ?? '',
      sign: item.sign ?? '',
      thumb: item.thumbnail,
      requestHeaders: item.requestHeaders,
      limitFrequency: item.limitFrequency,
    );
  }

  void pause(AlistDownloadItem item) {
    AlistDownloadManager.instance.pause(item.savedPath.value);
  }

  Future<void> delete(AlistDownloadItem item) async {
    AlistDownloadManager.instance.cancel(item.savedPath.value);
    downloadList.removeWhere((e) => e.id == item.id);

    await AlistDownloadManager.instance.deleteRecord(item.record);

    final savedFile = File(item.savedPath.value);
    if (savedFile.existsSync()) savedFile.deleteSync();
    final tmpFile = File('${item.savedPath.value}.tmp');
    if (tmpFile.existsSync()) tmpFile.deleteSync();
    final infoFile = File('${item.savedPath.value}.downloads');
    if (infoFile.existsSync()) infoFile.deleteSync();
  }

  void onMenuSelected(String value) {
    switch (value) {
      case 'startAll':
        _startAll();
        break;
      case 'pauseAll':
        _pauseAll();
        break;
      case 'setMax':
        _showSetMaxDialog();
        break;
    }
  }

  void _startAll() {
    final list = downloadList.toList()..sort((a, b) {
      return a.record.createTime.compareTo(b.record.createTime);
    });
    for (final item in list) {
      if (item.downloadStatus.value == AlistDownloadTaskStatus.waiting ||
          item.downloadStatus.value == AlistDownloadTaskStatus.downloading ||
          item.downloadStatus.value ==
              AlistDownloadTaskStatus.decompressing ||
          item.downloadStatus.value == AlistDownloadTaskStatus.finished) {
        continue;
      }
      AlistDownloadManager.instance.enqueue(
        name: item.name,
        remotePath: item.remotePath ?? '',
        sign: item.sign ?? '',
        thumb: item.thumbnail,
        requestHeaders: item.requestHeaders,
        limitFrequency: item.limitFrequency,
      );
    }
  }

  void _pauseAll() {
    for (final item in downloadList) {
      if (item.downloadStatus.value == AlistDownloadTaskStatus.waiting ||
          item.downloadStatus.value == AlistDownloadTaskStatus.downloading ||
          item.downloadStatus.value ==
              AlistDownloadTaskStatus.decompressing) {
        AlistDownloadManager.instance.pause(item.savedPath.value);
      }
    }
  }

  void _showSetMaxDialog() {
    final current = AlistDownloadManager.instance.maxRunningTaskCount;
    final options = List.generate(20, (i) => i + 1);
    showModalBottomSheet(
      context: Get.context!,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('最大同时下载数',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final n = options[i];
                  return ListTile(
                    title: Text('$n'),
                    trailing: n == current
                        ? const Icon(Icons.check, color: Colors.blue)
                        : null,
                    onTap: () {
                      AlistDownloadManager.instance.setMaxRunningTaskCount(n);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 保存到本地（桌面端用 FilePicker）
  Future<void> saveToLocal(AlistDownloadItem item) async {
    if (item.downloadStatus.value != AlistDownloadTaskStatus.finished) return;
    try {
      final srcFile = File(item.savedPath.value);
      if (!srcFile.existsSync()) {
        SmartDialog.showToast('文件不存在');
        return;
      }
      SmartDialog.showToast('已保存：${item.savedPath.value}');
    } catch (e) {
      SmartDialog.showToast('保存失败: $e');
    }
  }
}