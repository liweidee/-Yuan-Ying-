import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 洛雪音乐统一 HTTP 客户端
///
/// - 默认 15s 超时
/// - 不自动抛异常（validateStatus 全通过）
/// - 不自动 JSON 解析（统一返回 String）
/// - 放开证书校验（仅本模块，避开某些网络环境下酷我等服务器握手失败）
/// - 独立连接池，不污染项目主网络栈
class LxHttp {
  LxHttp._();

  static final Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 15),
    responseType: ResponseType.plain,
    validateStatus: (_) => true,
    followRedirects: true,
    maxRedirects: 5,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ))
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );

  static Options options({
    Duration? timeout,
    ResponseType? responseType,
    Map<String, dynamic>? headers,
    String? contentType,
  }) {
    return Options(
      sendTimeout: timeout,
      receiveTimeout: timeout,
      responseType: responseType,
      headers: headers,
      contentType: contentType,
      validateStatus: (_) => true,
      followRedirects: true,
      maxRedirects: 5,
    );
  }
}