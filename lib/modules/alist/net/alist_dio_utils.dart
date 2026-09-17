import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import '../models/alist_resp_models.dart';
import 'alist_auth_interceptor.dart';
import 'alist_net_error_handler.dart';

typedef AlistSuccessCallback<T> = void Function(T data);
typedef AlistErrorCallback = void Function(int code, String msg);

enum AlistMethod { get, post, put, patch, delete, head }

extension AlistMethodExt on AlistMethod {
  String get value => ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'][index];
}

/// AList 专用网络工具（独立于源影的 HttpClientFactory）
class AlistDioUtils {
  AlistDioUtils._();
  static final AlistDioUtils instance = AlistDioUtils._();

  late Dio _dio;
  final Dio _streamDio = Dio();

  String _baseUrl = '';
  bool _ignoreSSLError = false;
  final AlistAuthInterceptor _authInterceptor = AlistAuthInterceptor();

  bool _initialized = false;

  /// 切换服务器时调用
  void configAgain(String baseUrl, bool ignoreSSLError, {String? serverId}) {
    _baseUrl = baseUrl;
    _ignoreSSLError = ignoreSSLError;
    _authInterceptor.currentServerId = serverId;
    _init();
  }

  void _init() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ));

    if (_ignoreSSLError) {
      final adapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient()
            ..idleTimeout = const Duration(seconds: 3);
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        },
      );
      _dio.httpClientAdapter = adapter;
      _streamDio.httpClientAdapter = adapter;
    }

    _dio.interceptors.add(_authInterceptor);
    _initialized = true;
  }

  void _ensureInit() {
    if (!_initialized) {
      _init();
    }
  }

  /// 通用请求方法
  Future<void> requestNetwork<T>(
    AlistMethod method,
    String url, {
    AlistSuccessCallback<T?>? onSuccess,
    AlistErrorCallback? onError,
    Object? params,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
    T Function(dynamic)? decoder,
  }) async {
    _ensureInit();
    try {
      final resp = await _dio.request<String>(
        url,
        data: params,
        queryParameters: queryParameters,
        options: _checkOptions(method, options),
        cancelToken: cancelToken,
      );

      // 重定向
      if (options?.followRedirects == false &&
          (resp.statusCode == 301 ||
              resp.statusCode == 302 ||
              resp.statusCode == 307 ||
              resp.statusCode == 308)) {
        final location = resp.headers.value('location');
        if (location != null && location.isNotEmpty) {
          throw AlistRedirectException(location);
        }
      }

      if (resp.statusCode == 404) {
        onError?.call(404, 'HTTP 404 Not Found');
        return;
      }

      final raw = resp.data;
      if (raw == null || raw is! String) {
        onError?.call(-1, '响应数据为空');
        return;
      }

      // JSON 解析
      final Map<String, dynamic> json;
      try {
        if (raw.length > 10 * 1024 && !kIsWeb) {
          json = await compute(_parseData, raw);
        } else {
          json = jsonDecode(raw) as Map<String, dynamic>;
        }
      } catch (e) {
        throw AlistJsonParseException(e.toString());
      }

      final int code = json['code'] as int? ?? -1;
      if (code == 200) {
        if (onSuccess != null) {
          if (decoder != null) {
            onSuccess(decoder(json['data']));
          } else {
            // T 为空时直接忽略
            onSuccess(null);
          }
        }
      } else {
        onError?.call(code, json['message'] as String? ?? '请求失败');
      }
    } catch (e) {
      final code = e is AlistRedirectException ? 301 : -1;
      onError?.call(code, AlistNetErrorHandler.toMessage(e));
    }
  }

  /// 带泛型解码的请求（返回单个对象）
  Future<T?> request<T>(
    AlistMethod method,
    String url, {
    Object? params,
    Map<String, dynamic>? queryParameters,
    required T Function(Map<String, dynamic>) decoder,
    CancelToken? cancelToken,
    Options? options,
  }) async {
    _ensureInit();
    final resp = await _dio.request<String>(
      url,
      data: params,
      queryParameters: queryParameters,
      options: _checkOptions(method, options),
      cancelToken: cancelToken,
    );

    if (resp.statusCode == 301 ||
        resp.statusCode == 302 ||
        resp.statusCode == 307 ||
        resp.statusCode == 308) {
      final location = resp.headers.value('location');
      throw AlistRedirectException(location ?? '');
    }

    final raw = resp.data;
    if (raw == null || raw is! String) {
      throw AlistJsonParseException('响应数据为空');
    }

    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    final int code = json['code'] as int? ?? -1;
    if (code == 200) {
      final data = json['data'];
      if (data is Map<String, dynamic>) {
        return decoder(data);
      }
      return null;
    }
    throw AlistNetException(code, json['message'] as String? ?? '请求失败');
  }

  /// 下载（用于 AlistDownloadManager）
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    Options? options,
  }) {
    _ensureInit();
    final url = urlPath.startsWith('http://') || urlPath.startsWith('https://')
        ? urlPath
        : '$_baseUrl$urlPath';
    return _streamDio.download(
      url,
      savePath,
      onReceiveProgress: onReceiveProgress,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      deleteOnError: deleteOnError,
      lengthHeader: lengthHeader,
      options: options,
    );
  }

  Options _checkOptions(AlistMethod method, Options? options) {
    options ??= Options();
    options.method = method.value;
    return options;
  }

  /// 便捷方法：登录（无 token）
  Future<AlistLoginResp> login({
    required String serverUrl,
    required String username,
    required String password,
    String? otpCode,
    bool ignoreSSLError = false,
  }) async {
    // 登录用临时 Dio（因为 baseUrl 是 serverUrl + api/）
    final dio = Dio(BaseOptions(
      baseUrl: '${serverUrl}api/',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ));

    if (ignoreSSLError) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient()
            ..idleTimeout = const Duration(seconds: 3);
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        },
      );
    }

    final resp = await dio.post(
      'auth/login',
      data: {
        'username': username,
        'password': password,
        if (otpCode != null && otpCode.isNotEmpty) 'otp_code': otpCode,
      },
      options: Options(headers: {'alist_no_auth': 1}),
    );

    if (resp.statusCode == 301 ||
        resp.statusCode == 302 ||
        resp.statusCode == 307 ||
        resp.statusCode == 308) {
      final location = resp.headers.value('location');
      throw AlistRedirectException(location ?? '服务器重定向');
    }

    final raw = resp.data;
    if (raw is! String) {
      throw AlistJsonParseException('响应格式错误');
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final code = json['code'] as int? ?? -1;
    if (code != 200) {
      throw AlistNetException(code, json['message'] as String? ?? '登录失败');
    }
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw AlistJsonParseException('登录响应格式错误');
    }
    return AlistLoginResp.fromJson(data);
  }

  /// 便捷方法：获取当前用户信息
  Future<AlistMyInfoResp> getMyInfo() async {
    final result = await request(
      AlistMethod.get,
      'me',
      decoder: AlistMyInfoResp.fromJson,
      options: Options(followRedirects: false, headers: {'alist_no_auth': 1}),
    );
    if (result == null) {
      throw AlistNetException(-1, '无法获取用户信息');
    }
    return result;
  }

  /// 便捷方法：公共设置
  Future<AlistPublicSettingsResp?> getPublicSettings() async {
    try {
      return await request(
        AlistMethod.get,
        'public/settings',
        decoder: AlistPublicSettingsResp.fromJson,
      );
    } catch (_) {
      return null;
    }
  }

  /// 便捷方法：列出目录
  Future<AlistFileListResp> listDir({
    required String path,
    String password = '',
    bool refresh = false,
  }) async {
    final result = await request(
      AlistMethod.post,
      'fs/list',
      params: {
        'path': path,
        'password': password,
        'page': 1,
        'per_page': 0,
        'refresh': refresh,
      },
      decoder: AlistFileListResp.fromJson,
    );
    if (result == null) {
      throw AlistNetException(-1, '无法获取文件列表');
    }
    return result;
  }

  /// 便捷方法：获取文件信息（含 raw_url）
  Future<AlistFileInfoResp> getFileInfo({
    required String path,
    String password = '',
  }) async {
    final result = await request(
      AlistMethod.post,
      'fs/get',
      params: {'path': path, 'password': password},
      decoder: AlistFileInfoResp.fromJson,
    );
    if (result == null) {
      throw AlistNetException(-1, '无法获取文件信息');
    }
    return result;
  }

  /// 便捷方法：搜索
  Future<AlistFileSearchResp> search({
    required String parent,
    required String keywords,
    String password = '',
    int scope = 0,
    int page = 1,
    int perPage = 100,
  }) async {
    final result = await request(
      AlistMethod.post,
      'fs/search',
      params: {
        'parent': parent,
        'keywords': keywords,
        'scope': scope,
        'page': page,
        'per_page': perPage,
        'password': password,
      },
      decoder: AlistFileSearchResp.fromJson,
    );
    if (result == null) {
      throw AlistNetException(-1, '搜索失败');
    }
    return result;
  }

  /// 便捷方法：mkdir
  Future<void> mkdir(String path) async {
    await request<dynamic>(
      AlistMethod.post,
      'fs/mkdir',
      params: {'path': path},
      decoder: (_) => null,
    );
  }

  /// 便捷方法：rename
  Future<void> rename({required String path, required String name}) async {
    await request<dynamic>(
      AlistMethod.post,
      'fs/rename',
      params: {'path': path, 'name': name},
      decoder: (_) => null,
    );
  }

  /// 便捷方法：删除
  Future<void> remove({required String dir, required List<String> names}) async {
    await request<dynamic>(
      AlistMethod.post,
      'fs/remove',
      params: {'dir': dir, 'names': names},
      decoder: (_) => null,
    );
  }

  /// 便捷方法：复制
  Future<void> copy({
    required String srcDir,
    required String dstDir,
    required List<String> names,
  }) async {
    await request<dynamic>(
      AlistMethod.post,
      'fs/copy',
      params: {'src_dir': srcDir, 'dst_dir': dstDir, 'names': names},
      decoder: (_) => null,
    );
  }

  /// 便捷方法：移动
  Future<void> move({
    required String srcDir,
    required String dstDir,
    required List<String> names,
  }) async {
    await request<dynamic>(
      AlistMethod.post,
      'fs/move',
      params: {'src_dir': srcDir, 'dst_dir': dstDir, 'names': names},
      decoder: (_) => null,
    );
  }

  /// 便捷方法：构造文件链接（用于播放/下载）
  /// 需要 UserController 的 basePath，暂由外部传入
  static String buildFileUrl({
    required String serverUrl,
    required String basePath,
    required String path,
    String? sign,
  }) {
    final encodePath = _pathEncodeFull(path);
    var encodeBasePath = _pathEncodeFull(basePath);
    var fullPath = '$encodeBasePath$encodePath';
    if (fullPath.endsWith('/')) {
      fullPath = fullPath.substring(0, fullPath.length - 1);
    }
    var url = '${serverUrl}d$fullPath';
    if (!encodeBasePath.startsWith('/')) {
      url = '${serverUrl}d/$fullPath';
    }
    if (sign != null && sign.isNotEmpty) {
      url = '$url?sign=$sign';
    }
    return url;
  }

  static String _pathEncodeFull(String uri) {
    if (uri.isEmpty || uri == '/') return uri;
    final sb = StringBuffer();
    for (final value in uri.split('/')) {
      if (value.isNotEmpty) {
        sb.write(Uri.encodeComponent(value));
        sb.write('/');
      }
    }
    return sb.toString();
  }
}

Map<String, dynamic> _parseData(String data) {
  return jsonDecode(data) as Map<String, dynamic>;
}

class AlistNetException implements Exception {
  final int code;
  final String message;
  AlistNetException(this.code, this.message);

  @override
  String toString() => '[$code] $message';
}