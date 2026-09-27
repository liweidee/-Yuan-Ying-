import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart' show IOHttpClientAdapter;
import 'package:mime/mime.dart';

import 'concurrent_downloader.dart';
import 'proxy_models.dart';

/// MediaProxy 本地 HTTP 代理服务器
///
/// 自动格式识别：优先使用 URL 扩展名，魔数匹配作为辅助，
/// 无法识别时回退到 application/octet-stream，由播放器自行探测。
class MediaProxyServer {
  MediaProxyServer({required this.port, required this.log});

  final int port;
  final void Function(String) log;

  HttpServer? _httpServer;
  bool _running = false;

  late final Dio _dio;

  // ---- 探测缓存 ----
  final Map<String, CacheEntry<ProbeResult>> _probeCache = {};
  final Map<String, Future<ProbeResult?>> _pendingProbes = {};
  static const _maxProbeCacheSize = 100;
  Timer? _cacheCleanupTimer;

  // ---- 活动中的下载任务（按 URL 聚合） ----
  //
  // mpv 播放 MKV 时必然多次 seek（读头 → 跳文件尾读 Cues → 回到开头 →
  // 随机定位）。seek 意味着旧连接被废弃，但旧连接的下载任务如果还在跑，
  // 会同时拖着好几个全量下载，瞬间打满 maxConnectionsPerHost
  // 并触发源站限流。新请求到来时，先把同 URL 的旧任务取消掉。
  final Map<String, Set<ConcurrentDownloader>> _activeDownloaders = {};

  // ---- 分片大小的合理边界 ----
  //
  // 修复：原来最小分片只有 64KB，一个 370MB 的文件会被切成 5916 个独立
  // Range 请求。网盘/CDN 对高频小 Range 请求普遍有频控，这是触发限流的
  // 直接原因之一。现在下限抬到 512KB，默认 2MB。
  static const int _minChunkSize = 512 * 1024;
  static const int _maxChunkSize = 16 * 1024 * 1024;
  static const int _defaultChunkSize = 2 * 1024 * 1024;

  // ---- 单线程降级阈值 ----
  static const int _singleThreadRangeThreshold = 512 * 1024;

  // ---- open-ended range 的响应窗口 ----
  //
  // ⚠️ 默认 0（关闭）。
  //
  // 原因：实测 mpv/libmpv 的 ffmpeg http 层不接受代理截断。它解析
  // `Content-Range: bytes X-Y/TOTAL` 时拿 TOTAL 作为本次预期长度，
  // 在 Y 处关闭连接会报：
  //   ffmpeg: http: Stream ends prematurely at 33560448, should be 728576962
  //
  // 如需做 A/B 对比，用 URL 参数 `window=33554432` 单独开启，不必改代码。
  static const int _responseWindowBytes = 0;

  bool get isRunning => _running;
  int get actualPort => _httpServer?.port ?? port;

  // ================================================================
  // 生命周期
  // ================================================================

  Future<void> start() async {
    if (_running) return;

    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: null,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ));

    final adapter = IOHttpClientAdapter();
    adapter.createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      client.maxConnectionsPerHost = 32;
      client.idleTimeout = const Duration(seconds: 30);
      return client;
    };
    _dio.httpClientAdapter = adapter;

    try {
      _httpServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
    } on SocketException catch (e) {
      throw Exception('端口 $port 绑定失败: $e');
    }

    _running = true;

    _cacheCleanupTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _cleanupCache(),
    );

    _httpServer!.listen(
      _handleRequest,
      onError: (Object e) => log('[MediaProxy] 服务器错误: $e'),
      onDone: () {
        log('[MediaProxy] 服务器已关闭');
        _running = false;
      },
    );

    log('[MediaProxy] 已启动: http://127.0.0.1:$actualPort/proxy');
  }

  Future<void> stop() async {
    if (!_running && _httpServer == null) return;
    _running = false;
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = null;
    _probeCache.clear();
    _pendingProbes.clear();

    // 停服时把所有在跑的下载任务一并取消，避免它们继续占着连接池
    for (final set in _activeDownloaders.values) {
      for (final d in set) {
        d.cancel('server stopping');
      }
    }
    _activeDownloaders.clear();
    try {
      await _httpServer?.close(force: true);
    } catch (_) {}
    _httpServer = null;
    log('[MediaProxy] 已停止');
  }

  // ================================================================
  // 请求处理
  // ================================================================

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (!_running) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }

      if (request.uri.path != '/proxy') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      await _handleProxy(request);
    } catch (e, st) {
      log('[MediaProxy] 请求处理异常: $e\n$st');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleProxy(HttpRequest request) async {
    final qp = request.uri.queryParameters;
    var url = qp['url'] ?? '';
    final form = qp['form'] ?? '';
    final headerJson = qp['header'] ?? '';
    final threadStr = qp['thread'] ?? '';
    final sizeStr = qp['size'] ?? qp['chunkSize'] ?? '';
    final windowStr = qp['window'] ?? '';

    if (url.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    if (form == 'base64') {
      try {
        url = utf8.decode(base64Url.decode(url));
      } catch (e) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
    }

    final forwardHeaders = <String, String>{};
    request.headers.forEach((name, values) {
      if (_shouldFilterHeader(name)) return;
      if (values.isNotEmpty) {
        forwardHeaders[name] = values.first;
      }
    });

    if (headerJson.isNotEmpty) {
      try {
        var decoded = headerJson;
        if (form == 'base64') {
          decoded = utf8.decode(base64Url.decode(decoded));
        }
        final map = jsonDecode(decoded) as Map<String, dynamic>;
        map.forEach((key, value) {
          forwardHeaders[key] = value.toString();
        });
      } catch (e) {
        log('[MediaProxy] header 解析失败: $e');
      }
    }

    final rangeHeader = request.headers.value('range');
    final (clientStart, clientEnd) = _parseRangeHeader(rangeHeader);

    log('[MediaProxy] 请求: $url | range=$clientStart-$clientEnd');

    // ---- 取消该 URL 上残留的旧下载任务 ----
    //
    // 播放器 seek / 重新打开时，旧连接会被直接丢弃。旧任务的响应已经没人
    // 读，靠 response.done 往往检测不到断开，于是它们会继续把整个文件下完，
    // 几个任务叠加就把连接池和带宽吃光了。这里主动回收。
    _cancelStaleDownloaders(url);

    // ---- 探测源站（同时获取文件头字节用于格式识别） ----
    final probe = await _probeSource(url, forwardHeaders);
    if (probe == null || !_running) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      try {
        await request.response.close();
      } catch (_) {}
      return;
    }

    // ---- 设置 Content-Type（扩展名优先，魔数辅助） ----
    final detectedMimeType = _detectMimeType(url, probe.headerBytes);
    final contentType = detectedMimeType ?? 'application/octet-stream';
    request.response.headers.contentType = ContentType.parse(contentType);
    log('[MediaProxy] 设置 Content-Type: $contentType');

    // ---- 分支处理 ----
    if (!probe.supportsRange) {
      await _singleStreamForward(request, url, forwardHeaders, probe);
      return;
    }

    final effectiveStart = clientStart ?? 0;
    final effectiveEnd = clientEnd ?? (probe.contentSize - 1);
    final rangeSize = effectiveEnd - effectiveStart + 1;

    if (rangeSize <= _singleThreadRangeThreshold) {
      log('[MediaProxy] 小范围请求 ($rangeSize bytes)，降级为单线程');
      await _singleRangeForward(
        request: request,
        url: url,
        headers: forwardHeaders,
        start: effectiveStart,
        end: effectiveEnd,
        contentSize: probe.contentSize,
      );
      return;
    }

    await _multiThreadDownload(
      request: request,
      url: url,
      headers: forwardHeaders,
      probe: probe,
      clientStart: clientStart,
      clientEnd: clientEnd,
      threadStr: threadStr,
      sizeStr: sizeStr,
      windowStr: windowStr,
    );
  }

  // ================================================================
  // 源站探测
  // ================================================================

  Future<ProbeResult?> _probeSource(
    String url,
    Map<String, String> headers,
  ) async {
    final cached = _probeCache[url];
    if (cached != null && !cached.isExpired) {
      return cached.value;
    }

    final pending = _pendingProbes[url];
    if (pending != null) return pending;

    final future = _doProbe(url, headers);
    _pendingProbes[url] = future;
    try {
      final result = await future;
      if (result != null) {
        if (_probeCache.length >= _maxProbeCacheSize) {
          _cleanupCache();
        }
        _probeCache[url] = CacheEntry(
          result,
          DateTime.now().add(const Duration(minutes: 30)),
        );
      }
      return result;
    } finally {
      _pendingProbes.remove(url);
    }
  }

  Future<ProbeResult?> _doProbe(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: {...headers, 'Range': 'bytes=0-1023'},
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final respHeaders = <String, List<String>>{};
      response.headers.forEach((name, values) {
        respHeaders[name] = values;
      });

      final contentRange = response.headers.value('content-range');
      final acceptRanges = response.headers.value('accept-ranges');

      int contentSize = 0;
      bool supportsRange = false;

      if (contentRange != null) {
        final match = RegExp(r'/(\d+)\s*$').firstMatch(contentRange);
        if (match != null) {
          contentSize = int.parse(match.group(1)!);
        }
        supportsRange = true;
      } else if (acceptRanges?.toLowerCase() == 'bytes') {
        supportsRange = true;
        contentSize = int.tryParse(
              response.headers.value('content-length') ?? '0',
            ) ??
            0;
      } else {
        contentSize = int.tryParse(
              response.headers.value('content-length') ?? '0',
            ) ??
            0;
      }

      // ---- 捕获文件头字节 ----
      Uint8List? headerBytes;
      final body = response.data;
      if (body != null) {
        try {
          final builder = BytesBuilder(copy: false);
          int remaining = 64; // 读取 64 字节，足够魔数匹配
          await for (final chunk in body.stream) {
            if (remaining <= 0) break;
            final take = chunk.length < remaining ? chunk.length : remaining;
            builder.add(Uint8List.sublistView(chunk, 0, take));
            remaining -= take;
          }
          headerBytes = builder.takeBytes();
        } catch (_) {}
      }

      // ---- 兜底：有些 CDN 返回 `bytes 0-1023/*`，拿不到总大小 ----
      if (contentSize <= 0 && supportsRange) {
        contentSize = await _probeContentSize(url, headers) ?? 0;
      }

      log('[MediaProxy] 探测: size=$contentSize, supportsRange=$supportsRange, '
          'headerBytes=${headerBytes?.length ?? 0} bytes');

      return ProbeResult(
        supportsRange: supportsRange,
        contentSize: contentSize,
        headers: respHeaders,
        createdAt: DateTime.now(),
        headerBytes: headerBytes,
      );
    } catch (e) {
      log('[MediaProxy] 探测失败: $url | $e');
      return null;
    }
  }

  /// 用 `bytes=1-1` 再探一次，从 Content-Range 尾部取出总大小。
  ///
  /// 部分 CDN 在首个 Range 请求里返回 `bytes 0-1023/*`，只有后续请求
  /// 才会带上真实总长度。拿不到总大小时多线程会直接 502，必须兜底。
  Future<int?> _probeContentSize(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: {...headers, 'Range': 'bytes=1-1'},
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final cr = response.headers.value('content-range');
      if (cr != null) {
        final match = RegExp(r'/(\d+)\s*$').firstMatch(cr);
        if (match != null) return int.parse(match.group(1)!);
      }
      // 源站忽略 Range 直接返回 200 时，Content-Length 就是全文件大小
      final len = response.headers.value('content-length');
      if (len != null) return int.tryParse(len);
      return null;
    } catch (e) {
      log('[MediaProxy] 总大小兜底探测失败: $e');
      return null;
    }
  }

  // ================================================================
  // 格式识别（扩展名优先，魔数辅助）
  // ================================================================

  /// 自动检测 MIME 类型
  ///
  /// 优先级：
  ///   1. URL 扩展名（最可靠，不依赖文件内容）
  ///   2. 文件头魔数（当扩展名不存在时）
  ///   3. 返回 null（由调用方回退到 application/octet-stream）
  String? _detectMimeType(String url, Uint8List? headerBytes) {
    // 1. 扩展名优先
    final byExtension = _guessMimeTypeFromUrl(url);
    if (byExtension != null) {
      log('[MediaProxy] 通过扩展名识别: $byExtension');
      return byExtension;
    }

    // 2. 魔数辅助（当 URL 没有可识别的扩展名时）
    if (headerBytes != null && headerBytes.isNotEmpty) {
      final resolver = MimeTypeResolver();
      resolver.addMagicNumber(
        [0x1A, 0x45, 0xDF, 0xA3],
        'video/x-matroska',
      );
      resolver.addMagicNumber(
        [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70],
        'video/mp4',
      );
      resolver.addMagicNumber(
        [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70],
        'video/mp4',
      );
      resolver.addMagicNumber(
        [0x52, 0x49, 0x46, 0x46],
        'video/x-msvideo',
      );
      resolver.addMagicNumber(
        [0x46, 0x4C, 0x56, 0x01],
        'video/x-flv',
      );

      final byMagic = resolver.lookup('', headerBytes: headerBytes);
      if (byMagic != null && byMagic != 'application/octet-stream') {
        log('[MediaProxy] 通过魔数识别: $byMagic');
        return byMagic;
      }
    }

    // 3. 无法识别
    log('[MediaProxy] 无法识别格式，回退到 application/octet-stream');
    return null;
  }

  // ================================================================
  // 单线程转发
  // ================================================================

  Future<void> _singleStreamForward(
    HttpRequest request,
    String url,
    Map<String, String> headers,
    ProbeResult probe,
  ) async {
    log('[MediaProxy] 单线程模式: $url');

    final resp = request.response;
    resp.statusCode = HttpStatus.ok;

    // 修复：源站不支持 Range 时必须明确告诉客户端「不可 seek」，
    // 并且给出确定的 Content-Length。否则 mpv 会因为拿不到长度、
    // 又以为可以 seek，在 demuxer 里走到 "Failed to create file cache" 分支。
    if (probe.contentSize > 0) {
      resp.headers.set('Content-Length', '${probe.contentSize}');
    }
    resp.headers.set('Accept-Ranges', 'none');
    resp.headers.set('Connection', 'keep-alive');

    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          receiveTimeout: null,
        ),
      );

      final body = response.data;
      if (body == null) {
        await resp.close();
        return;
      }

      await for (final chunk in body.stream) {
        if (!_running) break;
        try {
          resp.add(chunk);
        } catch (_) {
          break;
        }
      }

      try {
        await resp.flush();
        await resp.close();
      } catch (_) {}
    } catch (e) {
      log('[MediaProxy] 单线程转发失败: $e');
      try {
        await resp.close();
      } catch (_) {}
    }
  }

  // ================================================================
  // 单线程带 Range 转发（小范围降级，含重试）
  // ================================================================

  Future<void> _singleRangeForward({
    required HttpRequest request,
    required String url,
    required Map<String, String> headers,
    required int start,
    required int end,
    required int contentSize,
  }) async {
    final resp = request.response;
    resp.statusCode = HttpStatus.partialContent;
    resp.headers.set('Content-Range', 'bytes $start-$end/$contentSize');
    resp.headers.set('Content-Length', '${end - start + 1}');
    resp.headers.set('Accept-Ranges', 'bytes');
    resp.headers.set('Connection', 'keep-alive');

    Response<ResponseBody>? response;
    Object? lastError;
    for (int retry = 0; retry < 3 && _running; retry++) {
      try {
        response = await _dio.get<ResponseBody>(
          url,
          options: Options(
            headers: {...headers, 'Range': 'bytes=$start-$end'},
            responseType: ResponseType.stream,
            receiveTimeout: null,
          ),
        );
        break;
      } catch (e) {
        lastError = e;
        log('[MediaProxy] 单线程 Range 第 ${retry + 1} 次失败: $e');
        if (retry < 2) {
          await Future.delayed(Duration(milliseconds: 500 * (retry + 1)));
        }
      }
    }

    if (response == null) {
      log('[MediaProxy] 单线程 Range 转发失败: $lastError');
      try {
        await resp.close();
      } catch (_) {}
      return;
    }

    final body = response.data;
    if (body == null) {
      await resp.close();
      return;
    }

    try {
      await for (final chunk in body.stream) {
        if (!_running) break;
        try {
          resp.add(chunk);
        } catch (_) {
          break;
        }
      }
      try {
        await resp.flush();
        await resp.close();
      } catch (_) {}
    } catch (e) {
      log('[MediaProxy] 单线程 Range 写入失败: $e');
      try {
        await resp.close();
      } catch (_) {}
    }
  }

  // ================================================================
  // 多线程下载
  // ================================================================

  Future<void> _multiThreadDownload({
    required HttpRequest request,
    required String url,
    required Map<String, String> headers,
    required ProbeResult probe,
    required int? clientStart,
    required int? clientEnd,
    required String threadStr,
    required String sizeStr,
    required String windowStr,
  }) async {
    final contentSize = probe.contentSize;
    if (contentSize <= 0) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      await request.response.close();
      return;
    }

    final effectiveStart = clientStart ?? 0;
    var effectiveEnd = clientEnd ?? (contentSize - 1);

    // 窗口大小：URL 参数 window 优先，否则用默认值（默认 0 = 关闭）
    var windowBytes = _responseWindowBytes;
    if (windowStr.isNotEmpty) {
      final parsed = int.tryParse(windowStr);
      if (parsed != null && parsed >= 0) {
        windowBytes = parsed;
        log('[MediaProxy] 窗口化(参数覆盖): $windowBytes bytes');
      }
    }

    if (windowBytes > 0 && clientEnd == null) {
      final windowEnd = effectiveStart + windowBytes - 1;
      if (windowEnd < effectiveEnd) {
        log('[MediaProxy] 窗口化: 开放式 Range 截断为 '
            '$effectiveStart-$windowEnd（原至 ${contentSize - 1}，'
            '总长度仍声明 $contentSize）');
        effectiveEnd = windowEnd;
      }
    }

    if (effectiveStart < 0 ||
        effectiveEnd >= contentSize ||
        effectiveStart > effectiveEnd) {
      try {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers
            .set('Content-Range', 'bytes */$contentSize');
      } catch (_) {}
      await request.response.close();
      return;
    }

    final rangeSize = effectiveEnd - effectiveStart + 1;

    // ---- 线程数 ----
    int threadCount;
    if (threadStr.isNotEmpty) {
      threadCount = int.tryParse(threadStr) ?? 4;
      if (threadCount <= 0) threadCount = 1;
      if (threadCount > 32) threadCount = 32;
    } else {
      threadCount = _autoThreadCount(contentSize, rangeSize);
    }

    // ---- 分片大小 ----
    int chunkSize;
    if (sizeStr.isNotEmpty) {
      chunkSize = int.tryParse(sizeStr) ?? _defaultChunkSize;
    } else {
      chunkSize = _defaultChunkSize;
    }

    if (chunkSize < _minChunkSize) chunkSize = _minChunkSize;
    if (chunkSize > _maxChunkSize) chunkSize = _maxChunkSize;

    final minChunks = threadCount * 4;
    if (rangeSize / chunkSize < minChunks) {
      final adjusted = (rangeSize / minChunks).ceil();
      if (adjusted > chunkSize) {
        chunkSize = adjusted;
        if (chunkSize < _minChunkSize) chunkSize = _minChunkSize;
      }
    }

    final totalChunks = (rangeSize / chunkSize).ceil();
    if (totalChunks < threadCount) {
      threadCount = totalChunks.clamp(1, threadCount);
    }

    // 修复：上限从 256 降到 64。分片变大后 256 个 slot 意味着几百 MB
    // 常驻内存，而背压一旦失效这些数据就全堆在堆里。
    final maxBufferedChunks = (64 * 1024 * 1024 ~/ chunkSize).clamp(4, 64);

    log('[MediaProxy] 多线程: range=$effectiveStart-$effectiveEnd '
        '(${_formatSize(rangeSize)}), '
        'thread=$threadCount, chunkSize=${_formatSize(chunkSize)}, '
        'totalChunks=$totalChunks, maxBuffered=$maxBufferedChunks');

    final resp = request.response;
    resp.statusCode = HttpStatus.partialContent;
    resp.headers.set(
      'Content-Range',
      'bytes $effectiveStart-$effectiveEnd/$contentSize',
    );
    resp.headers.set('Content-Length', '$rangeSize');
    resp.headers.set('Accept-Ranges', 'bytes');
    resp.headers.set('Connection', 'keep-alive');

    final downloader = ConcurrentDownloader(
      url: url,
      headers: headers,
      startOffset: effectiveStart,
      endOffset: effectiveEnd,
      chunkSize: chunkSize,
      threadCount: threadCount,
      maxBufferedChunks: maxBufferedChunks,
      dio: _dio,
      log: log,
    );

    _registerDownloader(url, downloader);
    try {
      await downloader.run(resp);
    } catch (e) {
      log('[MediaProxy] 多线程下载异常: $e');
      downloader.cancel('exception: $e');
      try {
        await resp.close();
      } catch (_) {}
    } finally {
      _unregisterDownloader(url, downloader);
    }
  }

  // ================================================================
  // 工具方法
  // ================================================================

  String? _guessMimeTypeFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final path = uri.path.toLowerCase();

    if (path.endsWith('.mp4') || path.endsWith('.m4s')) return 'video/mp4';
    if (path.endsWith('.mkv')) return 'video/x-matroska';
    if (path.endsWith('.webm')) return 'video/webm';
    if (path.endsWith('.avi')) return 'video/x-msvideo';
    if (path.endsWith('.mov')) return 'video/quicktime';
    if (path.endsWith('.flv')) return 'video/x-flv';
    if (path.endsWith('.ts')) return 'video/mp2t';
    if (path.endsWith('.m3u8')) return 'application/vnd.apple.mpegurl';
    if (path.endsWith('.mpg') || path.endsWith('.mpeg')) return 'video/mpeg';
    if (path.endsWith('.3gp')) return 'video/3gpp';
    if (path.endsWith('.wmv')) return 'video/x-ms-wmv';

    return null;
  }

  bool _shouldFilterHeader(String name) {
    final lower = name.toLowerCase().trim();
    if (lower.isEmpty) return true;
    return lower == 'range' ||
        lower == 'host' ||
        lower == 'http-client-ip' ||
        lower == 'remote-addr' ||
        lower == 'accept-encoding' ||
        lower == 'connection' ||
        lower == 'proxy-connection';
  }

  (int?, int?) _parseRangeHeader(String? rangeHeader) {
    if (rangeHeader == null) return (null, null);
    final match = RegExp(r'bytes= *(\d+) *- *(\d*)').firstMatch(rangeHeader);
    if (match == null) return (null, null);
    final start = int.tryParse(match.group(1) ?? '');
    final endStr = match.group(2) ?? '';
    final end = endStr.isEmpty ? null : int.tryParse(endStr);
    return (start, end);
  }

  int _autoThreadCount(int contentSize, int rangeSize) {
    if (rangeSize < 1 * 1024 * 1024) return 1;
    if (rangeSize < 16 * 1024 * 1024) return 2;
    if (rangeSize < 128 * 1024 * 1024) return 4;
    if (contentSize < 1 * 1024 * 1024 * 1024) return 8;
    if (contentSize < 4 * 1024 * 1024 * 1024) return 16;
    return 16;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  void _cleanupCache() {
    _probeCache.removeWhere((_, entry) => entry.isExpired);
  }

  // ================================================================
  // 活动下载任务管理
  // ================================================================

  void _registerDownloader(String url, ConcurrentDownloader downloader) {
    _activeDownloaders.putIfAbsent(url, () => <ConcurrentDownloader>{}).add(
          downloader,
        );
  }

  void _unregisterDownloader(String url, ConcurrentDownloader downloader) {
    final set = _activeDownloaders[url];
    if (set == null) return;
    set.remove(downloader);
    if (set.isEmpty) _activeDownloaders.remove(url);
  }

  /// 取消同一 URL 上仍在运行的旧任务
  void _cancelStaleDownloaders(String url) {
    final set = _activeDownloaders[url];
    if (set == null || set.isEmpty) return;
    log('[MediaProxy] 回收 ${set.length} 个残留下载任务');
    for (final d in set.toList()) {
      d.cancel('superseded by new request');
    }
    set.clear();
  }
}