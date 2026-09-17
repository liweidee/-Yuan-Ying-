import 'dart:io';
import 'package:flutter/foundation.dart';

class AlistDownloadHttpClient {
  final HttpClient _httpClient = HttpClient()..autoUncompress = false;
  int _lastLimitRequestTime = 0;
  bool _requesting = false;

  Future<HttpClientResponse> get(
    String url, {
    Map<String, dynamic>? headers,
    int? limitFrequency,
  }) async {
    if (limitFrequency == null || limitFrequency < 1) {
      return _getInner(url, headers: headers);
    }

    var now = DateTime.now().millisecondsSinceEpoch;
    if (_requesting ||
        now - _lastLimitRequestTime < limitFrequency * 1000) {
      do {
        await Future.delayed(const Duration(milliseconds: 200));
        now = DateTime.now().millisecondsSinceEpoch;
      } while (_requesting ||
          now - _lastLimitRequestTime < limitFrequency * 1000);
    }

    _requesting = true;
    try {
      return await _getInner(url, headers: headers);
    } finally {
      _requesting = false;
      _lastLimitRequestTime = DateTime.now().millisecondsSinceEpoch;
    }
  }

  Future<HttpClientResponse> _getInner(
    String url, {
    Map<String, dynamic>? headers,
  }) async {
    final request = await _httpClient.openUrl('GET', Uri.parse(url));
    headers?.forEach((key, value) {
      debugPrint('AList-DL header $key=$value');
      request.headers.set(key, value);
    });
    return request.close();
  }
}