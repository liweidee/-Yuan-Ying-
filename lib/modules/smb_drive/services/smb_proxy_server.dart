import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mime/mime.dart';
import 'package:smb_connect/smb_connect.dart';

import '../models/smb_server.dart';

/// SMB 本地 HTTP 代理（多文件模式）。
///
/// 播放器访问：
///   http://127.0.0.1:port/stream?share=X&path=Y
/// 代理通过 SMB 的 RandomAccessFile 读取请求的字节范围（支持 Range），
/// 实现边下边播 + 拖动进度条。
///
/// 同一个代理端口可服务任意多个文件（通过 query 的 share/path 区分），
/// 因此切集时播放器只需请求不同 URL，无需重启代理。
class SmbProxyServer {
  SmbProxyServer({required this.server});

  final SmbServer server;

  HttpServer? _httpServer;
  bool _running = false;

  int get port => _httpServer?.port ?? 0;
  bool get isRunning => _running;

  /// 构造某个文件的代理 URL
  String urlFor({
    required String share,
    required String relativePath,
  }) {
    final q = Uri(queryParameters: {
      'share': share,
      'path': relativePath,
    }).query;
    return 'http://127.0.0.1:$port/stream?$q';
  }

  // ==================================================================
  // 启动 / 停止
  // ==================================================================
  Future<void> start() async {
    if (_running) return;

    _httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _running = true;
    _httpServer!.listen(
      _handleRequest,
      onError: (e) => debugPrint('[SMB Proxy] server error: $e'),
    );
    debugPrint('[SMB Proxy] listening on port $port');
  }

  Future<void> stop() async {
    _running = false;
    try {
      await _httpServer?.close(force: true);
    } catch (_) {}
    _httpServer = null;
    debugPrint('[SMB Proxy] stopped');
  }

  // ==================================================================
  // 请求处理
  // ==================================================================
  Future<void> _handleRequest(HttpRequest request) async {
    if (!_running) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    // ---- 从 query 解析 share / path ----
    final share = request.uri.queryParameters['share'] ?? '';
    final relPath = request.uri.queryParameters['path'] ?? '';
    if (share.isEmpty || relPath.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final fullPath = _buildFullPath(share, relPath);
    final mime = lookupMimeType(relPath) ?? 'application/octet-stream';

    SmbConnect? conn;
    RandomAccessFile? raf;
    final resp = request.response;

    try {
      // 每次请求独立建立 SMB 连接（并发请求不会争用）
      conn = await SmbConnect.connectAuth(
        host: server.host,
        domain: server.anonymous ? '' : server.domain,
        username: server.anonymous ? 'guest' : server.username,
        password: server.anonymous ? '' : server.password,
      );
      final file = await conn.file(fullPath);
      final fileSize = file.size ?? 0;
      if (fileSize <= 0) {
        throw Exception('无法获取文件大小: $fullPath');
      }
      raf = await conn.open(file);

      // ---- 解析 Range 头 ----
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
            // "bytes=-N" 后缀形式：请求最后 N 字节
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

      // ---- 设置响应头 ----
      resp.headers.set('Accept-Ranges', 'bytes');
      resp.headers.set('Content-Type', mime);
      resp.headers.set('Content-Length', '$contentLength');
      resp.headers.set('Cache-Control', 'no-store');

      if (isPartial) {
        resp.statusCode = HttpStatus.partialContent;
        resp.headers.set(
          'Content-Range',
          'bytes $start-$end/$fileSize',
        );
      } else {
        resp.statusCode = HttpStatus.ok;
      }

      // ---- 流式返回数据 ----
      await raf.setPosition(start);
      const chunkSize = 64 * 1024;
      int remaining = contentLength;

      // 客户端断开时终止循环
      bool clientClosed = false;
      unawaited(resp.done.catchError((_) {
        clientClosed = true;
      }));

      while (remaining > 0 && _running && !clientClosed) {
        final toRead = remaining < chunkSize ? remaining : chunkSize;
        final bytesRead = await raf.read(toRead);
        if (bytesRead.isEmpty) break;
        try {
          resp.add(bytesRead);
        } catch (_) {
          break; // 客户端断开
        }
        remaining -= bytesRead.length;
      }

      try {
        await resp.flush();
        await resp.close();
      } catch (_) {}
    } catch (e, st) {
      debugPrint('[SMB Proxy] request error: $e\n$st');
      try {
        resp.statusCode = HttpStatus.internalServerError;
      } catch (_) {
        // headers 已发送，无法再改状态码
      }
      try {
        await resp.close();
      } catch (_) {}
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
      if (conn != null) {
        try {
          unawaited(conn.close().catchError((_) {}));
        } catch (_) {}
      }
    }
  }

  String _buildFullPath(String share, String relativePath) {
    if (relativePath.isEmpty || relativePath == '/') return '/$share';
    final clean = relativePath.startsWith('/')
        ? relativePath
        : '/$relativePath';
    final trimmed =
        clean.endsWith('/') ? clean.substring(0, clean.length - 1) : clean;
    return '/$share$trimmed';
  }
}

/// 全局管理器：整个应用维护一个代理实例
class SmbProxyManager {
  SmbProxyManager._();

  static SmbProxyServer? _current;

  static SmbProxyServer? get current => _current;

  /// 启动新代理（先停掉旧的）
  static Future<SmbProxyServer> start(SmbServer server) async {
    await stopCurrent();
    final proxy = SmbProxyServer(server: server);
    await proxy.start();
    _current = proxy;
    return proxy;
  }

  static Future<void> stopCurrent() async {
    final p = _current;
    _current = null;
    if (p != null) {
      await p.stop();
    }
  }
}