import 'dart:collection';
import 'dart:typed_data';

/// 分片级 LRU 缓存
///
/// 目的：MKV/MP4 播放时 mpv 会反复 seek（读头 → 跳到文件尾读 Cues → 回到开头 →
/// 随机定位）。如果每次 seek 都重建一次全量多线程下载，源站会被打满并触发限流。
///
/// 缓存以「全局 chunk 网格」为 key：
///   key = url + '#' + chunkSize + '#' + (gridStart ~/ chunkSize)
/// 只要同一个 URL 使用相同的 chunkSize，不同 Range 请求之间就能互相命中，
/// 哪怕两次请求的起始偏移量完全不对齐（5877 与 0 会落在同一个第 0 号网格上）。
class ChunkCache {
  ChunkCache({this.maxBytes = 192 * 1024 * 1024});

  final int maxBytes;

  final LinkedHashMap<String, Uint8List> _map = LinkedHashMap<String, Uint8List>();
  int _bytes = 0;

  /// 命中次数（便于排查命中率）
  int hitCount = 0;
  int missCount = 0;

  static String keyFor(String url, int chunkSize, int gridStart) =>
      '$url#$chunkSize#${gridStart ~/ chunkSize}';

  /// 读取一个完整网格分片；未命中返回 null。
  ///
  /// 注意：只缓存「完整分片」，因此读到的必然是长度 == chunkSize 的数据。
  Uint8List? get(String url, int chunkSize, int gridStart) {
    final data = _map[keyFor(url, chunkSize, gridStart)];
    if (data == null) {
      missCount++;
      return null;
    }
    // LinkedHashMap 的 LRU：访问后重新插入到末尾
    _map.remove(keyFor(url, chunkSize, gridStart));
    _map[keyFor(url, chunkSize, gridStart)] = data;
    hitCount++;
    return data;
  }

  /// 写入一个完整网格分片（长度必须等于 chunkSize，否则不缓存）。
  void put(String url, int chunkSize, int gridStart, Uint8List data) {
    if (data.length != chunkSize) return;
    final key = keyFor(url, chunkSize, gridStart);
    if (_map.containsKey(key)) return;

    _map[key] = data;
    _bytes += data.length;

    // 超限则按插入顺序淘汰
    while (_bytes > maxBytes && _map.isNotEmpty) {
      final oldest = _map.keys.first;
      final removed = _map.remove(oldest);
      if (removed != null) _bytes -= removed.length;
    }
  }

  void clear() {
    _map.clear();
    _bytes = 0;
  }

  int get sizeInBytes => _bytes;

  double get hitRate =>
      (hitCount + missCount) == 0 ? 0 : hitCount / (hitCount + missCount);
}
