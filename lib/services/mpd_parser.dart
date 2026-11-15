import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

/// MPD 解析结果
class MpdInfo {
  final String videoUrl;
  final String? audioUrl; // 纯视频 mpd 时为 null
  final String? videoCodec;
  final String? audioCodec;

  const MpdInfo({
    required this.videoUrl,
    this.audioUrl,
    this.videoCodec,
    this.audioCodec,
  });

  bool get hasAudio => (audioUrl ?? '').isNotEmpty;
}

/// 简易 DASH MPD 解析器（仅支持单 BaseURL 型）
///
/// 官方依据：
///   - ISO/IEC 23009-1 规定，Representation 若含 BaseURL 且不含
///     SegmentTemplate/SegmentList，则该 BaseURL 指向完整媒体文件，
///     可直接作为播放 URL。
///   - DASH-IF IOP 建议用 @contentType 标识轨道，@mimeType 兜底；
///     但 B 站音频 AdaptationSet 的 @mimeType 也是 video/mp4，
///     必须优先用 @codecs 前缀判断。
abstract final class MpdParser {
  static final Map<String, MpdInfo?> _cache = {};
  static const int _maxCache = 16;

  /// 判断 URL 是否为 MPD（保守策略，仅认两种强特征）
  ///
  /// 命中条件（任一）：
  ///   1. path 以 `.mpd` 结尾（标准 MPD 后缀）
  ///   2. URL 包含 `/mpdplay?`（本项目 B 站代理的固定路径）
  ///
  /// 其他情况一律返回 false —— 包括：
  ///   - 网盘直链（无后缀 / 带长 token）
  ///   - .mp4/.mkv/.m3u8 等明确媒体后缀
  ///   - 路径中偶然含 "mpd" 字符串的非 MPD URL
  ///
  /// 目的：兜底阶段避免对网盘直链发起无意义的 MPD 探测请求。
  static bool looksLikeMpd(String url) {
    if (url.isEmpty) return false;

    // 条件 1：path 以 .mpd 结尾
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url.split('?').first).toLowerCase();
    if (path.endsWith('.mpd')) return true;

    // 条件 2：包含 /mpdplay?（本项目 B 站代理路径）
    if (url.contains('/mpdplay?')) return true;

    // 其他一律不是 DASH
    return false;
  }

  /// 解析 mpd；失败返回 null（由调用方降级）
  ///
  /// 优先路径：
  ///   1. 从代理 URL query 提取 video/audio（无需网络）
  ///   2. 网络请求 + XML 解析
  static Future<MpdInfo?> parse(
    String mpdUrl, {
    Map<String, String>? headers,
  }) async {
    if (_cache.containsKey(mpdUrl)) return _cache[mpdUrl];

    // 优先：从代理 URL query 提取
    final fromQuery = _parseFromQuery(mpdUrl);
    if (fromQuery != null) {
      debugPrint('[MpdParser] 从 URL query 提取成功');
      _putCache(mpdUrl, fromQuery);
      return fromQuery;
    }

    // 回退：网络请求 + XML 解析
    final sanitized = _sanitizeHeaders(headers);
    try {
      final resp = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 12),
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      ).get(
        mpdUrl,
        options: Options(
          headers: sanitized,
          responseType: ResponseType.plain,
        ),
      );

      final body = resp.data?.toString().trim() ?? '';
      if (body.isEmpty) {
        _putCache(mpdUrl, null);
        return null;
      }
      // 内容嗅探：不是 XML/MPD 直接放弃
      if (!body.startsWith('<?xml') && !body.contains('<MPD')) {
        debugPrint('[MpdParser] 内容不是 XML/MPD，跳过');
        _putCache(mpdUrl, null);
        return null;
      }

      final info = _parseXml(body, mpdUrl);
      _putCache(mpdUrl, info);
      return info;
    } on DioException catch (e) {
      debugPrint('[MpdParser] 网络失败: ${e.message}');
      _putCache(mpdUrl, null);
      return null;
    } catch (e) {
      debugPrint('[MpdParser] 解析异常: $e');
      _putCache(mpdUrl, null);
      return null;
    }
  }

  /// 从代理 URL 的 query 参数提取 video/audio
  ///
  /// 支持形如 `/mpdplay?video=<encoded>&audio=<encoded>` 的代理 URL。
  /// 适用场景：服务端代理返回的 mpd 可能不包含音频 AdaptationSet，
  /// 但 URL 参数里已经明确携带了音频地址。
  static MpdInfo? _parseFromQuery(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    // Uri.queryParameters 已经自动做 URL 解码
    final video = uri.queryParameters['video'];
    if (video == null || video.isEmpty) return null;
    final audio = uri.queryParameters['audio'];
    return MpdInfo(
      videoUrl: video,
      audioUrl: (audio != null && audio.isNotEmpty) ? audio : null,
    );
  }

  static void _putCache(String key, MpdInfo? value) {
    if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
    _cache[key] = value;
  }

  static MpdInfo? _parseXml(String xmlStr, String mpdUrl) {
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlStr);
    } catch (e) {
      debugPrint('[MpdParser] XML 格式错误: $e');
      return null;
    }

    // 任意层级出现分片元素，直接判定为不支持
    if (doc.findAllElements('SegmentTemplate').isNotEmpty ||
        doc.findAllElements('SegmentList').isNotEmpty) {
      debugPrint('[MpdParser] 分片型 MPD，不支持');
      return null;
    }

    String? videoUrl;
    String? audioUrl;
    String? videoCodec;
    String? audioCodec;

    for (final adaptation in doc.findAllElements('AdaptationSet')) {
      try {
        final type = _detectAdaptationType(adaptation);
        if (type == null) continue;

        for (final rep in adaptation.findElements('Representation')) {
          try {
            final baseUrls = rep.findElements('BaseURL');
            if (baseUrls.isEmpty) continue;
            final raw = baseUrls.first.innerText.trim();
            if (raw.isEmpty) continue;

            final url = _resolveUrl(raw, mpdUrl);
            if (url.isEmpty) continue;

            final codec = rep.getAttribute('codecs') ??
                adaptation.getAttribute('codecs') ??
                '';

            if (type == 'video' && videoUrl == null) {
              videoUrl = url;
              videoCodec = codec;
            } else if (type == 'audio' && audioUrl == null) {
              audioUrl = url;
              audioCodec = codec;
            }
          } catch (e) {
            debugPrint('[MpdParser] Representation 解析跳过: $e');
          }
        }
      } catch (e) {
        debugPrint('[MpdParser] AdaptationSet 解析跳过: $e');
      }
    }

    if (videoUrl == null) {
      debugPrint('[MpdParser] 未找到有效视频 BaseURL');
      return null;
    }

    return MpdInfo(
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
    );
  }

  /// 类型判定：contentType → codecs → mimeType
  ///
  /// 关键：B 站音频 AdaptationSet 的 @mimeType 也是 video/mp4，
  /// 必须用 @codecs 前缀（mp4a 等）优先判定。
  static String? _detectAdaptationType(XmlElement adaptation) {
    // 1. contentType 属性（最权威）
    final ct = adaptation.getAttribute('contentType');
    if (ct == 'video' || ct == 'audio') return ct;

    // 2. codecs 前缀
    final codecs = adaptation.getAttribute('codecs')?.toLowerCase() ?? '';
    if (_isAudioCodec(codecs)) return 'audio';
    if (_isVideoCodec(codecs)) return 'video';

    // 3. mimeType 兜底（仅前两者都缺失时）
    final mime = adaptation.getAttribute('mimeType')?.toLowerCase() ?? '';
    if (mime.startsWith('audio/')) return 'audio';
    if (mime.startsWith('video/')) return 'video';

    return null;
  }

  static bool _isAudioCodec(String c) =>
      c.contains('mp4a') ||
      c.contains('ac-3') ||
      c.contains('ec-3') ||
      c.contains('ac-4') ||
      c.contains('flac') ||
      c.contains('opus') ||
      c.contains('vorbis') ||
      c.contains('aac');

  static bool _isVideoCodec(String c) =>
      c.contains('hev1') ||
      c.contains('hvc1') ||
      c.contains('avc1') ||
      c.contains('avc3') ||
      c.contains('vp9') ||
      c.contains('vp09') ||
      c.contains('av01') ||
      c.contains('av1');

  static String _resolveUrl(String baseUrl, String mpdUrl) {
    if (baseUrl.startsWith('http://') || baseUrl.startsWith('https://')) {
      return baseUrl;
    }
    try {
      return Uri.parse(mpdUrl).resolve(baseUrl).toString();
    } catch (_) {
      return '';
    }
  }

  /// 移除所有 ASCII 控制字符（\r \n \t 等），避免 Dio/mpv 抛 FormatException
  static Map<String, String> _sanitizeHeaders(Map<String, String>? raw) {
    if (raw == null) return {};
    final cleaned = <String, String>{};
    for (final e in raw.entries) {
      final v = e.value.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
      if (v.isNotEmpty) cleaned[e.key] = v;
    }
    return cleaned;
  }
}