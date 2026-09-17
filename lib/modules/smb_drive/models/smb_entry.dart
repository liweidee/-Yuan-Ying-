import 'package:smb_connect/smb_connect.dart';

/// SMB 条目：既可以是共享（share），也可以是目录/文件
///
/// - `path` 对共享：仅共享名（如 `public`）
/// - `path` 对目录/文件：相对共享根的路径（如 `/movies`、`/movies/xxx.mkv`）
class SmbEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final bool isShare;
  final int size;
  final DateTime? modified;

  const SmbEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isShare = false,
    this.size = 0,
    this.modified,
  });

  /// 从共享列表构造（`path` 只存共享名）
  factory SmbEntry.fromShare(SmbFile share) {
    final name = share.path.split('/').where((p) => p.isNotEmpty).last;
    return SmbEntry(
      name: name,
      path: name,
      isDirectory: true,
      isShare: true,
    );
  }

  /// 从文件/目录构造（`path` 转为相对共享根的路径）
  /// [share] 用于计算相对路径
  factory SmbEntry.fromSmbFile(SmbFile f, {required String share}) {
    final name = f.path.split('/').where((p) => p.isNotEmpty).last;
    final relPath = _relativize(f.path, share);
    return SmbEntry(
      name: name,
      path: relPath,
      isDirectory: f.isDirectory(),
      isShare: false,
      size: f.size ?? 0,
      modified: _parseTimestamp(f.lastModified),
    );
  }

  /// `/public/movies/xxx.mkv` + share=`public` → `/movies/xxx.mkv`
  static String _relativize(String fullPath, String share) {
    final prefix = '/$share';
    if (fullPath == prefix || fullPath == '$prefix/') {
      return '/';
    }
    if (fullPath.startsWith('$prefix/')) {
      return fullPath.substring(prefix.length);
    }
    // 万一 share 前缀不匹配（少数服务器），退回原路径
    return fullPath.startsWith('/') ? fullPath : '/$fullPath';
  }

  /// Unix 时间戳（秒或毫秒）→ DateTime
  static DateTime? _parseTimestamp(int? ts) {
    if (ts == null || ts <= 0) return null;
    // 秒级时间戳约 1e9，毫秒级约 1e12
    if (ts > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(ts);
    }
    return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  }

  bool get isVideo {
    final ext = name.split('.').last.toLowerCase();
    return const {
      'mp4', 'mkv', 'avi', 'webm', 'mov', 'ts', 'm2ts',
      'wmv', 'flv', 'ogv', 'rmvb', 'mpg', 'mpeg', 'vob', '3gp', 'm4v',
    }.contains(ext);
  }

  String get sizeLabel {
    if (size <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = size.toDouble();
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[u]}';
  }
}