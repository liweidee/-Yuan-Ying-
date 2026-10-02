// lib/modules/download/services/download_manager.dart
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:yuanying/modules/download/services/m3u8_downloader.dart';

class DownloadManager {
  final String url;
  final String savePath;
  final Map<String, String>? headers;
  final void Function(int received, int total)? onProgress;
  final void Function()? onComplete;
  final void Function(Object error)? onError;

  final CancelToken _cancelToken = CancelToken();
  bool _isCancelled = false;
  late final Future<void> task;

  DownloadManager({
    required this.url,
    required this.savePath,
    this.headers,
    this.onProgress,
    this.onComplete,
    this.onError,
  }) {
    task = _start();
  }

  bool get isCancelled => _isCancelled;

  M3U8Downloader? _m3u8Downloader;

  Future<void> _start() async {
    // ===== M3U8 分支 =====
    if (_isM3u8(url)) {
      await _startM3u8();
      return;
    }

    // ===== 原有直链分支 =====
    int received;
    final file = File(savePath);
    if (file.existsSync()) {
      received = await file.length();
    } else {
      await file.create(recursive: true);
      received = 0;
    }

    final sink = file.openWrite(
      mode: received == 0 ? FileMode.writeOnly : FileMode.writeOnlyAppend,
    );

    try {
      // ===== 构造最终 headers =====
      // 复制一份，避免修改调用方传入的 map
      final finalHeaders = <String, String>{};
      if (headers != null && headers!.isNotEmpty) {
        finalHeaders.addAll(headers!);
      }
      finalHeaders['range'] = 'bytes=$received-';

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 10),
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) =>
            s != null && (s == 416 || (s >= 200 && s < 300)),
      ));

      final response = await dio.get<ResponseBody>(
        url,
        options: Options(
          headers: finalHeaders,
          responseType: ResponseType.stream,
        ),
        cancelToken: _cancelToken,
      );

      final data = response.data!;
      final contentLength = data.contentLength + received;

      if (received == 0) {
        onProgress?.call(0, contentLength);
      }

      int? lastSecond;
      await for (final chunk in data.stream) {
        if (_isCancelled) break;
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (lastSecond != now) {
          lastSecond = now;
          onProgress?.call(received, contentLength);
        }
      }

      await sink.close();
      if (_isCancelled) return;
      onComplete?.call();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (!_isCancelled) onError?.call(e);
    }
  }

  bool _isM3u8(String u) {
    final lower = u.toLowerCase();
    return lower.contains('.m3u8');
  }

  Future<void> _startM3u8() async {
    try {
      final downloader = M3U8Downloader(
        url: url,
        savePath: savePath,
        headers: headers,
        onProgress: (downloaded, total) {
          // received / total 是分片数
          onProgress?.call(downloaded, total);
        },
        onComplete: (_) {
          onComplete?.call();
        },
        onError: (e) {
          onError?.call(e);
        },
      );
      _m3u8Downloader = downloader;
      await downloader.start();
    } catch (e) {
      if (!_isCancelled) onError?.call(e);
    }
  }

  Future<void> cancel() async {
    _isCancelled = true;
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
    await _m3u8Downloader?.cancel();
    try {
      await task;
    } catch (_) {}
  }
}