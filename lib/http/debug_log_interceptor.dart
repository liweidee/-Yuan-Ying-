import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:yuanying/services/debug_log_service.dart';

class DebugLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.uri.scheme.startsWith('http')) {
      // ===== 从 extra 读取来源，默认为 't4' =====
      final source = options.extra['source'] as String? ?? 't4';
      
      DebugLogService.instance.logRequest(
        method: options.method,
        url: options.uri.toString(),
        headers: options.headers.map((k, v) => MapEntry(k, v.toString())),
        requestBody: _getRequestBody(options),
        source: source,
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.uri.scheme.startsWith('http')) {
      final source = response.requestOptions.extra['source'] as String? ?? 't4';
      
      DebugLogService.instance.logResponse(
        url: response.requestOptions.uri.toString(),
        method: response.requestOptions.method,
        statusCode: response.statusCode,
        responseBody: _getResponseBody(response),
        responseSize: response.data is List<int>
            ? (response.data as List<int>).length
            : null,
        source: source,
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.requestOptions.uri.scheme.startsWith('http')) {
      final source = err.requestOptions.extra['source'] as String? ?? 't4';
      
      DebugLogService.instance.logResponse(
        url: err.requestOptions.uri.toString(),
        method: err.requestOptions.method,
        statusCode: err.response?.statusCode,
        responseBody: err.message ?? err.error?.toString(),
        source: source,
      );
    }
    handler.next(err);
  }

  String? _getRequestBody(RequestOptions options) {
    if (options.data == null) return null;
    if (options.data is String) return options.data as String;
    if (options.data is Map || options.data is List) {
      try {
        return jsonEncode(options.data);
      } catch (_) {
        return options.data.toString();
      }
    }
    if (options.data is FormData) {
      return '[FormData]';
    }
    return '[binary data]';
  }

  String? _getResponseBody(Response response) {
    if (response.data == null) return null;
    if (response.data is String) return response.data as String;
    if (response.data is Map || response.data is List) {
      try {
        return jsonEncode(response.data);
      } catch (_) {
        return response.data.toString();
      }
    }
    if (response.data is List<int>) {
      return '[binary data, ${(response.data as List<int>).length} bytes]';
    }
    return response.data.toString();
  }
}