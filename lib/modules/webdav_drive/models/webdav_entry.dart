class WebDavEntry {
  final String name;
  final String path;         // 服务器上的相对路径，如 /movies/xxx.mkv
  final bool isDirectory;
  final int size;
  final DateTime? modified;

  const WebDavEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  /// 视频文件扩展名判断
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