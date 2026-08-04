import 'package:dio/dio.dart';
import 'package:yuanying/http/init.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';

class VideoApiService {
  // final Dio _dio = Dio();
  final Dio _dio = HttpClientFactory.dio;  // 已包含 15s/30s 超时
  String _baseUrl = '';

  void setBaseUrl(String url) {
    _baseUrl = url;
    print('VideoApiService._baseUrl 已设置为: $_baseUrl');
  }

  String get baseUrl => _baseUrl;

  /// 获取视频详情（严格按接口文档）
  Future<VideoDetail?> getDetail({
    required String vodId,
    required String pwd,
  }) async {
    if (_baseUrl.isEmpty) {
      print('getDetail: _baseUrl 为空，无法请求');
      return null;
    }

    // 构建请求 URL，如果 _baseUrl 已经包含 pwd，则不再重复添加
    final uri = Uri.parse(_baseUrl);
    final queryParams = Map<String, dynamic>.from(uri.queryParameters);
    queryParams['ac'] = 'detail';
    queryParams['ids'] = vodId;
    // 如果原 URL 中没有 pwd，则加上
    if (!queryParams.containsKey('pwd')) {
      queryParams['pwd'] = pwd;
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

  /// 获取播放地址（严格按接口文档）
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    if (_baseUrl.isEmpty) {
      print('getPlayUrl: _baseUrl 为空');
      return null;
    }

    final uri = Uri.parse(_baseUrl);
    final queryParams = Map<String, dynamic>.from(uri.queryParameters);
    queryParams['ac'] = 'play';
    queryParams['play'] = playParams;
    queryParams['flag'] = flag;
    if (!queryParams.containsKey('pwd')) {
      queryParams['pwd'] = pwd;
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
}