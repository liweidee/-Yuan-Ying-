import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

/// 轻量 Cookie 拦截器（等价于 dio_cookie_manager 的 CookieManager）
///
/// 直接依赖已有 cookie_jar 包，避免新增依赖。
class SimpleCookieInterceptor extends Interceptor {
  final CookieJar cookieJar;
  SimpleCookieInterceptor(this.cookieJar);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final cookies = await cookieJar.loadForRequest(options.uri);
      if (cookies.isNotEmpty) {
        options.headers['Cookie'] = cookies
            .map((c) => '${c.name}=${c.value}')
            .join('; ');
      }
    } catch (_) {}
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    await _saveCookies(response);
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response != null) {
      await _saveCookies(err.response!);
    }
    handler.next(err);
  }

  Future<void> _saveCookies(Response response) async {
    try {
      final setCookies = response.headers['set-cookie'];
      if (setCookies == null || setCookies.isEmpty) return;
      final cookies = setCookies
          .map((e) => Cookie.fromSetCookieValue(e))
          .toList();
      await cookieJar.saveFromResponse(
        response.requestOptions.uri,
        cookies,
      );
    } catch (_) {}
  }
}