import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yuanying/modules/local_file/models/video_file.dart';

class FileScannerService {
  static const List<String> videoExtensions = [
    '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm',
    '.m4v', '.3gp', '.mpg', '.mpeg', '.ts', '.m2ts',
  ];

  /// 扫描目录下的所有视频文件
  Future<List<VideoFile>> scanDirectory(String path, {bool recursive = true}) async {
    final directory = Directory(path);
    if (!await directory.exists()) return [];

    final files = <VideoFile>[];
    await for (final entity in directory.list(recursive: recursive, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (videoExtensions.contains(ext)) {
          try {
            final stat = await entity.stat();
            files.add(VideoFile(
              path: entity.path,
              name: p.basename(entity.path),
              size: stat.size,
              modifiedTime: stat.modified,
              duration: 0,
            ));
          } catch (_) {}
        }
      }
    }
    return files;
  }

  /// 获取目录下的子文件夹（只包含有视频文件的）
  Future<List<String>> getSubDirectories(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return [];

    final subDirs = <String>[];
    await for (final entity in directory.list(recursive: false, followLinks: false)) {
      if (entity is Directory) {
        final hasVideo = await _hasVideoFiles(entity.path);
        if (hasVideo) {
          subDirs.add(entity.path);
        }
      }
    }
    return subDirs;
  }

  /// 检查目录是否包含视频文件（递归检查）
  Future<bool> _hasVideoFiles(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return false;

    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (videoExtensions.contains(ext)) return true;
      }
    }
    return false;
  }

  static String getFileName(String path) => p.basename(path);
}