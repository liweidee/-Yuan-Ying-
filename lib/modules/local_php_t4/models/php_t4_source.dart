// lib/modules/local_php_t4/models/php_t4_source.dart

/// PHP-T4 本地源文件
class PhpT4Source {
  /// 显示名（不含后缀，例如「央视频」）
  final String name;

  /// 完整文件名（例如「央视频 ᵈᶻ.php」）
  final String fileName;

  /// 绝对路径
  final String path;

  final int size;
  final DateTime modified;

  const PhpT4Source({
    required this.name,
    required this.fileName,
    required this.path,
    required this.size,
    required this.modified,
  });

  String get sizeText {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)}MB';
  }
}