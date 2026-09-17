import 'package:dio/dio.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

class AlistAuthInterceptor extends Interceptor {
  /// 当前请求所对应的 serverId（在切换服务器时更新）
  String? currentServerId;

  AlistAuthInterceptor({this.currentServerId});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 跳过鉴权（登录等公开接口）
    if (options.headers['alist_no_auth'] == 1) {
      options.headers.remove('alist_no_auth');
      return handler.next(options);
    }

    if (currentServerId != null && currentServerId!.isNotEmpty) {
      final token = StorageManager.getSetting<String>(
        '${AlistStorageKeys.tokenPrefix}$currentServerId',
      );
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = token;
      }
    }
    handler.next(options);
  }
}