// lib/modules/download/models/m3u8_playlist.dart

/// AES-128 密钥信息（可能随分片变化）
class M3U8Key {
  final String method; // AES-128 / NONE / SAMPLE-AES
  final String? uri;
  final String? iv; // 十六进制字符串，可能带 0x 前缀
  final int? mediaSequence; // 用于 IV 计算

  M3U8Key({
    required this.method,
    this.uri,
    this.iv,
    this.mediaSequence,
  });

  bool get isEncrypted => method.toUpperCase() == 'AES-128';
}

/// M3U8 分片
class M3U8Segment {
  final String url;
  final double duration;
  final int mediaSequence;
  final M3U8Key? key;

  M3U8Segment({
    required this.url,
    required this.duration,
    required this.mediaSequence,
    this.key,
  });
}

/// M3U8 master playlist 中的 variant（码率选项）
class M3U8Variant {
  final String url;
  final int bandwidth;
  final String? resolution;

  M3U8Variant({
    required this.url,
    required this.bandwidth,
    this.resolution,
  });
}

/// M3U8 播放列表（master 或 media）
class M3U8Playlist {
  final List<M3U8Segment> segments;
  final List<M3U8Variant> variants;
  final bool isMaster;
  final M3U8Key? key;

  M3U8Playlist({
    required this.segments,
    required this.variants,
    required this.isMaster,
    this.key,
  });

  bool get isEmpty => segments.isEmpty && variants.isEmpty;
}