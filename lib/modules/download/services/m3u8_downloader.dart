// lib/modules/download/services/m3u8_downloader.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import 'package:yuanying/modules/download/models/m3u8_playlist.dart';
import 'package:yuanying/modules/download/services/m3u8_parser.dart';
import 'package:yuanying/modules/download/services/ts_merger.dart';
import 'package:yuanying/modules/download/utils/aes_decryptor.dart';

/// M3U8 下载器
///
/// 关键设计：
/// - **共享 Dio**：整个任务共用一个 Dio，连接池复用，避免每个分片重新 TLS 握手
/// - **忽略证书错误**：第三方 CDN 常见证书链不全，直接放行避免 HandshakeException
/// - **低并发**：默认 3，降低 CDN 反爬触发概率
/// - **分片级重试**：单分片失败重试 3 次，指数退避
/// - **请求头补全**：Referer / Origin / User-Agent 从 URL 与传入 headers 推导
class M3U8Downloader {
  final String url;
  final String savePath;
  final Map<String, String>? headers;

  /// 进度回调：已下载分片数 / 总分片数
  final void Function(int downloaded, int total)? onProgress;
  final void Function(String savePath)? onComplete;
  final void Function(Object error)? onError;

  /// 并发数：保守取 3，避免 CDN 拒绝
  static const int maxConcurrent = 3;

  /// 单分片最大重试次数
  static const int maxRetries = 3;

  bool _cancelled = false;
  final _cancelToken = CancelToken();
  final _keyCache = <String, Uint8List>{};

  late final Dio _dio = _buildDio();
  late final Map<String, String> _finalHeaders = _buildHeaders();

  M3U8Downloader({
    required this.url,
    required this.savePath,
    this.headers,
    this.onProgress,
    this.onComplete,
    this.onError,
  });

  bool get isCancelled => _cancelled;

  // ============================================================
  // Dio & Headers 构造
  // ============================================================
  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s >= 200 && s < 300,
      ),
    );

    // 自定义 HttpClientAdapter：
    // - 忽略证书错误
    // - 限制单主机连接数，避免触发 CDN 限流
    // - 允许连接复用
    //
    // 注意：这里用独立语句而不是级联写法。
    // Dart 的 lambda `(a, b) => expr` 会把后续的 `..setter` 吞进 lambda 体内，
    // 导致 setter 被作用在 bool 上（编译错误）。
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        client.connectionTimeout = const Duration(seconds: 30);
        client.idleTimeout = const Duration(seconds: 15);
        client.maxConnectionsPerHost = maxConcurrent + 2;
        client.autoUncompress = true;
        return client;
      },
    );

    return dio;
  }

  Map<String, String> _buildHeaders() {
    final h = <String, String>{};
    if (headers != null) h.addAll(headers!);

    final uri = Uri.parse(url);
    final origin = '${uri.scheme}://${uri.host}';

    void setIfMissing(String key, String value) {
      if (!h.keys.any((k) => k.toLowerCase() == key.toLowerCase())) {
        h[key] = value;
      }
    }

    setIfMissing('Referer', '$origin/');
    setIfMissing('Origin', origin);
    setIfMissing(
      'User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36',
    );
    setIfMissing('Accept', '*/*');
    setIfMissing('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');

    return h;
  }

  // ============================================================
  // 主流程
  // ============================================================
  Future<void> start() async {
    try {
      debugPrint('M3U8Downloader: parsing $url');
      final playlist = await M3U8Parser.parseFromUrl(
        url,
        headers: _finalHeaders,
      );
      if (_cancelled) return;

      if (playlist.segments.isEmpty) {
        throw Exception('m3u8 没有可用分片');
      }

      final total = playlist.segments.length;
      debugPrint('M3U8Downloader: $total segments');

      final tmpDir = Directory(p.join(p.dirname(savePath), 'segments'));
      if (!tmpDir.existsSync()) {
        await tmpDir.create(recursive: true);
      }

      final localPaths = List<String?>.filled(total, null);
      int downloaded = 0;
      final semaphore = _Semaphore(maxConcurrent);

      final futures = <Future<void>>[];
      for (int i = 0; i < total; i++) {
        final index = i;
        final segment = playlist.segments[i];
        futures.add(Future(() async {
          await semaphore.acquire();
          try {
            if (_cancelled) return;
            final path = p.join(tmpDir.path, '$index.ts');
            await _downloadWithRetry(segment: segment, localPath: path);
            localPaths[index] = path;
            downloaded++;
            onProgress?.call(downloaded, total);
          } finally {
            semaphore.release();
          }
        }));
      }

      await Future.wait(futures);
      if (_cancelled) return;

      final missing = localPaths.indexWhere((p) => p == null);
      if (missing >= 0) {
        throw Exception('分片 $missing 下载失败');
      }

      debugPrint('M3U8Downloader: merging $total segments');
      final merged = await TsMerger.merge(
        tsPaths: localPaths.cast<String>(),
        outputPath: savePath,
      );

      if (merged == null) {
        throw Exception('TS 合并失败');
      }

      try {
        if (tmpDir.existsSync()) {
          await tmpDir.delete(recursive: true);
        }
      } catch (_) {}

      onComplete?.call(savePath);
    } catch (e, s) {
      debugPrint('M3U8Downloader error: $e\n$s');
      if (!_cancelled) onError?.call(e);
    }
  }

  // ============================================================
  // 分片下载（含重试）
  // ============================================================
  Future<void> _downloadWithRetry({
    required M3U8Segment segment,
    required String localPath,
  }) async {
    Object? lastError;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await _downloadSegment(segment: segment, localPath: localPath);
        return;
      } catch (e) {
        lastError = e;
        if (_cancelled) rethrow;
        debugPrint(
          'M3U8Downloader: segment ${segment.mediaSequence} '
          'retry ${attempt + 1}/$maxRetries: $e',
        );
        if (attempt < maxRetries - 1) {
          // 指数退避：800ms, 1600ms
          await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
        }
      }
    }

    throw lastError ?? Exception('segment download failed');
  }

  Future<void> _downloadSegment({
    required M3U8Segment segment,
    required String localPath,
  }) async {
    // 断点续传：已存在且非空则跳过
    final f = File(localPath);
    if (f.existsSync() && await f.length() > 0) {
      return;
    }

    final response = await _dio.get<List<int>>(
      segment.url,
      options: Options(
        headers: _finalHeaders,
        responseType: ResponseType.bytes,
      ),
      cancelToken: _cancelToken,
    );

    var bytes = Uint8List.fromList(response.data ?? []);

    // AES-128 解密
    if (segment.key != null && segment.key!.isEncrypted) {
      final keyUri = segment.key!.uri;
      if (keyUri == null) throw Exception('AES key URI 为空');

      Uint8List? keyBytes = _keyCache[keyUri];
      if (keyBytes == null) {
        final keyRes = await _dio.get<List<int>>(
          keyUri,
          options: Options(
            headers: _finalHeaders,
            responseType: ResponseType.bytes,
          ),
          cancelToken: _cancelToken,
        );
        keyBytes = Uint8List.fromList(keyRes.data ?? []);
        if (keyBytes.length != 16) {
          throw Exception('AES key 长度不是 16 字节');
        }
        _keyCache[keyUri] = keyBytes;
      }

      Uint8List? iv;
      if (segment.key!.iv != null) {
        iv = AesDecryptor.parseIv(segment.key!.iv);
      }

      bytes = AesDecryptor.decrypt(
        encrypted: bytes,
        keyBytes: keyBytes,
        iv: iv,
        mediaSequence: segment.mediaSequence,
      );
    }

    await File(localPath).writeAsBytes(bytes, flush: true);
  }

  Future<void> cancel() async {
    _cancelled = true;
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
  }
}

/// 简单信号量（控制并发数）
class _Semaphore {
  final int maxCount;
  int _count = 0;
  final _queue = <Completer<void>>[];

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_count < maxCount) {
      _count++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final c = _queue.removeAt(0);
      if (!c.isCompleted) c.complete();
    } else {
      _count--;
    }
  }
}