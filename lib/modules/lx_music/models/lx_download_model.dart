import 'dart:convert';
import 'lx_music_model.dart';

/// 下载状态
enum LxDownloadStatus {
  pending,
  downloading,
  completed,
  failed,
}

/// 下载任务
class LxDownloadTask {
  final LxMusic music;
  final String quality;
  LxDownloadStatus status;
  int progress;
  String? filePath;
  String? error;
  final DateTime addedTime;

  LxDownloadTask({
    required this.music,
    required this.quality,
    required this.status,
    required this.progress,
    this.filePath,
    this.error,
    required this.addedTime,
  });

  String toJsonString() {
    return jsonEncode({
      'music': music.toJson(),
      'quality': quality,
      'status': status.index,
      'progress': progress,
      'filePath': filePath,
      'error': error,
      'addedTime': addedTime.toIso8601String(),
    });
  }

  factory LxDownloadTask.fromJsonString(String json) {
    final map = Map<String, dynamic>.from(jsonDecode(json) as Map);
    return LxDownloadTask(
      music: LxMusic.fromJson(Map<String, dynamic>.from(map['music'] as Map)),
      quality: map['quality']?.toString() ?? '320k',
      status: LxDownloadStatus.values[(map['status'] as int?) ?? 0],
      progress: (map['progress'] as int?) ?? 0,
      filePath: map['filePath']?.toString(),
      error: map['error']?.toString(),
      addedTime: map['addedTime'] != null
          ? DateTime.tryParse(map['addedTime'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}