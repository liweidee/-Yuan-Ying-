// lib/modules/download/services/m3u8_parser.dart
import 'package:dio/dio.dart';

import 'package:yuanying/modules/download/models/m3u8_playlist.dart';

/// M3U8 解析器
///
/// 支持：
/// - master playlist（含 #EXT-X-STREAM-INF），自动选择最高码率 variant
/// - media playlist（含 #EXTINF / #EXT-X-KEY / #EXT-X-MEDIA-SEQUENCE）
/// - 相对路径转绝对路径
abstract final class M3U8Parser {
  /// 从 URL 加载并解析
  ///
  /// 如果是 master playlist，递归解析码率最高的 variant
  static Future<M3U8Playlist> parseFromUrl(
    String url, {
    Map<String, String>? headers,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    ));

    final response = await dio.get<String>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
      ),
    );

    final content = response.data ?? '';
    final playlist = parseText(content, url);

    if (playlist.isMaster && playlist.variants.isNotEmpty) {
      // 选择码率最高的 variant
      final best = playlist.variants.reduce(
        (a, b) => a.bandwidth >= b.bandwidth ? a : b,
      );
      return parseFromUrl(best.url, headers: headers);
    }

    return playlist;
  }

  /// 解析 m3u8 文本
  static M3U8Playlist parseText(String content, String baseUrl) {
    final lines = content
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final isMaster = lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'));
    if (isMaster) {
      return _parseMaster(lines, baseUrl);
    }
    return _parseMedia(lines, baseUrl);
  }

  // ============================================================
  // Master playlist
  // ============================================================
  static M3U8Playlist _parseMaster(List<String> lines, String baseUrl) {
    final variants = <M3U8Variant>[];
    int bandwidth = 0;
    String? resolution;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('#EXT-X-STREAM-INF')) {
        bandwidth = _parseAttrInt(line, 'BANDWIDTH') ?? 0;
        resolution = _parseAttrString(line, 'RESOLUTION');
      } else if (!line.startsWith('#')) {
        final url = _resolveUrl(baseUrl, line);
        variants.add(M3U8Variant(
          url: url,
          bandwidth: bandwidth,
          resolution: resolution,
        ));
        bandwidth = 0;
        resolution = null;
      }
    }

    return M3U8Playlist(
      segments: const [],
      variants: variants,
      isMaster: true,
    );
  }

  // ============================================================
  // Media playlist
  // ============================================================
  static M3U8Playlist _parseMedia(List<String> lines, String baseUrl) {
    final segments = <M3U8Segment>[];
    M3U8Key? currentKey;
    double duration = 0;
    int mediaSequence = 0;
    int segmentIndex = 0;

    for (final line in lines) {
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE')) {
        mediaSequence = int.tryParse(line.split(':').last.trim()) ?? 0;
      } else if (line.startsWith('#EXT-X-KEY')) {
        final method = _parseAttrString(line, 'METHOD') ?? 'NONE';
        if (method.toUpperCase() == 'NONE') {
          currentKey = null;
        } else {
          final uri = _parseAttrString(line, 'URI');
          final iv = _parseAttrString(line, 'IV');
          currentKey = M3U8Key(
            method: method,
            uri: uri != null ? _resolveUrl(baseUrl, uri) : null,
            iv: iv,
            mediaSequence: mediaSequence,
          );
        }
      } else if (line.startsWith('#EXTINF')) {
        final value = line.substring(8).split(',').first.trim();
        duration = double.tryParse(value) ?? 0;
      } else if (!line.startsWith('#')) {
        final url = _resolveUrl(baseUrl, line);
        segments.add(M3U8Segment(
          url: url,
          duration: duration,
          mediaSequence: mediaSequence + segmentIndex,
          key: currentKey,
        ));
        segmentIndex++;
        duration = 0;
      }
    }

    return M3U8Playlist(
      segments: segments,
      variants: const [],
      isMaster: false,
      key: currentKey,
    );
  }

  // ============================================================
  // 辅助方法
  // ============================================================
  static int? _parseAttrInt(String line, String key) {
    final match = RegExp('$key=(\\d+)').firstMatch(line);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  static String? _parseAttrString(String line, String key) {
    final match = RegExp('$key=([^,\\s]+)').firstMatch(line);
    if (match == null) return null;
    var value = match.group(1)!;
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }

  static String _resolveUrl(String baseUrl, String relative) {
    try {
      return Uri.parse(baseUrl).resolve(relative).toString();
    } catch (_) {
      return relative;
    }
  }
}