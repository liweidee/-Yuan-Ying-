import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:yuanying/http/init.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/services/debug_log_service.dart';

/// AppYsV2 服务
/// 对应 TVBox 的 csp_AppYsV2 类型
///
/// 兼容两种接口路径：
///   - /api.php/app/       （App协议）
///   - /api.php/v1.vod/    （V1协议）
///
/// ext 格式：
///   - http://域名/api.php/app/
///   - http://域名/api.php/v1.vod/
///   - http://域名/xxx_api.php/v1.vod
///
/// 通过 ext 中包含的路径片段自动选择协议分支
class AppYsV2Service implements ISpiderService {
  final String _siteKey;
  String _baseUrl = '';
  String _apiPrefix = '';        // 例如：http://xxx.com/api.php/app
  bool _isAppProtocol = true;    // true=/app/, false=/v1.vod/
  String? _currentKey;

  late final Dio _dio;

  AppYsV2Service(this._siteKey, String ext) {
    _dio = HttpClientFactory.dio;
    _dio.options.validateStatus = (status) => true;
    _parseExt(ext);
  }

  /// 解析 ext，提取 baseUrl 和协议类型
  /// ext 可能带 $key$iv 后缀，这里只取第一段
  void _parseExt(String ext) {
    if (ext.isEmpty) return;
    final parts = ext.split('\$');
    String raw = parts[0].trim();
    // 去掉末尾斜杠
    while (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    _baseUrl = raw;

    // 判断协议类型
    if (raw.contains('/api.php/app')) {
      _isAppProtocol = true;
      // 提取前缀（到 api.php/app 为止）
      final idx = raw.indexOf('/api.php/app');
      _apiPrefix = raw.substring(0, idx + '/api.php/app'.length);
    } else if (raw.contains('/api.php/v1.vod')) {
      _isAppProtocol = false;
      final idx = raw.indexOf('/api.php/v1.vod');
      _apiPrefix = raw.substring(0, idx + '/api.php/v1.vod'.length);
    } else if (raw.contains('_api.php/v1.vod')) {
      // 变体：xxx_api.php/v1.vod
      _isAppProtocol = false;
      final idx = raw.indexOf('_api.php/v1.vod');
      _apiPrefix = raw.substring(0, idx + '_api.php/v1.vod'.length);
    } else {
      // 兜底：当作 /app/ 协议，直接拼 api.php/app
      _isAppProtocol = true;
      _apiPrefix = '$_baseUrl/api.php/app';
    }
  }

  @override
  String? get currentKey => _currentKey ?? _siteKey;

  @override
  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    _currentKey = siteKey;
    if (ext is String && ext.isNotEmpty) {
      _parseExt(ext);
    }
  }

  // ========== 网络请求 ==========
  Future<Map<String, dynamic>?> _getJson(String url) async {
    final headers = <String, String>{
      'User-Agent': 'okhttp/3.12.11',
    };

    // 请求日志
    DebugLogService.instance.logRequest(
      method: 'GET',
      url: url,
      headers: headers,
      source: 'appysv2',
    );

    final startTime = DateTime.now();

    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
        ),
      );

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      final raw = response.data?.toString() ?? '';

      // 响应日志
      DebugLogService.instance.logResponse(
        url: url,
        method: 'GET',
        statusCode: response.statusCode,
        responseBody: raw,
        responseSize: raw.length,
        source: 'appysv2',
        durationMs: duration,
      );

      if (response.statusCode != 200) return null;
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      // 异常日志
      DebugLogService.instance.logResponse(
        url: url,
        method: 'GET',
        statusCode: null,
        responseBody: e.toString(),
        source: 'appysv2',
        durationMs: duration,
      );
      print('[AppYsV2Service] _getJson error: $e, url=$url');
      return null;
    }
  }

  // ========== URL 拼接 ==========

  /// 分类列表 URL
  String get _cateUrl {
    if (_isAppProtocol) {
      // /app/ 协议：nav?token=
      return '$_apiPrefix/nav?token=';
    } else {
      // /v1.vod/ 协议：?ac=list
      return '$_apiPrefix/?ac=list';
    }
  }

  /// 视频列表 URL
  String _cateListUrl(String tid, int pg) {
    if (_isAppProtocol) {
      return '$_apiPrefix/video?tid=$tid&pg=$pg';
    } else {
      return '$_apiPrefix/?ac=detail&t=$tid&pg=$pg';
    }
  }

  /// 详情 URL
  String _detailUrl(String id) {
    if (_isAppProtocol) {
      return '$_apiPrefix/video_detail?id=$id';
    } else {
      return '$_apiPrefix/?ac=detail&ids=$id';
    }
  }

  /// 搜索 URL
  String _searchUrl(String wd, int pg) {
    if (_isAppProtocol) {
      return '$_apiPrefix/search?text=${Uri.encodeComponent(wd)}&pg=$pg';
    } else {
      return '$_apiPrefix/?ac=list&wd=${Uri.encodeComponent(wd)}&pg=$pg';
    }
  }

  // ========== ISpiderService 实现 ==========

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    if (_apiPrefix.isEmpty) return {'class': [], 'list': []};

    final cateJson = await _getJson(_cateUrl);
    final classes = <Map<String, dynamic>>[];

    if (cateJson != null) {
      // 结构：{list: [...]} 或 {data: {list: [...]}} 或 {data: {typelist: [...]}} 或 {data: [...]}
      List<dynamic>? rawList;
      if (cateJson['list'] is List) {
        rawList = cateJson['list'] as List;
      } else if (cateJson['data'] is Map) {
        final data = cateJson['data'] as Map;
        if (data['list'] is List) {
          rawList = data['list'] as List;
        } else if (data['typelist'] is List) {
          rawList = data['typelist'] as List;
        }
      } else if (cateJson['data'] is List) {
        rawList = cateJson['data'] as List;
      }

      if (rawList != null) {
        for (final item in rawList) {
          if (item is Map) {
            final m = _asStringMap(item);
            classes.add({
              'type_id': m['type_id']?.toString() ?? '',
              'type_name': m['type_name']?.toString() ?? m['name']?.toString() ?? '',
            });
          }
        }
      }
    }

    return {
      'class': classes,
      'list': [],
      'filters': <String, dynamic>{},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchCate(
    String cateId,
    int page, {
    String? ext,
  }) async {
    if (_apiPrefix.isEmpty) {
      return {'list': [], 'page': page, 'pagecount': 0, 'total': 0};
    }

    // 解析筛选参数
    Map<String, dynamic> filterMap = {};
    if (ext != null && ext.isNotEmpty) {
      try {
        String decodedStr = ext;
        try {
          final decodedBytes = base64Decode(ext);
          decodedStr = utf8.decode(decodedBytes);
        } catch (_) {}
        final parsed = jsonDecode(decodedStr);
        if (parsed is Map) filterMap = Map<String, dynamic>.from(parsed);
      } catch (_) {}
    }

    // 拼接 URL
    String url;
    if (_isAppProtocol) {
      final parts = <String>['tid=$cateId', 'pg=$page'];
      if (filterMap['class'] != null && filterMap['class'].toString().isNotEmpty) {
        parts.add('class=${Uri.encodeComponent(filterMap['class'].toString())}');
      }
      if (filterMap['area'] != null && filterMap['area'].toString().isNotEmpty) {
        parts.add('area=${Uri.encodeComponent(filterMap['area'].toString())}');
      }
      if (filterMap['lang'] != null && filterMap['lang'].toString().isNotEmpty) {
        parts.add('lang=${Uri.encodeComponent(filterMap['lang'].toString())}');
      }
      if (filterMap['year'] != null && filterMap['year'].toString().isNotEmpty) {
        parts.add('year=${Uri.encodeComponent(filterMap['year'].toString())}');
      }
      url = '$_apiPrefix/video?${parts.join('&')}';
    } else {
      final parts = <String>['ac=detail', 't=$cateId', 'pg=$page'];
      if (filterMap['class'] != null && filterMap['class'].toString().isNotEmpty) {
        parts.add('class=${Uri.encodeComponent(filterMap['class'].toString())}');
      }
      if (filterMap['area'] != null && filterMap['area'].toString().isNotEmpty) {
        parts.add('area=${Uri.encodeComponent(filterMap['area'].toString())}');
      }
      if (filterMap['lang'] != null && filterMap['lang'].toString().isNotEmpty) {
        parts.add('lang=${Uri.encodeComponent(filterMap['lang'].toString())}');
      }
      if (filterMap['year'] != null && filterMap['year'].toString().isNotEmpty) {
        parts.add('year=${Uri.encodeComponent(filterMap['year'].toString())}');
      }
      if (filterMap['by'] != null && filterMap['by'].toString().isNotEmpty) {
        parts.add('by=${Uri.encodeComponent(filterMap['by'].toString())}');
      }
      url = '$_apiPrefix/?${parts.join('&')}';
    }

    final json = await _getJson(url);
    final list = _parseVideoList(json);
    return {
      'list': list,
      'page': page,
      'pagecount': list.isNotEmpty ? 999 : 0,
      'total': list.isNotEmpty ? 999 : 0,
    };
  }

  @override
  Future<Map<String, dynamic>> search(
    String wd,
    int page, {
    int quick = 0,
  }) async {
    if (_apiPrefix.isEmpty) return {'list': []};
    final json = await _getJson(_searchUrl(wd, page));
    return {
      'list': _parseVideoList(json),
      'page': page,
    };
  }

  @override
  Future<VideoDetail?> getDetail({
    required String vodId,
    required String pwd,
  }) async {
    if (_apiPrefix.isEmpty) return null;
    final json = await _getJson(_detailUrl(vodId));
    if (json == null) return null;

    // /app/ 协议返回 {data: {...}}
    // /v1.vod/ 协议返回 {list: [{...}]}
    Map<String, dynamic>? dataMap;
    if (json['data'] is Map) {
      dataMap = _asStringMap(json['data']);
    } else if (json['list'] is List && (json['list'] as List).isNotEmpty) {
      dataMap = _asStringMap((json['list'] as List).first);
    }
    if (dataMap == null) return null;

    return _buildVideoDetail(dataMap, vodId);
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    if (_apiPrefix.isEmpty) return {'list': []};
    return await _getJson(_detailUrl(ids)) ?? {'list': []};
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    if (playParams.isEmpty) return null;
    // 直链直接返回
    if (playParams.startsWith('http')) {
      return PlayUrl.fromJson({'parse': 0, 'url': playParams});
    }
    // 非直链走嗅探
    return PlayUrl.fromJson({'parse': 1, 'url': playParams, 'jx': 1});
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(
    String play, {
    String? flag,
  }) async {
    if (play.startsWith('http')) {
      return {'url': play, 'parse': 0};
    }
    return {'url': play, 'parse': 1, 'jx': 1};
  }

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) async {
    // 用临时 ext 解析出 prefix
    String tempExt = ext is String ? ext : '';
    if (tempExt.isEmpty) return {'list': []};

    final parts = tempExt.split('\$');
    String raw = parts[0].trim();
    while (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }

    String url;
    if (raw.contains('/api.php/app')) {
      url = '$raw/search?text=${Uri.encodeComponent(wd)}&pg=$page';
    } else if (raw.contains('/api.php/v1.vod')) {
      url = '$raw/?ac=list&wd=${Uri.encodeComponent(wd)}&pg=$page';
    } else {
      url = '$raw/api.php/app/search?text=${Uri.encodeComponent(wd)}&pg=$page';
    }
    final json = await _getJson(url);
    return {
      'list': _parseVideoList(json),
      'page': page,
    };
  }

  // ========== 辅助方法 ==========

  List<Map<String, dynamic>> _parseVideoList(Map<String, dynamic>? json) {
    if (json == null) return [];
    List<dynamic>? rawList;
    if (json['list'] is List) {
      rawList = json['list'] as List;
    } else if (json['data'] is List) {
      rawList = json['data'] as List;
    } else if (json['data'] is Map && json['data']['list'] is List) {
      rawList = json['data']['list'] as List;
    }
    if (rawList == null) return [];

    final result = <Map<String, dynamic>>[];
    for (final item in rawList) {
      if (item is Map) {
        final m = _asStringMap(item);
        result.add({
          'vod_id': m['vod_id']?.toString() ?? m['nextlink']?.toString() ?? '',
          'vod_name': m['vod_name']?.toString() ?? m['title']?.toString() ?? '',
          'vod_pic': m['vod_pic']?.toString() ?? m['pic']?.toString() ?? '',
          'vod_remarks': m['vod_remarks']?.toString() ?? m['state']?.toString() ?? '',
        });
      }
    }
    return result;
  }

  /// 从详情 JSON 构建 VideoDetail
  /// 关键：处理 vod_url_with_player 数组，拼接成 vod_play_from / vod_play_url
  VideoDetail _buildVideoDetail(Map<String, dynamic> data, String fallbackId) {
    final vodId = data['vod_id']?.toString() ?? fallbackId;
    final vodName = data['vod_name']?.toString() ?? '';
    final vodPic = data['vod_pic']?.toString() ?? '';
    final vodContent = data['vod_content']?.toString();
    final vodActor = data['vod_actor']?.toString();
    final vodDirector = data['vod_director']?.toString();
    final vodYear = data['vod_year']?.toString();
    final vodArea = data['vod_area']?.toString();
    final vodRemarks = data['vod_remarks']?.toString();

    // 线路拼接
    final playFlags = <String>[];
    final playUrls = <String>[];

    final vodUrlWithPlayer = data['vod_url_with_player'];
    if (vodUrlWithPlayer is List && vodUrlWithPlayer.isNotEmpty) {
      for (final item in vodUrlWithPlayer) {
        if (item is! Map) continue;
        final m = _asStringMap(item);
        String flag = m['code']?.toString().trim() ?? '';
        if (flag.isEmpty) {
          flag = m['name']?.toString().trim() ?? '';
        }
        if (flag.isEmpty) flag = '线路${playFlags.length + 1}';

        final url = m['url']?.toString() ?? '';
        if (url.isEmpty) continue;

        playFlags.add(flag);
        playUrls.add(url);
      }
    } else {
      // 兜底：直接用 vod_play_from / vod_play_url
      final from = data['vod_play_from']?.toString() ?? '';
      final urlStr = data['vod_play_url']?.toString() ?? '';
      if (from.isNotEmpty && urlStr.isNotEmpty) {
        return VideoDetail(
          vodId: vodId,
          vodName: vodName,
          vodPic: vodPic,
          vodRemarks: vodRemarks,
          vodActor: vodActor,
          vodContent: vodContent,
          vodDirector: vodDirector,
          vodYear: vodYear,
          vodArea: vodArea,
          vodPlayUrl: urlStr,
          playSources: _parsePlaySources(from, urlStr),
        );
      }
    }

    final vodPlayFrom = playFlags.join(r'$$$');
    final vodPlayUrl = playUrls.join(r'$$$');

    return VideoDetail(
      vodId: vodId,
      vodName: vodName,
      vodPic: vodPic,
      vodRemarks: vodRemarks,
      vodActor: vodActor,
      vodContent: vodContent,
      vodDirector: vodDirector,
      vodYear: vodYear,
      vodArea: vodArea,
      vodPlayUrl: vodPlayUrl,
      playSources: _parsePlaySources(vodPlayFrom, vodPlayUrl),
    );
  }

  List<PlaySource> _parsePlaySources(String from, String url) {
    if (from.isEmpty || url.isEmpty) return [];
    final fromList = from.split(r'$$$');
    final urlList = url.split(r'$$$');
    final sources = <PlaySource>[];
    for (int i = 0; i < fromList.length && i < urlList.length; i++) {
      final episodes = _parseEpisodes(urlList[i]);
      if (episodes.isNotEmpty) {
        sources.add(PlaySource(name: fromList[i], episodes: episodes));
      }
    }
    return sources;
  }

  List<Episode> _parseEpisodes(String urlStr) {
    final episodes = <Episode>[];
    if (urlStr.isEmpty) return episodes;
    for (final part in urlStr.split('#')) {
      if (part.trim().isEmpty) continue;
      final idx = part.indexOf('\$');
      if (idx != -1) {
        final name = part.substring(0, idx);
        final url = part.substring(idx + 1);
        if (url.isNotEmpty) {
          episodes.add(Episode(name: name, url: url));
        }
      } else {
        episodes.add(Episode(name: part, url: part));
      }
    }
    return episodes;
  }

  Map<String, dynamic> _asStringMap(dynamic item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) {
      final m = <String, dynamic>{};
      item.forEach((k, v) {
        m[k.toString()] = v;
      });
      return m;
    }
    return {};
  }
}