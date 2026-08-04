import 'package:dio/dio.dart';

import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/services/video_api_service.dart';
import 'resource_sniffer.dart';

/// 解析源配置
class ParserSource {
  final String name;
  final String url;
  final int type; // 0=嗅探, 1=JSON直接取
  final Map<String, String>? headers;

  ParserSource({
    required this.name,
    required this.url,
    required this.type,
    this.headers,
  });

  factory ParserSource.fromJson(Map<String, dynamic> json) {
    return ParserSource(
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      type: json['type'] ?? 0,
      headers: json['header'] != null
          ? Map<String, String>.from(json['header'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'type': type,
      if (headers != null) 'header': headers,
    };
  }
}

/// 解析服务 - 处理 parse:1 和 jx:1 场景
class ParserService {
  final VideoApiService _apiService;
  final Dio _dio = Dio();

  ParserService(this._apiService);

  /// 处理解析播放
  Future<PlayUrlResult?> process({
    required String playParams,
    required String flag,
    required String pwd,
    required List<ParserSource> parsers,
    ParserSource? selectedParser,
  }) async {
    // 1. 获取播放接口返回
    final result = await _apiService.getPlayUrl(
      playParams: playParams,
      flag: flag,
      pwd: pwd,
    );

    if (result == null) return null;

    // 2. 如果是直链 (parse: 0)，直接返回
    if (result.parse == 0) {
      return PlayUrlResult.direct(
        playUrl: result,
        usedParser: null,
      );
    }

    // 3. 如果需要嗅探 (parse: 1)
    if (result.parse == 1) {
      final defaultUrl = result.defaultUrl;
      if (defaultUrl == null) return null;
      final url = await ResourceSniffer.sniff(
        url: defaultUrl,
        headers: result.headers,
      );
      if (url != null) {
        return PlayUrlResult.direct(
          playUrl: PlayUrl(
            parse: 0,
            qualities: [PlayQuality(label: '默认', url: url)],
            headers: result.headers,
          ),
          usedParser: null,
        );
      }
      return null;
    }

    // 4. 如果需要解析 (jx: 1)
    if (result.jx == 1) {
      // 使用选中的解析源，如果没有则使用第一个
      final parser = selectedParser ?? parsers.firstOrNull;
      if (parser == null) return null;

      final parsed = await _parseWithParser(result.defaultUrl ?? '', parser);
      if (parsed != null) {
        return PlayUrlResult.parsed(
          playUrl: parsed,
          usedParser: parser,
        );
      }
      return null;
    }

    return null;
  }

  /// 使用解析源获取播放地址
  Future<PlayUrl?> _parseWithParser(String url, ParserSource parser) async {
    try {
      final fullUrl = '${parser.url}${Uri.encodeComponent(url)}';

      // type: 1 - JSON 直接取 url
      if (parser.type == 1) {
        final response = await _dio.get(
          fullUrl,
          options: Options(
            headers: parser.headers ?? {},
          ),
        );
        final data = response.data;
        if (data is Map) {
          final playUrl = data['url']?.toString() ??
              data['playUrl']?.toString() ??
              data['play_url']?.toString();
          if (playUrl != null && playUrl.startsWith('http')) {
            return PlayUrl(
              parse: 0,
              qualities: [PlayQuality(label: '解析', url: playUrl)],
              headers: parser.headers,
            );
          }
        }
        return null;
      }

      // type: 0 - 需要嗅探（使用 ResourceSniffer）
      final sniffedUrl = await ResourceSniffer.sniff(
        url: fullUrl,
        headers: parser.headers,
        useWebView: true,
      );
      if (sniffedUrl != null) {
        return PlayUrl(
          parse: 0,
          qualities: [PlayQuality(label: '解析', url: sniffedUrl)],
          headers: parser.headers,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

/// 播放URL处理结果
class PlayUrlResult {
  final PlayUrl playUrl;
  final ParserSource? usedParser;
  final bool isParsed;

  const PlayUrlResult._({
    required this.playUrl,
    this.usedParser,
    required this.isParsed,
  });

  factory PlayUrlResult.direct({
    required PlayUrl playUrl,
    ParserSource? usedParser,
  }) {
    return PlayUrlResult._(
      playUrl: playUrl,
      usedParser: usedParser,
      isParsed: false,
    );
  }

  factory PlayUrlResult.parsed({
    required PlayUrl playUrl,
    required ParserSource usedParser,
  }) {
    return PlayUrlResult._(
      playUrl: playUrl,
      usedParser: usedParser,
      isParsed: true,
    );
  }
}