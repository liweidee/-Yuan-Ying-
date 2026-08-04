import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:dio_brotli_transformer/dio_brotli_transformer.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/http/debug_log_interceptor.dart';

/// HTTP 客户端工厂
abstract final class HttpClientFactory {
  static late final Dio dio;
  static late final Dio http11Dio;

  static void init() {
    final baseOptions = BaseOptions(
      // ===== 保持与 T4ApiService 原配置一致：15s/30s =====
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'user-agent': 'Dart/3.6 (dart:io)',
        'accept-encoding': 'br,gzip',
      },
      persistentConnection: true,
    );

    final (http11Adapter, connectionManager) = _createPool();

    if (SettingPref.enableHttp2) {
      dio = Dio(baseOptions)
        ..httpClientAdapter = Http2Adapter(connectionManager, fallbackAdapter: http11Adapter);
    } else {
      dio = Dio(baseOptions)..httpClientAdapter = http11Adapter;
    }

    http11Dio = Dio(baseOptions)..httpClientAdapter = http11Adapter;

    // ===== 全局启用 Brotli 支持 =====
    dio.transformer = DioBrotliTransformer();
    http11Dio.transformer = DioBrotliTransformer();

    // ===== 强制忽略 HTTP 状态码，由业务层处理 =====
    dio.options.validateStatus = (status) => true;
    http11Dio.options.validateStatus = (status) => true;

    // 添加调试日志拦截器（紧跟在日志拦截器之后）
    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: false,
          requestHeader: false,
          responseHeader: false,
        ),
      );
    }
    // 调试日志拦截器（无论 debug 模式都添加，由开关控制是否记录）
    dio.interceptors.add(DebugLogInterceptor());
  }

  static (IOHttpClientAdapter, ConnectionManager?) _createPool() {
    final bool enableSystemProxy;
    late final String systemProxyHost;
    late final int? systemProxyPort;

    if (SettingPref.enableSystemProxy) {
      systemProxyHost = SettingPref.systemProxyHost;
      systemProxyPort = int.tryParse(SettingPref.systemProxyPort);
      enableSystemProxy = systemProxyPort != null && systemProxyHost.isNotEmpty;
    } else {
      enableSystemProxy = false;
    }

    final http11Adapter = IOHttpClientAdapter(
      createHttpClient: enableSystemProxy
          ? () => HttpClient()
              ..idleTimeout = const Duration(seconds: 15)
              ..autoUncompress = true
              ..findProxy = ((_) => 'PROXY $systemProxyHost:$systemProxyPort')
              ..badCertificateCallback = (cert, host, port) => true
          : () => HttpClient()
              ..idleTimeout = const Duration(seconds: 15)
              ..autoUncompress = true
              ..badCertificateCallback = (cert, host, port) => SettingPref.badCertificateCallback,
    );

    final connectionManager = SettingPref.enableHttp2
        ? ConnectionManager(
            idleTimeout: const Duration(seconds: 15),
            onClientCreate: enableSystemProxy
                ? (_, config) => config
                    ..proxy = Uri(
                      scheme: 'http',
                      host: systemProxyHost,
                      port: systemProxyPort,
                    )
                    ..onBadCertificate = (_) => true
                : SettingPref.badCertificateCallback
                ? (_, config) => config.onBadCertificate = (_) => true
                : null,
          )
        : null;

    return (http11Adapter, connectionManager);
  }

  /// 网络变化时重置适配器（可选）
  static void resetAdapters() {
    final (http11Adapter, connectionManager) = _createPool();
    if (connectionManager != null) {
      if (dio.httpClientAdapter is Http2Adapter) {
        (dio.httpClientAdapter as Http2Adapter)
          ..connectionManager.close(force: true)
          ..connectionManager = connectionManager
          ..fallbackAdapter.close(force: true)
          ..fallbackAdapter = http11Adapter;
      }
      http11Dio.httpClientAdapter = http11Adapter;
    } else {
      dio.httpClientAdapter.close(force: true);
      dio.httpClientAdapter = http11Adapter;
    }
  }
}