import 'dart:io';

class VideoFile {
  final String path;
  final String name;
  final int size;
  final DateTime modifiedTime;
  final int duration;

  VideoFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedTime,
    this.duration = 0,
  });

  String get sizeFormatted => _formatSize(size);
  String get durationFormatted => _formatDuration(duration);
  String get parentPath {
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index > 0 ? path.substring(0, index) : path;
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '--:--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => name;
}