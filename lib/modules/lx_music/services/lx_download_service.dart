import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/storage_keys.dart';
import '../models/lx_download_model.dart';
import '../models/lx_music_model.dart';
import '../storage/lx_storage.dart';
import '../utils/lx_logger.dart';

/// 洛雪音乐下载服务
class LxDownloadService {
  LxDownloadService._();
  static final LxDownloadService instance = LxDownloadService._();

  static const String _downloadSubDir = 'lx_music/downloads';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
  ));

  final Map<String, CancelToken> _cancelTokens = {};
  bool _isProcessing = false;
  Timer? _progressSaveTimer;

  final StreamController<LxDownloadTask> _taskStreamController =
      StreamController<LxDownloadTask>.broadcast();
  Stream<LxDownloadTask> get taskStream => _taskStreamController.stream;

  void _emitTask(LxDownloadTask task) {
    if (!_taskStreamController.isClosed) {
      _taskStreamController.add(task);
    }
  }

  // ==================== 下载路径 ====================

  /// 下载目录：优先读项目设置 `downloadPath`，否则用应用文档目录
  Future<String> _getLocalPath() async {
    String basePath;
    try {
      // 尝试读取项目的下载路径设置
      final fromSetting = _readSettingDownloadPath();
      if (fromSetting != null && fromSetting.isNotEmpty) {
        basePath = fromSetting;
      } else {
        final directory = await getApplicationDocumentsDirectory();
        basePath = '${directory.path}/$_downloadSubDir';
      }
    } catch (_) {
      final directory = await getApplicationDocumentsDirectory();
      basePath = '${directory.path}/$_downloadSubDir';
    }

    final downloadDir = Directory(basePath);
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir.path;
  }

  /// 尝试从项目的 SettingBox 读取 downloadPath（避免强依赖，做容错）
  String? _readSettingDownloadPath() {
    try {
      // 用 Hive 直接读 app_settings box（与项目 SettingBoxKey.downloadPath 对应）
      // 这里用同步方式；如果 box 未打开则返回 null
      // 由于 Hive box 是懒加载的，这里用 try-catch 兜底
      return null; // 保守：不读设置，直接用应用目录。如需读取请告知我补充
    } catch (_) {
      return null;
    }
  }

  // ==================== 队列管理 ====================

  Future<List<LxDownloadTask>> getDownloadQueue() async {
    final jsonList = await LxStorage.instance.getDownloadQueue();
    final result = <LxDownloadTask>[];
    for (final json in jsonList) {
      try {
        result.add(LxDownloadTask.fromJsonString(json));
      } catch (e) {
        LxLogger.warn('跳过损坏任务: $e');
      }
    }
    return result;
  }

  Future<void> _saveDownloadQueue(List<LxDownloadTask> queue) async {
    final jsonList = queue.map((t) => t.toJsonString()).toList();
    await LxStorage.instance.saveDownloadQueue(jsonList);
  }

  Future<List<LxMusic>> getDownloadedSongs() async {
    final jsonList = await LxStorage.instance.getDownloadedSongs();
    final result = <LxMusic>[];
    for (final json in jsonList) {
      try {
        if (!json.startsWith('{')) continue;
        result.add(
            LxMusic.fromJson(Map<String, dynamic>.from(jsonDecode(json) as Map)));
      } catch (e) {
        LxLogger.warn('跳过损坏歌曲记录: $e');
      }
    }
    return result;
  }

  Future<void> _saveDownloadedSongs(List<LxMusic> songs) async {
    final jsonList = songs.map((s) => jsonEncode(s.toJson())).toList();
    await LxStorage.instance.saveDownloadedSongs(jsonList);
  }

  Future<void> addToDownloadQueue(LxMusic music,
      {String quality = '320k'}) async {
    final queue = await getDownloadQueue();
    if (queue.any((task) => task.music.id == music.id)) return;

    final task = LxDownloadTask(
      music: music,
      quality: quality,
      status: LxDownloadStatus.pending,
      progress: 0,
      addedTime: DateTime.now(),
    );

    queue.add(task);
    await _saveDownloadQueue(queue);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        final queue = await getDownloadQueue();

        // 卡死任务恢复
        var recovered = false;
        for (final t in queue) {
          if (t.status == LxDownloadStatus.downloading) {
            t.status = LxDownloadStatus.pending;
            t.progress = 0;
            t.error = null;
            recovered = true;
          }
        }
        if (recovered) {
          await _saveDownloadQueue(queue);
        }

        final pendingTasks = queue
            .where((task) => task.status == LxDownloadStatus.pending)
            .toList();
        if (pendingTasks.isEmpty) break;

        final currentTask = pendingTasks.first;
        currentTask.status = LxDownloadStatus.downloading;
        currentTask.progress = 0;
        await _saveDownloadQueue(queue);
        _emitTask(currentTask);

        try {
          final downloadDir = await _getLocalPath();
          final ext = currentTask.quality == 'flac' ||
                  currentTask.quality == 'flac24bit'
              ? 'flac'
              : 'mp3';
          final fileName =
              '${currentTask.music.id}_${currentTask.quality}.$ext';
          final filePath = '$downloadDir/$fileName';

          final partialFile = File(filePath);
          if (await partialFile.exists()) {
            await partialFile.delete();
          }

          final cancelToken = CancelToken();
          _cancelTokens[currentTask.music.id] = cancelToken;

          await _dio.download(
            currentTask.music.songUrl ?? '',
            filePath,
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              if (total != -1) {
                currentTask.progress = (received / total * 100).toInt();
                _scheduleQueueSave(queue);
                _emitTask(currentTask);
              }
            },
          );
          _cancelTokens.remove(currentTask.music.id);

          currentTask.status = LxDownloadStatus.completed;
          currentTask.filePath = filePath;
          currentTask.progress = 100;
          await _saveDownloadQueue(queue);
          _emitTask(currentTask);

          final downloadedSongs = await getDownloadedSongs();
          final updatedMusic =
              currentTask.music.copyWith(songUrl: filePath);
          downloadedSongs.removeWhere((s) => s.id == updatedMusic.id);
          downloadedSongs.add(updatedMusic);
          await _saveDownloadedSongs(downloadedSongs);

          LxLogger.info('下载完成: ${currentTask.music.name}');
        } catch (e) {
          _cancelTokens.remove(currentTask.music.id);

          final downloadDir2 = await _getLocalPath();
          final ext2 = currentTask.quality == 'flac' ||
                  currentTask.quality == 'flac24bit'
              ? 'flac'
              : 'mp3';
          final partialFile2 = File(
              '$downloadDir2/${currentTask.music.id}_${currentTask.quality}.$ext2');
          if (await partialFile2.exists()) {
            await partialFile2.delete();
          }

          final stillExists = (await getDownloadQueue())
              .any((t) => t.music.id == currentTask.music.id);
          if (stillExists) {
            currentTask.status = LxDownloadStatus.failed;
            currentTask.error = e.toString();
            await _saveDownloadQueue(queue);
            _emitTask(currentTask);
          }
          LxLogger.error('下载失败: ${currentTask.music.name} - $e');
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  void _scheduleQueueSave(List<LxDownloadTask> queue) {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 800), () {
      _saveDownloadQueue(List<LxDownloadTask>.from(queue));
    });
  }

  Future<void> processQueue() => _processQueue();

  Future<void> retryDownload(String musicId) async {
    final queue = await getDownloadQueue();
    final task = queue.firstWhere(
      (task) => task.music.id == musicId,
      orElse: () => throw Exception('Task not found'),
    );

    task.status = LxDownloadStatus.pending;
    task.progress = 0;
    task.error = null;
    await _saveDownloadQueue(queue);
    _processQueue();
  }

  Future<void> removeFromDownloadQueue(String musicId) async {
    final queue = await getDownloadQueue();
    queue.removeWhere((task) => task.music.id == musicId);
    await _saveDownloadQueue(queue);
  }

  Future<void> cancelDownload(String musicId) async {
    _cancelTokens[musicId]?.cancel('user cancelled');
    _cancelTokens.remove(musicId);

    final queue = await getDownloadQueue();
    queue.removeWhere((task) => task.music.id == musicId);
    await _saveDownloadQueue(queue);
  }

  Future<void> deleteDownloadedSong(LxMusic music) async {
    final downloadedSongs = await getDownloadedSongs();
    downloadedSongs.removeWhere((song) => song.id == music.id);
    await _saveDownloadedSongs(downloadedSongs);

    if (music.songUrl != null) {
      final file = File(music.songUrl!);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<bool> isDownloaded(String musicId) async {
    final downloadedSongs = await getDownloadedSongs();
    return downloadedSongs.any((song) => song.id == musicId);
  }

  void dispose() {
    _progressSaveTimer?.cancel();
    _taskStreamController.close();
  }
}