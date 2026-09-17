import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:smb_connect/smb_connect.dart';

import '../models/smb_entry.dart';
import '../models/smb_server.dart';

class SmbService {
  SmbService._();
  static final SmbService instance = SmbService._();

  // ==================================================================
  // 连接管理
  // ==================================================================
  Future<SmbConnect> _connect(SmbServer server) async {
    return SmbConnect.connectAuth(
      host: server.host,
      domain: server.anonymous ? '' : server.domain,
      username: server.anonymous ? 'guest' : server.username,
      password: server.anonymous ? '' : server.password,
    );
  }

  /// 安全关闭 SMB 连接（吞掉 smb_connect 的所有 close 异常）
  void _safeClose(SmbConnect? c) {
    if (c == null) return;
    try {
      unawaited(
        c.close().catchError((Object e) {
          debugPrint('[SMB] close ignored: $e');
        }),
      );
    } catch (e) {
      debugPrint('[SMB] close sync error ignored: $e');
    }
  }

  // ==================================================================
  // 测试连接
  // ==================================================================
  Future<({bool ok, String? error})> testConnection(SmbServer server) async {
    SmbConnect? c;
    try {
      c = await _connect(server);
      try {
        await c.listShares();
      } catch (_) {}
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: _friendlyError(e));
    } finally {
      _safeClose(c);
    }
  }

  // ==================================================================
  // 枚举共享
  // ==================================================================
  Future<List<SmbEntry>> listShares(SmbServer server) async {
    SmbConnect? c;
    try {
      c = await _connect(server);
      final shares = await c.listShares();
      final entries = <SmbEntry>[];
      for (final s in shares) {
        final name = s.path.split('/').where((p) => p.isNotEmpty).last;
        if (name.endsWith(r'$')) continue; // 隐藏共享
        entries.add(SmbEntry.fromShare(s));
      }
      entries.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return entries;
    } finally {
      _safeClose(c);
    }
  }

  // ==================================================================
  // 列目录
  // ==================================================================
  Future<List<SmbEntry>> listDirectory(
    SmbServer server,
    String share,
    String relativePath,
  ) async {
    SmbConnect? c;
    try {
      c = await _connect(server);
      final fullPath = _buildFullPath(share, relativePath);
      final folder = await c.file(fullPath);
      final files = await c.listFiles(folder);

      final entries = <SmbEntry>[];
      for (final f in files) {
        final name = f.path.split('/').where((p) => p.isNotEmpty).last;
        if (name == '.' || name == '..') continue;
        entries.add(SmbEntry.fromSmbFile(f, share: share));
      }
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return entries;
    } finally {
      _safeClose(c);
    }
  }

  String _buildFullPath(String share, String relativePath) {
    if (relativePath.isEmpty || relativePath == '/') {
      return '/$share';
    }
    final clean =
        relativePath.startsWith('/') ? relativePath : '/$relativePath';
    final trimmed =
        clean.endsWith('/') ? clean.substring(0, clean.length - 1) : clean;
    return '/$share$trimmed';
  }

  // ==================================================================
  // 下载文件
  // ==================================================================
  Future<void> download({
    required SmbServer server,
    required String share,
    required String relativePath,
    required String localPath,
    void Function(int received, int total)? onProgress,
  }) async {
    SmbConnect? c;
    IOSink? sink;
    try {
      c = await _connect(server);
      final fullPath = _buildFullPath(share, relativePath);
      final file = await c.file(fullPath);

      int total = 0;
      try {
        total = file.size ?? 0;
      } catch (_) {}

      final stream = await c.openRead(file);
      sink = File(localPath).openWrite();
      int received = 0;
      await for (final chunk in stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}
      _safeClose(c);
    }
  }

  // ==================================================================
  // 播放准备：下载到临时文件（命中缓存则秒开）
  // ==================================================================
  Future<String> prepareForPlayback({
    required SmbServer server,
    required String share,
    required String relativePath,
    void Function(int received, int total)? onProgress,
  }) async {
    final tmpDir = Directory(
      '${Directory.systemTemp.path}/yuanying_smb_cache/${server.id}',
    );
    if (!await tmpDir.exists()) await tmpDir.create(recursive: true);

    final fileName = relativePath.split('/').last;
    final localPath = '${tmpDir.path}/$fileName';

    final f = File(localPath);
    if (await f.exists() && await f.length() > 0) {
      return localPath;
    }

    await download(
      server: server,
      share: share,
      relativePath: relativePath,
      localPath: localPath,
      onProgress: onProgress,
    );
    return localPath;
  }

  // ==================================================================
  // 错误友好化
  // ==================================================================
  String _friendlyError(dynamic e) {
    final s = e.toString().toLowerCase();
    if (s.contains('auth') ||
        s.contains('password') ||
        s.contains('logon') ||
        s.contains('access denied') ||
        s.contains('logon failure')) {
      return '认证失败，请检查用户名/密码/域';
    }
    if (s.contains('timeout')) return '连接超时';
    if (s.contains('refused')) return '服务器拒绝连接';
    if (s.contains('not found') || s.contains('no such')) {
      return '路径不存在';
    }
    if (s.contains('network name is no longer available')) {
      return '连接已断开，请重试';
    }
    if (s.contains('share')) return '共享不可用';
    if (s.contains('network')) return '网络不可达';
    return e.toString();
  }
}