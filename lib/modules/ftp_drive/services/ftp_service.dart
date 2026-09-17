import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:pure_ftp/pure_ftp.dart' hide FtpEntry;

import '../models/ftp_entry.dart' as model;
import '../models/ftp_server.dart';

class FtpService {
  FtpService._();
  static final FtpService instance = FtpService._();

  // ==================================================================
  // 连接管理
  // ==================================================================
  Future<FtpClient> _connectFtp(FtpServer server) async {
    final client = FtpClient(
      socketInitOptions: FtpSocketInitOptions(
        host: server.host,
        port: server.port,
      ),
      authOptions: FtpAuthOptions(
        username: server.username.isEmpty ? 'anonymous' : server.username,
        password: server.password,
      ),
    );
    await client.connect();
    return client;
  }

  Future<SSHClient> _connectSftp(FtpServer server) async {
    final socket = await SSHSocket.connect(
      server.host,
      server.port,
      timeout: const Duration(seconds: 15),
    );
    final client = SSHClient(
      socket,
      username: server.username,
      onPasswordRequest: () => server.password,
    );
    await client.authenticated;
    return client;
  }

  // ==================================================================
  // 测试连接
  // ==================================================================
  Future<({bool ok, String? error})> testConnection(FtpServer server) async {
    if (server.isSftp) return _testSftp(server);
    return _testFtp(server);
  }

  Future<({bool ok, String? error})> _testFtp(FtpServer server) async {
    FtpClient? client;
    try {
      client = await _connectFtp(server);
      await client.fs.listDirectory();
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: _friendlyError(e));
    } finally {
      try {
        await client?.disconnect();
      } catch (_) {}
    }
  }

  Future<({bool ok, String? error})> _testSftp(FtpServer server) async {
    SSHClient? client;
    try {
      client = await _connectSftp(server);
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: _friendlyError(e));
    } finally {
      client?.close();
    }
  }

  // ==================================================================
  // 列目录
  // ==================================================================
  Future<List<model.FtpEntry>> listDirectory(
    FtpServer server,
    String path,
  ) async {
    if (server.isSftp) return _listSftp(server, path);
    return _listFtp(server, path);
  }

  Future<List<model.FtpEntry>> _listFtp(
      FtpServer server, String path) async {
    FtpClient? client;
    try {
      client = await _connectFtp(server);
      await client.fs.changeDirectory(path);
      final list = await client.fs.listDirectory();

      final entries = <model.FtpEntry>[];
      for (final entry in list) {
        final name = entry.name;
        if (name == '.' || name == '..') continue;
        final fullPath =
            path.endsWith('/') ? '$path$name' : '$path/$name';

        entries.add(model.FtpEntry(
          name: name,
          path: fullPath,
          isDirectory: entry.isDirectory,
          size: entry.info?.size ?? 0,
          modified: _parseFtpModifyTime(entry.info?.modifyTime),
        ));
      }
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return entries;
    } finally {
      try {
        await client?.disconnect();
      } catch (_) {}
    }
  }

  Future<List<model.FtpEntry>> _listSftp(
      FtpServer server, String path) async {
    SSHClient? client;
    try {
      client = await _connectSftp(server);
      final sftp = await client.sftp();
      final list = await sftp.listdir(path);

      final entries = list.map((e) {
        final fullPath =
            path.endsWith('/') ? '$path${e.filename}' : '$path/${e.filename}';
        return model.FtpEntry(
          name: e.filename,
          path: fullPath,
          isDirectory: e.attr.isDirectory,
          size: e.attr.size ?? 0,
          modified: e.attr.modifyTime != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  e.attr.modifyTime! * 1000)
              : null,
        );
      }).toList();
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return entries;
    } finally {
      client?.close();
    }
  }

  /// 解析 FTP 服务器返回的 modifyTime 字符串为 DateTime
  /// 支持：
  ///   - MLSD:  yyyyMMddHHmmss  (如 20240101120000)
  ///   - ISO 8601: yyyy-MM-dd HH:mm:ss
  ///   - Unix LIST: MMM dd HH:mm 或 MMM dd yyyy
  DateTime? _parseFtpModifyTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final s = raw.trim();

    // 格式1: yyyyMMddHHmmss (14位纯数字, MLSD 格式)
    if (RegExp(r'^\d{14}$').hasMatch(s)) {
      try {
        return DateTime(
          int.parse(s.substring(0, 4)),
          int.parse(s.substring(4, 6)),
          int.parse(s.substring(6, 8)),
          int.parse(s.substring(8, 10)),
          int.parse(s.substring(10, 12)),
          int.parse(s.substring(12, 14)),
        );
      } catch (_) {}
    }

    // 格式2: ISO 8601 或 yyyy-MM-dd HH:mm:ss
    try {
      return DateTime.parse(s);
    } catch (_) {}

    // 格式3: MMM dd HH:mm 或 MMM dd yyyy (Unix LIST)
    try {
      final parts = s.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        const months = {
          'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
        };
        final month = months[parts[0].toLowerCase()];
        final day = int.tryParse(parts[1]);
        if (month != null && day != null) {
          if (parts[2].contains(':')) {
            final timeParts = parts[2].split(':');
            final year = DateTime.now().year;
            return DateTime(
              year,
              month,
              day,
              int.tryParse(timeParts[0]) ?? 0,
              int.tryParse(timeParts[1]) ?? 0,
            );
          } else {
            final year = int.tryParse(parts[2]);
            if (year != null) return DateTime(year, month, day);
          }
        }
      }
    } catch (_) {}

    return null;
  }

  // ==================================================================
  // 获取文件大小（用于代理服务器）
  // ==================================================================
  Future<int> getFileSize(FtpServer server, String remotePath) async {
    if (server.isSftp) {
      SSHClient? client;
      try {
        client = await _connectSftp(server);
        final sftp = await client.sftp();
        final stat = await sftp.stat(remotePath);
        return stat.size ?? 0;
      } catch (_) {
        return 0;
      } finally {
        client?.close();
      }
    }

    FtpClient? client;
    try {
      client = await _connectFtp(server);
      final parentPath = remotePath.substring(0, remotePath.lastIndexOf('/'));
      final fileName = remotePath.split('/').last;
      await client.fs.changeDirectory(parentPath.isEmpty ? '/' : parentPath);
      final list = await client.fs.listDirectory();
      for (final entry in list) {
        if (entry.name == fileName) {
          return entry.info?.size ?? 0;
        }
      }
      return 0;
    } catch (_) {
      return 0;
    } finally {
      try {
        await client?.disconnect();
      } catch (_) {}
    }
  }

  // ==================================================================
  // 流式读取（核心：支持 REST 偏移量）
  // ==================================================================
  Future<Stream<List<int>>> openReadStream(
    FtpServer server,
    String remotePath, {
    int offset = 0,
    int? length,
  }) async {
    if (server.isSftp) {
      return _openSftpStream(server, remotePath, offset, length);
    }
    return _openFtpStream(server, remotePath, offset, length);
  }

  Future<Stream<List<int>>> _openFtpStream(
    FtpServer server,
    String remotePath,
    int offset,
    int? length,
  ) async {
    final client = await _connectFtp(server);

    // 切换到父目录，找到目标 FtpFile
    final parentPath = remotePath.substring(0, remotePath.lastIndexOf('/'));
    final fileName = remotePath.split('/').last;
    await client.fs.changeDirectory(parentPath.isEmpty ? '/' : parentPath);
    final list = await client.fs.listDirectory();

    FtpFile? file;
    for (final entry in list) {
      if (entry.name == fileName && entry is FtpFile) {
        file = entry;
        break;
      }
    }
    if (file == null) {
      try {
        await client.disconnect();
      } catch (_) {}
      throw Exception('文件不存在: $remotePath');
    }

    // ★ 官方 API：downloadFileStream(file, restSize: offset)
    final stream = client.fs.downloadFileStream(file, restSize: offset);

    if (length == null) return stream;
    return _limitStream(stream, length);
  }

  Future<Stream<List<int>>> _openSftpStream(
    FtpServer server,
    String remotePath,
    int offset,
    int? length,
  ) async {
    final client = await _connectSftp(server);
    final sftp = await client.sftp();
    final file = await sftp.open(remotePath);
    // ★ dartssh2 官方 API：read(offset:, length:)
    return file.read(offset: offset, length: length);
  }

  /// 限制流的总长度
  Stream<List<int>> _limitStream(Stream<List<int>> source, int maxLength) {
    int remaining = maxLength;
    return source.takeWhile((chunk) {
      remaining -= chunk.length;
      return remaining >= 0;
    });
  }

  // ==================================================================
  // 下载文件（用于"下载 Tab"）
  // ==================================================================
  Future<void> download({
    required FtpServer server,
    required String remotePath,
    required String localPath,
    void Function(int received, int total)? onProgress,
  }) async {
    if (server.isSftp) {
      await _downloadSftp(server, remotePath, localPath, onProgress);
    } else {
      await _downloadFtp(server, remotePath, localPath, onProgress);
    }
  }

  Future<void> _downloadFtp(
    FtpServer server,
    String remotePath,
    String localPath,
    void Function(int, int)? onProgress,
  ) async {
    FtpClient? client;
    try {
      client = await _connectFtp(server);

      final parentPath = remotePath.substring(0, remotePath.lastIndexOf('/'));
      final fileName = remotePath.split('/').last;
      await client.fs.changeDirectory(parentPath.isEmpty ? '/' : parentPath);
      final list = await client.fs.listDirectory();

      FtpFile? file;
      for (final entry in list) {
        if (entry.name == fileName && entry is FtpFile) {
          file = entry;
          break;
        }
      }
      if (file == null) throw Exception('文件不存在: $remotePath');

      final total = file.info?.size ?? 0;
      final stream = client.fs.downloadFileStream(file);
      final sink = File(localPath).openWrite();
      int received = 0;
      try {
        await for (final chunk in stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
    } finally {
      try {
        await client?.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _downloadSftp(
    FtpServer server,
    String remotePath,
    String localPath,
    void Function(int, int)? onProgress,
  ) async {
    SSHClient? client;
    try {
      client = await _connectSftp(server);
      final sftp = await client.sftp();
      final stat = await sftp.stat(remotePath);
      final total = stat.size ?? 0;
      final remoteFile = await sftp.open(remotePath);
      final sink = File(localPath).openWrite();
      int received = 0;
      try {
        await for (final chunk in remoteFile.read()) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
        await remoteFile.close();
      }
    } finally {
      client?.close();
    }
  }

  // ==================================================================
  // 错误友好化
  // ==================================================================
  String _friendlyError(dynamic e) {
    final s = e.toString().toLowerCase();
    if (s.contains('auth') || s.contains('password') || s.contains('login')) {
      return '认证失败，请检查用户名密码';
    }
    if (s.contains('timeout')) return '连接超时';
    if (s.contains('refused')) return '服务器拒绝连接';
    if (s.contains('not found') || s.contains('no such')) return '路径不存在';
    if (s.contains('handshake') || s.contains('certificate')) return 'SSH 握手失败';
    if (s.contains('rest') || s.contains('not supported')) {
      return '服务器不支持 REST 命令（无法流式播放）';
    }
    return e.toString();
  }
}