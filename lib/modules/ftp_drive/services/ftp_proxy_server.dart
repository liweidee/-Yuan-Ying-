import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mime/mime.dart';

import '../models/ftp_entry.dart' as model;
import '../models/ftp_server.dart';
import 'ftp_service.dart';

class FtpProxyServer {
  FtpProxyServer({required this.server});

  final FtpServer server;

  HttpServer? _httpServer;
  bool _running = false;

  int get port => _httpServer?.port ?? 0;
  bool get isRunning => _running;

  String urlFor(String remotePath) {
    final q = Uri(queryParameters: {'path': remotePath}).query;
    return 'http://127.0.0.1:$port/stream?$q';
  }

  Future<void> start() async {
    if (_running) return;
    _httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _running = true;
    _httpServer!.listen(
      _handleRequest,
      onError: (e) => debugPrint('[FTP Proxy] server error: $e'),
    );
    debugPrint('[FTP Proxy] listening on port $port (${server.protocolLabel})');
  }

  Future<void> stop() async {
    _running = false;
    try { await _httpServer?.close(force: true); } catch (_) {}
    _httpServer = null;
    debugPrint('[FTP Proxy] stopped');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (!_running) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    final remotePath = request.uri.queryParameters['path'] ?? '';
    if (remotePath.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    debugPrint('[FTP Proxy] request: ${request.method} $remotePath');
    await _handleStream(request, remotePath);
  }

  Future<void> _handleStream(HttpRequest request, String remotePath) async {
    final resp = request.response;

    try {
      // 1. 获取文件大小
      final fileSize = await FtpService.instance.getFileSize(server, remotePath);
      if (fileSize <= 0) {
        resp.statusCode = HttpStatus.notFound;
        await resp.close();
        return;
      }

      // 2. 解析 Range
      final rangeHeader = request.headers.value('range');
      int start = 0;
      int end = fileSize - 1;
      bool isPartial = false;

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final spec = rangeHeader.substring(6).trim();
        final dashIdx = spec.indexOf('-');
        if (dashIdx >= 0) {
          final startStr = spec.substring(0, dashIdx);
          final endStr = spec.substring(dashIdx + 1);

          if (startStr.isEmpty) {
            final suffix = int.tryParse(endStr) ?? 0;
            start = (fileSize - suffix).clamp(0, fileSize - 1);
            end = fileSize - 1;
          } else {
            start = int.tryParse(startStr) ?? 0;
            end = endStr.isEmpty
                ? fileSize - 1
                : (int.tryParse(endStr) ?? fileSize - 1);
          }

          if (start < 0) start = 0;
          if (end >= fileSize) end = fileSize - 1;
          if (end < start) end = fileSize - 1;
          isPartial = true;
        }
      }

      final contentLength = end - start + 1;
      final mime = lookupMimeType(remotePath) ?? 'application/octet-stream';

      // 3. 设置响应头
      resp.headers.set('Accept-Ranges', 'bytes');
      resp.headers.set('Content-Type', mime);
      resp.headers.set('Content-Length', '$contentLength');
      resp.headers.set('Cache-Control', 'no-store');
      if (isPartial) {
        resp.statusCode = HttpStatus.partialContent;
        resp.headers.set('Content-Range', 'bytes $start-$end/$fileSize');
      } else {
        resp.statusCode = HttpStatus.ok;
      }

      debugPrint('[FTP Proxy] streaming: range=$start-$end/$fileSize');

      // 4. 流式传输
      final stream = await FtpService.instance.openReadStream(
        server, remotePath, offset: start, length: contentLength,
      );

      bool clientClosed = false;
      unawaited(resp.done.catchError((_) { clientClosed = true; }));

      await for (final chunk in stream) {
        if (!_running || clientClosed) break;
        try {
          resp.add(chunk);
        } catch (e) {
          debugPrint('[FTP Proxy] resp.add error: $e');
          break;
        }
      }

      try { await resp.flush(); await resp.close(); } catch (_) {}
      debugPrint('[FTP Proxy] streaming completed');
    } catch (e, st) {
      debugPrint('[FTP Proxy] error: $e\n$st');
      try { resp.statusCode = HttpStatus.internalServerError; } catch (_) {}
      try { await resp.close(); } catch (_) {}
    }
  }
}

class FtpProxyManager {
  FtpProxyManager._();
  static FtpProxyServer? _current;
  static FtpProxyServer? get current => _current;

  static Future<FtpProxyServer> start(FtpServer server) async {
    await stopCurrent();
    final proxy = FtpProxyServer(server: server);
    await proxy.start();
    _current = proxy;
    return proxy;
  }

  static Future<void> stopCurrent() async {
    final p = _current;
    _current = null;
    if (p != null) await p.stop();
  }
}