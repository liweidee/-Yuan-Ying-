import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../controllers/alist_server_controller.dart';
import '../controllers/alist_user_controller.dart';
import '../models/alist_download_record.dart';
import 'alist_download_http_client.dart';
import 'alist_download_task.dart';
import 'alist_download_task_status.dart';
import 'alist_file_utils.dart';

class AlistDownloadManager {
  static final AlistDownloadManager instance = AlistDownloadManager._();
  AlistDownloadManager._();

  final AlistDownloadHttpClient _httpClient = AlistDownloadHttpClient();
  final Queue<AlistDownloadTask> _waitingTasks = Queue();
  final Queue<AlistDownloadTask> _runningTasks = Queue();
  final _statusController = StreamController<AlistDownloadTask>.broadcast();
  final _progressController = StreamController<AlistDownloadTask>.broadcast();

  var _maxRunningTaskCount = 3;
  Timer? _progressTimer;

  int get runningTaskSize => _runningTasks.length;
  int get maxRunningTaskCount => _maxRunningTaskCount;

  // ============ Hive 存储 ============

  List<AlistDownloadRecord> _loadAllRecords() {
    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.downloadRecords,
        ) ??
        [];
    return raw
        .map((e) => AlistDownloadRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _saveAllRecords(List<AlistDownloadRecord> list) async {
    await StorageManager.setSetting(
      AlistStorageKeys.downloadRecords,
      list.map((e) => e.toJson()).toList(),
    );
  }

  AlistDownloadRecord? _findRecord(
    String serverId,
    String userId,
    String remotePath,
  ) {
    return _loadAllRecords().firstWhereOrNull((r) =>
        r.serverId == serverId &&
        r.userId == userId &&
        r.remotePath == remotePath);
  }

  Future<void> _insertRecord(AlistDownloadRecord record) async {
    final list = _loadAllRecords();
    list.add(record);
    await _saveAllRecords(list);
  }

  /// 对外（被 Task 调用）
  Future<void> updateRecord(AlistDownloadRecord record) async {
    final list = _loadAllRecords();
    final idx = list.indexWhere((r) => r.id == record.id);
    if (idx != -1) {
      list[idx] = record;
    } else {
      list.add(record);
    }
    await _saveAllRecords(list);
  }

  Future<void> _deleteRecord(AlistDownloadRecord record) async {
    final list = _loadAllRecords();
    list.removeWhere((r) => r.id == record.id);
    await _saveAllRecords(list);
  }

  // ============ 下载入口 ============

  /// 直接下载（不排队）
  Future<AlistDownloadTask?> download({
    required String name,
    required String remotePath,
    required String sign,
    String? thumb,
    Map<String, dynamic>? requestHeaders,
    int? limitFrequency,
    CancelToken? cancelToken,
  }) async {
    final fileUrl = await AlistFileUtils.makeFileLink(remotePath, sign);
    if (fileUrl == null) return null;

    final serverCtrl = Get.find<AlistServerController>();
    final userCtrl = Get.find<AlistUserController>();
    final server = serverCtrl.currentServer;
    if (server == null) return null;

    final serverId = server.id;
    final userId = server.username ?? 'guest';

    // 已有记录
    var record = _findRecord(serverId, userId, remotePath);
    if (record != null) {
      final localFile = File(record.localPath);
      if (record.sign == sign && localFile.existsSync()) {
        return AlistDownloadTask(
          downloadManager: this,
          statusCallback: _onTaskStatusChange,
          url: fileUrl,
          record: record,
          cancelToken: cancelToken ?? CancelToken(),
          requestHeaders: requestHeaders ?? {},
          limitFrequency: limitFrequency ?? 0,
          status: AlistDownloadTaskStatus.finished,
        );
      }
    }

    // 新建记录
    final fileName = _makeDownloadFileName(name);
    final downloadDir = await _getDownloadDir('Downloads');
    final localPath = p.join(downloadDir.path, fileName);

    record = AlistDownloadRecord(
      id: const Uuid().v4(),
      serverId: serverId,
      userId: userId,
      remotePath: remotePath,
      name: name,
      sign: sign,
      localPath: localPath,
      thumbnail: thumb,
      requestHeaders:
          requestHeaders != null ? jsonEncode(requestHeaders) : null,
      limitFrequency: limitFrequency,
      createTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _insertRecord(record);

    final parentDir = Directory(localPath).parent;
    if (!parentDir.existsSync()) await parentDir.create(recursive: true);

    final task = AlistDownloadTask(
      downloadManager: this,
      statusCallback: _onTaskStatusChange,
      url: fileUrl,
      record: record,
      requestHeaders: requestHeaders ?? {},
      limitFrequency: limitFrequency ?? 0,
      cancelToken: cancelToken ?? CancelToken(),
    );
    task.start();
    _startListenProgress();
    return task;
  }

  /// 排队下载（受并发数限制）
  Future<AlistDownloadTask?> enqueue({
    required String name,
    required String remotePath,
    required String sign,
    String? thumb,
    Map<String, dynamic>? requestHeaders,
    int? limitFrequency,
    CancelToken? cancelToken,
    bool ignoreDuplicates = false,
  }) async {
    final fileUrl = await AlistFileUtils.makeFileLink(remotePath, sign);
    if (fileUrl == null) return null;

    // 已在队列中
    if (_waitingTasks.any((t) => t.url == fileUrl)) {
      if (!ignoreDuplicates) {
        SmartDialog.showToast('已经在下载队列中了');
      }
      return null;
    }
    if (_runningTasks.any((t) => t.url == fileUrl)) {
      if (!ignoreDuplicates) {
        SmartDialog.showToast('该任务正在下载中');
      }
      return null;
    }

    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return null;
    final serverId = server.id;
    final userId = server.username ?? 'guest';

    var record = _findRecord(serverId, userId, remotePath);
    if (record != null && ignoreDuplicates) return null;

    // 已存在文件：询问是否覆盖
    if (record != null) {
      final localFile = File(record.localPath);
      if (record.sign == sign && localFile.existsSync()) {
        // 简化处理：直接跳过
        SmartDialog.showToast('文件已下载');
        return null;
      }
    }

    final fileName = _makeDownloadFileName(name);
    final downloadDir = await _getDownloadDir('Downloads');
    final localPath = p.join(downloadDir.path, fileName);

    record = AlistDownloadRecord(
      id: const Uuid().v4(),
      serverId: serverId,
      userId: userId,
      remotePath: remotePath,
      name: name,
      sign: sign,
      localPath: localPath,
      thumbnail: thumb,
      requestHeaders:
          requestHeaders != null ? jsonEncode(requestHeaders) : null,
      limitFrequency: limitFrequency,
      createTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _insertRecord(record);

    final parentDir = Directory(localPath).parent;
    if (!parentDir.existsSync()) await parentDir.create(recursive: true);

    final task = AlistDownloadTask(
      downloadManager: this,
      statusCallback: _onTaskStatusChange,
      url: fileUrl,
      record: record,
      requestHeaders: requestHeaders ?? {},
      limitFrequency: limitFrequency ?? 0,
      cancelToken: cancelToken ?? CancelToken(),
    );

    if (_runningTasks.length >= _maxRunningTaskCount) {
      _onTaskStatusChange(task, AlistDownloadTaskStatus.waiting, null);
    } else {
      task.start();
      _startListenProgress();
    }
    return task;
  }

  // ============ 任务状态变化 ============

  void _onTaskStatusChange(
    AlistDownloadTask task,
    AlistDownloadTaskStatus status,
    String? reason,
  ) {
    switch (status) {
      case AlistDownloadTaskStatus.waiting:
        if (_waitingTasks.contains(task)) return;
        _waitingTasks.addLast(task);
        _runningTasks.remove(task);
        break;
      case AlistDownloadTaskStatus.downloading:
      case AlistDownloadTaskStatus.decompressing:
        _startListenProgress();
        if (_runningTasks.contains(task)) return;
        _runningTasks.addFirst(task);
        _waitingTasks.remove(task);
        break;
      case AlistDownloadTaskStatus.paused:
      case AlistDownloadTaskStatus.failed:
      case AlistDownloadTaskStatus.finished:
      case AlistDownloadTaskStatus.canceled:
        _waitingTasks.remove(task);
        _runningTasks.remove(task);
        if (status == AlistDownloadTaskStatus.finished) {
          SmartDialog.showToast('文件"${task.record.name}"下载完成');
        } else if (status == AlistDownloadTaskStatus.failed) {
          SmartDialog.showToast('文件"${task.record.name}"下载失败');
        }
        if (_waitingTasks.isNotEmpty &&
            _runningTasks.length < _maxRunningTaskCount) {
          final next = _waitingTasks.removeFirst();
          next.start();
        }
        if (_runningTasks.isEmpty && _waitingTasks.isEmpty) {
          _stopListenProgress();
        }
        break;
    }
    if (_statusController.hasListener) {
      _statusController.add(task);
    }
  }

  Future<HttpClientResponse> request(
    AlistDownloadTask task,
    Map<String, dynamic> requestHeader,
  ) async {
    return _httpClient.get(
      task.url,
      headers: requestHeader,
      limitFrequency: task.limitFrequency,
    );
  }

  void _startListenProgress() {
    if (!_progressController.hasListener ||
        _runningTasks.isEmpty ||
        _progressTimer != null) {
      return;
    }
    _progressTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      for (final task in _runningTasks) {
        if (task.status == AlistDownloadTaskStatus.downloading &&
            task.downloaded > 0) {
          _progressController.add(task);
        }
      }
    });
  }

  void _stopListenProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  // ============ 对外接口 ============

  StreamSubscription<AlistDownloadTask> listenDownloadStatusChange(
    void Function(AlistDownloadTask task) onStatusChange,
  ) {
    return _statusController.stream.listen(onStatusChange);
  }

  StreamSubscription<AlistDownloadTask> listenDownloadProgressChange(
    void Function(AlistDownloadTask task) onProgressChange,
  ) {
    final sub = _progressController.stream.listen(onProgressChange);
    _startListenProgress();
    return sub;
  }

  void setMaxRunningTaskCount(int count) {
    if (_maxRunningTaskCount == count) return;
    if (count < 1) throw ArgumentError('count must be > 0');
    final original = _maxRunningTaskCount;
    _maxRunningTaskCount = count;

    if (original > count && _runningTasks.isNotEmpty) {
      final diff = original - count;
      for (var i = 0; i < diff; i++) {
        if (_runningTasks.isNotEmpty) {
          _runningTasks.removeFirst().moveToWaiting();
        } else {
          break;
        }
      }
    } else if (count > original && _waitingTasks.isNotEmpty) {
      final diff = count - original;
      for (var i = 0; i < diff; i++) {
        if (_waitingTasks.isNotEmpty) {
          _waitingTasks.removeFirst().start();
        } else {
          break;
        }
      }
    }
    StorageManager.setSetting(AlistStorageKeys.maxRunningTaskCount, count);
  }

  void pause(String savedPath) {
    final task = _findTaskBySavedPath(savedPath);
    task?.pause();
  }

  void cancel(String savedPath) {
    final task = _findTaskBySavedPath(savedPath);
    task?.cancel();
  }

  AlistDownloadTask? _findTaskBySavedPath(String path) {
    return _runningTasks.firstWhereOrNull(
          (t) => t.record.localPath == path,
        ) ??
        _waitingTasks.firstWhereOrNull((t) => t.record.localPath == path);
  }

  String? findLocalPath(String remotePath) {
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return null;
    final record = _findRecord(
      server.id,
      server.username ?? 'guest',
      remotePath,
    );
    if (record == null) return null;
    final file = File(record.localPath);
    return file.existsSync() ? record.localPath : null;
  }

  Future<void> deleteRecord(AlistDownloadRecord record) async {
    await _deleteRecord(record);
  }

  // ============ 路径与文件名 ============

  Future<Directory> _getDownloadDir(String fileType) async {
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) {
      throw StateError('未选择 AList 服务器');
    }

    Directory baseDir;
    if (Platform.isAndroid) {
      final dirs = await getExternalStorageDirectory();
      baseDir = dirs ?? await getTemporaryDirectory();
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final subPath = '${server.id}/${server.username ?? "guest"}';
    final dir = Directory(
      '${baseDir.path}/AListDownloads/$subPath/$fileType',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _makeDownloadFileName(String originalName) {
    var extension = originalName.contains('.')
        ? originalName.substring(originalName.lastIndexOf('.') + 1)
        : '';
    if (extension.length > 10) {
      extension = '';
    } else {
      extension = extension.isEmpty ? '' : '.$extension';
    }
    return '${const Uuid().v4()}$extension';
  }

  void dispose() {
    _statusController.close();
    _progressController.close();
    _progressTimer?.cancel();
  }
}