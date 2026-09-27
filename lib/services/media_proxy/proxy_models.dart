import 'dart:typed_data';

/// 探测结果
class ProbeResult {
  final bool supportsRange;
  final int contentSize;
  final Map<String, List<String>> headers;
  final DateTime createdAt;

  /// 文件头字节（用于魔数识别）
  final Uint8List? headerBytes;

  ProbeResult({
    required this.supportsRange,
    required this.contentSize,
    required this.headers,
    required this.createdAt,
    this.headerBytes,
  });

  bool get isExpired =>
      DateTime.now().difference(createdAt).inMinutes > 30;
}

/// 缓存条目
class CacheEntry<T> {
  final T value;
  final DateTime expireAt;
  CacheEntry(this.value, this.expireAt);
  bool get isExpired => DateTime.now().isAfter(expireAt);
}