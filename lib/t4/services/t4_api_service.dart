import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:yuanying/http/init.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';

class T4ApiService implements ISpiderService {
  late Dio _dio;
  String? _baseUrl;
  String? _currentKey;
  dynamic _ext;

  // T4ApiService() {
  //   _dio = Dio(BaseOptions(
  //     connectTimeout: const Duration(seconds: 15),
  //     receiveTimeout: const Duration(seconds: 30),
  //   ));
  // }

  T4ApiService() {
    _dio = HttpClientFactory.dio;  // 已包含 15s/30s 超时
    _dio.options.validateStatus = (status) => true;
  }

  void setBaseUrl(String url) {
    _baseUrl = url;
    print('T4ApiService._baseUrl 已设置为: $_baseUrl');
  }

  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    print('switchSite 被调用: apiUrl=$apiUrl, siteKey=$siteKey');
    _baseUrl = apiUrl;
    _currentKey = siteKey;
    _ext = ext;
    print('_baseUrl 已设置为: $_baseUrl');
    print('_ext 类型: ${_ext.runtimeType}');
  }

  String? get currentKey => _currentKey;
  bool get hasSite => _baseUrl != null && _baseUrl!.isNotEmpty;

  // 只负责将 _ext 转为 JSON 字符串，不编码
  String? _getExtJson() {
    if (_ext == null) return null;

    if (_ext is Map) {
      // Map → JSON 字符串
      return jsonEncode(_ext);
    } else if (_ext is String) {
      final str = _ext as String;
      if (str.isEmpty) return null;
      // 已经是 JSON 字符串，直接返回
      return str;
    } else {
      return _ext.toString();
    }
  }

  // ===== 获取当前站点 extend 的 JSON 字符串 =====
  String? getExtend() {
    return _getExtJson();
  }

  String _buildUrl(Map<String, dynamic>? params) {
    if (_baseUrl == null) throw Exception('请先配置接口源');
    if (params == null || params.isEmpty) return _baseUrl!;
    final uri = Uri.parse(_baseUrl!);

    final Map<String, String> allParams = {};
    uri.queryParameters.forEach((key, value) {
      allParams[key] = value;
    });
    params.forEach((key, value) {
      if (value != null) {
        allParams[key] = value.toString();
      }
    });

    // Uri.replace 会自动进行 URL 编码，只编码一次
    return uri.replace(queryParameters: allParams).toString();
  }

  Future<Map<String, dynamic>> _get(Map<String, dynamic> params) async {
    if (!hasSite) {
      print('_get: 未配置接口源');
      return {'list': []};
    }
    try {
      final Map<String, dynamic> stringParams = {};
      params.forEach((key, value) {
        stringParams[key] = value.toString();
      });

      final url = _buildUrl(stringParams);
      print('_get 请求URL: $url');
      final response = await _dio.get(url);
      print('_get 响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        if (response.data is Map<String, dynamic>) {
          return response.data;
        } else if (response.data is List) {
          return {'list': response.data};
        } else {
          print('_get 返回其他类型: ${response.data}');
          return {'list': []};
        }
      } else {
        print('_get 非 200 状态码: ${response.statusCode}，返回空列表');
        return {'list': []};
      }
    } catch (e) {
      print('_get 异常: $e');
      return {'list': []};
    }
  }

  // Future<Map<String, dynamic>> fetchConfig({String? configUrl}) async {
  //   final url = configUrl ?? _baseUrl;
  //   if (url == null || url.isEmpty) {
  //     throw Exception('请先配置接口源');
  //   }
  //   try {
  //     final response = await _dio.get(url);
  //     if (response.statusCode == 200) return response.data;
  //     throw Exception('获取配置失败');
  //   } catch (e) {
  //     throw Exception('获取配置失败: $e');
  //   }
  // }

  Future<Map<String, dynamic>> fetchConfig({String? configUrl}) async {
    final url = configUrl ?? _baseUrl;
    if (url == null || url.isEmpty) {
      throw Exception('请先配置接口源');
    }
    try {
      // 使用 ResponseType.plain 避免自动解析（兼容 Brotli 压缩）
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
        ),
      );
      if (response.statusCode == 200) {
        final rawData = response.data.toString();
        try {
          final decoded = jsonDecode(rawData);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          } else {
            throw Exception('配置数据格式错误：期望 Map 类型');
          }
        } catch (e) {
          throw Exception('JSON解析失败: $e');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('获取配置失败: $e');
    }
  }

  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    final params = <String, dynamic>{'filter': filter};
    final extJson = _getExtJson();
    if (extJson != null && extJson.isNotEmpty) {
      params['extend'] = extJson;
    }
    return await _get(params);
  }

  Future<Map<String, dynamic>> fetchCate(String cateId, int page, {String? ext}) async {
    final params = <String, dynamic>{'ac': 'list', 't': cateId, 'pg': page};
    if (ext != null && ext.isNotEmpty) {
      params['ext'] = ext;
    }
    final extJson = _getExtJson();
    if (extJson != null && extJson.isNotEmpty) {
      params['extend'] = extJson;
    }
    return await _get(params);
  }

  Future<Map<String, dynamic>> search(String wd, int page, {int quick = 0}) async {
    final params = <String, dynamic>{'wd': wd, 'pg': page, 'quick': quick};
    final extJson = _getExtJson();
    if (extJson != null && extJson.isNotEmpty) {
      params['extend'] = extJson;
    }
    return await _get(params);
  }

  // ===== 获取视频详情 =====
  Future<VideoDetail?> getDetail({
    required String vodId,
    required String pwd,
  }) async {
    if (_baseUrl == null || _baseUrl!.isEmpty) {
      print('getDetail: _baseUrl 为空，无法请求');
      return null;
    }

    final uri = Uri.parse(_baseUrl!);
    final queryParams = Map<String, dynamic>.from(uri.queryParameters);
    queryParams['ac'] = 'detail';
    queryParams['ids'] = vodId;
    if (!queryParams.containsKey('pwd')) {
      queryParams['pwd'] = pwd;
    }
    final extJson = _getExtJson();
    if (extJson != null && extJson.isNotEmpty) {
      queryParams['extend'] = extJson;
    }
    final requestUrl = uri.replace(queryParameters: queryParams).toString();

    print('getDetail 请求URL: $requestUrl');

    try {
      final response = await _dio.get(requestUrl);
      print('getDetail 响应状态码: ${response.statusCode}');
      print('getDetail 响应数据: ${response.data}');

      final data = response.data;
      if (data is Map && data['list'] is List && data['list'].isNotEmpty) {
        return VideoDetail.fromJson(data['list'][0]);
      }
      print('getDetail: 响应数据中没有 list 或 list 为空');
      return null;
    } catch (e) {
      print('getDetail 异常: $e');
      return null;
    }
  }

  // ===== 获取播放地址 =====
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    if (_baseUrl == null || _baseUrl!.isEmpty) {
      print('getPlayUrl: _baseUrl 为空');
      return null;
    }

    final uri = Uri.parse(_baseUrl!);
    final queryParams = Map<String, dynamic>.from(uri.queryParameters);
    queryParams['ac'] = 'play';
    queryParams['play'] = playParams;
    queryParams['flag'] = flag;
    if (!queryParams.containsKey('pwd')) {
      queryParams['pwd'] = pwd;
    }
    final extJson = _getExtJson();
    if (extJson != null && extJson.isNotEmpty) {
      queryParams['extend'] = extJson;
    }
    final requestUrl = uri.replace(queryParameters: queryParams).toString();

    print('getPlayUrl 请求URL: $requestUrl');

    try {
      final response = await _dio.get(requestUrl);
      print('getPlayUrl 响应状态码: ${response.statusCode}');
      final data = response.data;
      if (data != null) {
        return PlayUrl.fromJson(data);
      }
      return null;
    } catch (e) {
      print('getPlayUrl 异常: $e');
      return null;
    }
  }

  // ===== 获取视频详情（返回 Map） =====
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    final params = <String, dynamic>{'ac': 'detail', 'ids': ids};
    final extJson = _getExtJson();
    if (extJson != null && extJson.isNotEmpty) {
      params['extend'] = extJson;
    }
    final data = await _get(params);
    if (data is List && data.isNotEmpty) return data[0];
    return data;
  }

  // ===== 获取播放地址（返回 Map） =====
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) async {
    final params = {'play': play};
    if (flag != null && flag.isNotEmpty) params['flag'] = flag;
    final extJson = _getExtJson();
    if (extJson != null && extJson.isNotEmpty) {
      params['extend'] = extJson;
    }
    return await _get(params);
  }

  // ===== 独立搜索（不依赖全局状态，用于多源聚合搜索） =====
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) async {
    print('searchDirect 被调用: baseUrl=$baseUrl, wd=$wd, page=$page');

    final uri = Uri.parse(baseUrl);
    // 确保所有值都是 String
    final queryParams = <String, String>{};
    uri.queryParameters.forEach((key, value) {
      queryParams[key] = value.toString();
    });

    queryParams['wd'] = wd;
    queryParams['pg'] = page.toString();
    queryParams['quick'] = quick.toString();

    if (ext != null) {
      if (ext is Map) {
        queryParams['extend'] = jsonEncode(ext);
      } else if (ext is String && ext.isNotEmpty) {
        queryParams['extend'] = ext;
      }
    }

    final requestUrl = uri.replace(queryParameters: queryParams).toString();
    print('searchDirect 请求URL: $requestUrl');

    try {
      final response = await _dio.get(requestUrl);
      print('searchDirect 响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }

      if (data is List) {
        return {'list': data};
      }

      throw Exception('响应格式异常: ${data.runtimeType}');
    } catch (e) {
      print('searchDirect 异常: $e');
      rethrow;
    }
  }
}