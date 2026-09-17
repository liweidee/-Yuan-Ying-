import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 本地代理服务器：解决百度网盘等 provider 的重定向 header 失效问题
class AlistProxyServer {
  static const int defaultPort = 28080;
  static const String headerFlag = 'alistheader_';
  static const int _maxRedirectTimes = 20;

  int _port = defaultPort;
  HttpClient? _httpClient;
  HttpServer? _httpServer;
  final _redirectCache = <String, _RedirectCacheValue>{};
  final _content = <String, String>{};
  final _files = <String, File>{};

  Future<void> start({int port = defaultPort}) async {
    if (_httpServer != null) return;
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } catch (_) {
      await start(port: port + 1);
      return;
    }
    if (_httpServer != null) {
      server.close(force: true);
      return;
    }
    _httpClient = _createHttpClient();
    _port = port;
    _httpServer = server;
    _handleRequests(server);
  }

  Future<void> _handleRequests(HttpServer server) async {
    await for (final req in server) {
      try {
        await _handleRequest(req);
      } catch (e) {
        try {
          req.response
            ..statusCode = HttpStatus.internalServerError
            ..write('Proxy error: $e');
          await req.response.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final httpClient = _httpClient;
    final targetUrl = request.uri.queryParameters['targetUrl'];
    final contentKey = request.uri.queryParameters['contentKey'];
    final file = request.uri.queryParameters['file'];

    if (httpClient == null ||
        (targetUrl == null && contentKey == null && file == null)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    if (contentKey != null && contentKey.isNotEmpty) {
      final content = _content[contentKey];
      if (content == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.statusCode = HttpStatus.ok;
        request.response.write(content);
      }
      await request.response.close();
      return;
    }

    if (file != null && file.isNotEmpty) {
      final target = _files[file];
      if (target == null || !target.existsSync()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      await _writeFileResponse(target, request);
      return;
    }

    // 处理 targetUrl
    final extraHeaders = <String, String>{};
    request.uri.queryParameters.forEach((k, v) {
      if (k.startsWith(headerFlag)) {
        extraHeaders[k.substring(headerFlag.length)] = v;
      }
    });

    final cached = _findCache(targetUrl!);
    Uri uri = cached != null ? Uri.parse(cached.target) : Uri.parse(targetUrl);

    var httpReq = await httpClient.openUrl(request.method, uri);
    httpReq.followRedirects = false;
    request.headers.forEach((name, values) {
      if (_isValidRequestHeader(name)) httpReq.headers.set(name, values);
    });
    extraHeaders.forEach((k, v) => httpReq.headers.set(k, v));

    var resp = await httpReq.close();
    var redirectTimes = 0;
    while (_httpServer != null &&
        resp.isRedirect &&
        redirectTimes < _maxRedirectTimes) {
      redirectTimes++;
      await resp.drain();
      var location = resp.headers.value(HttpHeaders.locationHeader);
      if (location != null) _addCache(uri, location);
      if (location != null) {
        uri = uri.resolve(location);
        httpReq = await httpClient.getUrl(uri);
        httpReq.followRedirects = false;
        request.headers.forEach((name, values) {
          if (_isValidRequestHeader(name)) {
            httpReq.headers.set(name, values);
          }
        });
        extraHeaders.forEach((k, v) => httpReq.headers.set(k, v));
        resp = await httpReq.close();
      }
    }

    if (_httpServer == null) {
      await httpReq.close();
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    request.response.statusCode = resp.statusCode;
    resp.headers.forEach((name, values) {
      request.response.headers.set(name, values);
    });
    await resp.pipe(request.response);
    _clearInvalidCache();
  }

  Future<void> _writeFileResponse(File file, HttpRequest request) async {
    try {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'bytes=(\d+)-(\d+)?').firstMatch(range);
        if (match != null) {
          final start = int.parse(match.group(1)!);
          final end =
              match.group(2) != null ? int.parse(match.group(2)!) : file.lengthSync() - 1;
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-$end/${file.lengthSync()}');
          request.response.headers.set(
              HttpHeaders.contentLengthHeader, end - start + 1);
          await file.openRead(start, end + 1).pipe(request.response);
          return;
        }
      }
      request.response.headers.contentType = ContentType.binary;
      await file.openRead().pipe(request.response);
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  bool _isValidRequestHeader(String name) {
    final lower = name.toLowerCase();
    return lower != 'host' && lower != 'x-device-id';
  }

  void _addCache(Uri uri, String location) {
    final validTime = DateTime.now().millisecondsSinceEpoch + 10 * 60 * 1000;
    _redirectCache[uri.toString()] = _RedirectCacheValue(location, validTime);
  }

  _RedirectCacheValue? _findCache(String targetUrl) {
    final cached = _redirectCache[targetUrl];
    if (cached == null) return null;
    if (cached.validTime < DateTime.now().millisecondsSinceEpoch) {
      _redirectCache.remove(targetUrl);
      return null;
    }
    return cached;
  }

  void _clearInvalidCache() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _redirectCache.removeWhere((_, v) => v.validTime < now);
  }

  Uri makeProxyUrl(String targetUrl, {Map<String, String>? headers}) {
    if (_httpServer == null) {
      throw StateError('Proxy server is not started');
    }
    final queryParams = <String, String>{'targetUrl': targetUrl};
    headers?.forEach((k, v) => queryParams['$headerFlag$k'] = v);
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _port,
      queryParameters: queryParams,
    );
  }

  Uri makeContentUri(String key, String value) {
    if (_httpServer == null) throw StateError('Proxy server is not started');
    final encodeKey = Uri.encodeComponent(key);
    _content[encodeKey] = value;
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _port,
      queryParameters: {'contentKey': encodeKey},
    );
  }

  Uri makeFileUri(File file) {
    if (_httpServer == null) throw StateError('Proxy server is not started');
    final pathHash = file.absolute.path.hashCode.toString();
    _files[pathHash] = file;
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _port,
      queryParameters: {'file': pathHash},
    );
  }

  Future<void> stop() async {
    final server = _httpServer;
    final client = _httpClient;
    _httpServer = null;
    _httpClient = null;
    _content.clear();
    _files.clear();
    try {
      await server?.close(force: true);
    } catch (_) {}
    try {
      client?.close(force: true);
    } catch (_) {}
  }

  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.autoUncompress = false;
    return client;
  }
}

class _RedirectCacheValue {
  final String target;
  final int validTime;
  _RedirectCacheValue(this.target, this.validTime);
}