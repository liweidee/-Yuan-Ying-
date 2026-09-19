import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:yuanying/http/init.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/services/debug_log_service.dart';

/// 苹果CMS标准协议服务
/// 对应 TVBox 的 csp_CMS 类型
///
/// ext 格式：
///   - 纯域名：https://www.ttmja.com
///   - 域名$参数：https://www.ttmja.com$其他
///
/// 接口约定：
///   分类列表：{base}/api.php/provide/vod/?ac=list
///   视频列表：{base}/api.php/provide/vod/?ac=detail&t={tid}&pg={pg}
///   视频详情：{base}/api.php/provide/vod/?ac=detail&ids={id}
///   搜索：    {base}/api.php/provide/vod/?ac=list&wd={wd}&pg={pg}
class AppCmsService implements ISpiderService {
  final String _siteKey;
  String _baseUrl = '';
  String? _currentKey;

  late final Dio _dio;

  AppCmsService(this._siteKey, String ext) {
    _dio = HttpClientFactory.dio;
    _dio.options.validateStatus = (status) => true;
    _parseExt(ext);
  }

  /// 解析 ext，提取 baseUrl
  /// ext 可能为：域名 或 域名$参数
  void _parseExt(String ext) {
    if (ext.isEmpty) return;
    final parts = ext.split('\$');
    _baseUrl = parts[0].trim();
    // 去掉末尾斜杠，统一拼接
    while (_baseUrl.endsWith('/')) {
      _baseUrl = _baseUrl.substring(0, _baseUrl.length - 1);
    }
  }

  /// 拼接 API 基础路径
  /// 苹果CMS标准路径固定为 /api.php/provide/vod/
  String get _apiBase {
    if (_baseUrl.isEmpty) return '';
    // 如果 ext 已经带了 /api.php/provide/vod/，直接用
    if (_baseUrl.contains('/api.php/provide/vod')) {
      return _baseUrl;
    }
    return '$_baseUrl/api.php/provide/vod/';
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
    // csp_CMS 的 ext 才是真实域名，apiUrl 恒为 'csp_CMS'
    if (ext is String && ext.isNotEmpty) {
      _parseExt(ext);
    }
  }

  // ========== 网络请求 ==========
  Future<Map<String, dynamic>?> _getJson(String url) async {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
    };

    // 请求日志
    DebugLogService.instance.logRequest(
      method: 'GET',
      url: url,
      headers: headers,
      source: 'appcms',
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
        source: 'appcms',
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
        source: 'appcms',
        durationMs: duration,
      );
      print('[AppCmsService] _getJson error: $e, url=$url');
      return null;
    }
  }

  // ========== ISpiderService 实现 ==========

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    if (_apiBase.isEmpty) return {'class': [], 'list': []};

    // 1. 获取分类列表
    final cateUrl = '${_apiBase}?ac=list';
    final cateJson = await _getJson(cateUrl);
    final classes = <Map<String, dynamic>>[];
    if (cateJson != null && cateJson['class'] is List) {
      for (final item in cateJson['class']) {
        if (item is Map) {
          classes.add({
            'type_id': item['type_id']?.toString() ?? '',
            'type_name': item['type_name']?.toString() ?? '',
          });
        }
      }
    }

    // 2. 首页推荐列表（苹果CMS标准接口没有独立推荐，返回空）
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
    if (_apiBase.isEmpty) {
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

    final params = <String, String>{
      'ac': 'detail',
      't': cateId,
      'pg': page.toString(),
    };
    // 苹果CMS支持的筛选字段
    if (filterMap['class'] != null && filterMap['class'].toString().isNotEmpty) {
      params['class'] = filterMap['class'].toString();
    }
    if (filterMap['area'] != null && filterMap['area'].toString().isNotEmpty) {
      params['area'] = filterMap['area'].toString();
    }
    if (filterMap['lang'] != null && filterMap['lang'].toString().isNotEmpty) {
      params['lang'] = filterMap['lang'].toString();
    }
    if (filterMap['year'] != null && filterMap['year'].toString().isNotEmpty) {
      params['year'] = filterMap['year'].toString();
    }
    if (filterMap['by'] != null && filterMap['by'].toString().isNotEmpty) {
      params['by'] = filterMap['by'].toString();
    }

    final uri = Uri.parse('${_apiBase}?ac=list').replace(
      queryParameters: params,
    );
    // 注意：上面的 Uri 替换会丢掉原 query，这里手动拼接
    final query = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final finalUrl = '${_apiBase}?$query';

    final json = await _getJson(finalUrl);
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
    if (_apiBase.isEmpty) return {'list': []};
    final url = '${_apiBase}?ac=list&wd=${Uri.encodeComponent(wd)}&pg=$page';
    final json = await _getJson(url);
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
    if (_apiBase.isEmpty) return null;
    final url = '${_apiBase}?ac=detail&ids=$vodId';
    final json = await _getJson(url);
    if (json == null) return null;
    final list = json['list'];
    if (list is List && list.isNotEmpty) {
      final dataMap = _asStringMap(list[0]);
      return VideoDetail.fromJson(dataMap);
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    if (_apiBase.isEmpty) return {'list': []};
    final url = '${_apiBase}?ac=detail&ids=$ids';
    return await _getJson(url) ?? {'list': []};
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    // 苹果CMS的播放地址是直链，直接返回
    if (playParams.isEmpty) return null;
    final data = <String, dynamic>{
      'parse': 0,
      'url': playParams,
    };
    return PlayUrl.fromJson(data);
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(
    String play, {
    String? flag,
  }) async {
    return {
      'url': play,
      'parse': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) async {
    // 用临时 ext 解析 baseUrl
    String tempBase = baseUrl;
    if (ext is String && ext.isNotEmpty) {
      final parts = ext.split('\$');
      tempBase = parts[0].trim();
      while (tempBase.endsWith('/')) {
        tempBase = tempBase.substring(0, tempBase.length - 1);
      }
    }
    if (tempBase.isEmpty) return {'list': []};
    final url = '$tempBase/api.php/provide/vod/?ac=list'
        '&wd=${Uri.encodeComponent(wd)}&pg=$page';
    final json = await _getJson(url);
    return {
      'list': _parseVideoList(json),
      'page': page,
    };
  }

  // ========== 辅助方法 ==========

  List<Map<String, dynamic>> _parseVideoList(Map<String, dynamic>? json) {
    if (json == null) return [];
    final listData = json['list'];
    if (listData is! List) return [];
    final result = <Map<String, dynamic>>[];
    for (final item in listData) {
      if (item is Map) {
        final m = _asStringMap(item);
        result.add({
          'vod_id': m['vod_id']?.toString() ?? '',
          'vod_name': m['vod_name']?.toString() ?? '',
          'vod_pic': m['vod_pic']?.toString() ?? m['vod_pic_thumb']?.toString() ?? '',
          'vod_remarks': m['vod_remarks']?.toString() ?? '',
        });
      }
    }
    return result;
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