import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 第一部分：仅负责 AList 登录（第二部分会被 AlistDioUtils 整合）
class AlistAuthService {
  Future<String> login({
    required String serverUrl,
    required String username,
    required String password,
    String? otpCode,
    bool ignoreSSLError = false,
  }) async {
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

    try {
      final resp = await dio.post(
        'auth/login',
        data: {
          'username': username,
          'password': password,
          if (otpCode != null && otpCode.isNotEmpty) 'otp_code': otpCode,
        },
      );

      // 重定向处理：AList 有时返回 301
      if (resp.statusCode == 301 ||
          resp.statusCode == 302 ||
          resp.statusCode == 307 ||
          resp.statusCode == 308) {
        final location = resp.headers.value('location');
        throw AlistLoginException(
          code: 301,
          message: location ?? '服务器重定向',
        );
      }

      final data = resp.data;
      if (data is! String) {
        throw AlistLoginException(code: -1, message: '响应格式错误');
      }

      final Map<String, dynamic> json =
          jsonDecode(data) as Map<String, dynamic>;
      final int code = json['code'] as int? ?? -1;

      if (code == 200) {
        final token =
            ((json['data'] as Map<String, dynamic>?)?['token']) as String?;
        if (token == null || token.isEmpty) {
          throw AlistLoginException(code: -1, message: '返回的 token 为空');
        }
        return token;
      }

      throw AlistLoginException(
        code: code,
        message: json['message'] as String? ?? '登录失败',
      );
    } on DioException catch (e) {
      throw AlistLoginException(code: -1, message: _mapDioError(e));
    }
  }

  String _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '连接超时';
      case DioExceptionType.connectionError:
        return '无法连接服务器';
      case DioExceptionType.badCertificate:
        return 'SSL 证书错误';
      default:
        return e.message ?? '网络错误';
    }
  }
}

class AlistLoginException implements Exception {
  final int code;
  final String message;
  AlistLoginException({required this.code, required this.message});

  @override
  String toString() => '[$code] $message';
}