import 'dart:io';
import 'package:dio/dio.dart';

class AlistNetErrorHandler {
  /// 将异常转换为用户可读的中文消息
  static String toMessage(dynamic error) {
    if (error is AlistRedirectException) {
      return error.message;
    }
    if (error is AlistJsonParseException) {
      return '数据解析异常';
    }
    if (error is SocketException) {
      return '网络异常，请检查网络';
    }
    if (error is HttpException) {
      return '服务器异常，请稍后重试';
    }
    if (error is FormatException) {
      return '数据解析异常';
    }
    if (error is DioException) {
      if (error.error is HandshakeException) {
        return 'SSL 证书错误';
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return '连接超时';
        case DioExceptionType.sendTimeout:
          return '请求超时';
        case DioExceptionType.receiveTimeout:
          return '响应超时';
        case DioExceptionType.badCertificate:
          return 'SSL 证书错误';
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          if (code != null) {
            return '响应 $code ${error.response?.statusMessage ?? ""}';
          }
          return '网络异常';
        case DioExceptionType.cancel:
          return '请求已取消';
        case DioExceptionType.connectionError:
          return '网络异常';
        default:
          break;
      }
    }
    return '网络异常';
  }
}

class AlistRedirectException implements Exception {
  final String message;
  AlistRedirectException(this.message);
  @override
  String toString() => 'Redirect: $message';
}

class AlistJsonParseException implements Exception {
  final String message;
  AlistJsonParseException(this.message);
  @override
  String toString() => 'ParseError: $message';
}