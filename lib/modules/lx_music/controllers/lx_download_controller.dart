import 'dart:async';

import 'package:get/get.dart';

import '../models/lx_download_model.dart';
import '../models/lx_music_model.dart';
import '../services/lx_download_service.dart';
import '../services/lx_music_url_service.dart';
import '../utils/lx_logger.dart';

/// 洛雪音乐下载控制器
class LxDownloadController extends GetxController {
  final LxDownloadService _service = LxDownloadService.instance;

  final RxList<LxDownloadTask> queue = <LxDownloadTask>[].obs;
  final RxList<LxMusic> downloadedSongs = <LxMusic>[].obs;
  final RxBool isLoading = false.obs;

  StreamSubscription<LxDownloadTask>? _taskSub;

  int get downloadingCount => queue
      .where((t) =>
          t.status == LxDownloadStatus.downloading ||
          t.status == LxDownloadStatus.pending)
      .length;

  int get completedCount =>
      queue.where((t) => t.status == LxDownloadStatus.completed).length;

  int get failedCount =>
      queue.where((t) => t.status == LxDownloadStatus.failed).length;

  bool isDownloaded(String musicId) =>
      downloadedSongs.any((s) => s.id == musicId);

  @override
  void onInit() {
    super.onInit();
    // 延后到微任务，避免 initState/build 期间改 Rx
    Future.microtask(() => _loadData());

    _taskSub = _service.taskStream.listen((task) {
      final list = List<LxDownloadTask>.from(queue);
      final idx = list.indexWhere((t) => t.music.id == task.music.id);
      if (idx >= 0) {
        list[idx] = task;
        queue.value = list;
      }
      if (task.status == LxDownloadStatus.completed) {
        final downloaded = List<LxMusic>.from(downloadedSongs);
        final updated = task.music.copyWith(songUrl: task.filePath);
        downloaded.removeWhere((s) => s.id == updated.id);
        downloaded.add(updated);
        downloadedSongs.value = downloaded;
      }
    });
  }

  @override
  void onClose() {
    _taskSub?.cancel();
    super.onClose();
  }

  Future<void> _loadData() async {
    isLoading.value = true;
    try {
      queue.value = await _service.getDownloadQueue();
      downloadedSongs.value = await _service.getDownloadedSongs();
      _service.processQueue();
    } catch (e) {
      LxLogger.error('下载数据加载失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refresh() => _loadData();

  Future<void> download(LxMusic music, {String quality = '320k'}) async {
    await _service.addToDownloadQueue(music, quality: quality);
    queue.value = await _service.getDownloadQueue();
  }

  /// 供 UI 层取下载地址（不触发下载）
  Future<String?> serviceUrlFor(LxMusic music) async {
    try {
      return await LxMusicUrlService.instance.getMusicUrl(music: music);
    } catch (e) {
      LxLogger.warn('取下载URL失败: $e');
      return null;
    }
  }

  Future<void> retry(String musicId) async {
    await _service.retryDownload(musicId);
    await _loadData();
  }

  Future<void> remove(String musicId) async {
    await _service.removeFromDownloadQueue(musicId);
    await _loadData();
  }

  Future<void> cancel(String musicId) async {
    await _service.cancelDownload(musicId);
    await _loadData();
  }

  Future<void> deleteDownloaded(LxMusic music) async {
    await _service.deleteDownloadedSong(music);
    await _loadData();
  }
}