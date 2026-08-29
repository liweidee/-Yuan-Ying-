// lib/modules/transfer/services/transfer_server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

/// 文件过大异常
class TransferFileTooLargeException implements Exception {
  final int limit;
  const TransferFileTooLargeException(this.limit);
  @override
  String toString() => '文件大小超过 ${limit ~/ (1024 * 1024)} MB 限制';
}

class TransferServer {
  TransferServer._();
  static final TransferServer instance = TransferServer._();

  static const int maxUploadBytes = 512 * 1024 * 1024; // 512MB
  static const int defaultPort = 12346;

  HttpServer? _server;
  int _port = 0;
  String _ip = '';
  bool _running = false;

  bool get running => _running;
  int get port => _port;
  String get ip => _ip;
  String get url => 'http://$_ip:$_port';

  /// 上传成功回调
  void Function(String filePath)? onFileUploaded;

  Future<void> start({int preferredPort = defaultPort}) async {
    if (_server != null) return;

    final ips = await _ipAddresses();
    if (ips.isEmpty) {
      throw const SocketException('未找到可用的网络地址');
    }
    _ip = ips.first;

    HttpServer? server;
    int port = preferredPort;
    Object? lastError;
    for (int i = 0; i < 12; i++) {
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          port,
        );
        break;
      } catch (e) {
        lastError = e;
        port++;
      }
    }
    if (server == null) throw lastError ?? '端口绑定失败';
    _port = server.port;
    _server = server;
    _running = true;
    server.listen(_handleRequest, onError: (_) {});
  }

  Future<void> stop() async {
    _running = false;
    final server = _server;
    _server = null;
    _port = 0;
    _ip = '';
    await server?.close(force: true);
  }

  Future<List<String>> _ipAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final ips = <String>[];
      for (final itf in interfaces) {
        for (final addr in itf.addresses) {
          if (!addr.isLoopback && !ips.contains(addr.address)) {
            ips.add(addr.address);
          }
        }
      }
      ips.sort((a, b) {
        int score(String s) {
          if (s.startsWith('192.168.') || s.startsWith('10.')) return 0;
          return 1;
        }
        return score(a).compareTo(score(b));
      });
      return ips;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && (path == '/' || path == '/index.html')) {
        req.response.headers.contentType = ContentType.html;
        req.response.write(_uploadPage());
        await req.response.close();
        return;
      }
      if (req.method == 'POST' && path == '/upload') {
        await _handleUpload(req);
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } on TransferFileTooLargeException catch (e) {
      await _writeJson(req, {'ok': false, 'msg': e.toString()},
          statusCode: HttpStatus.requestEntityTooLarge);
    } catch (e) {
      await _writeJson(req, {'ok': false, 'msg': '服务器处理失败: $e'},
          statusCode: HttpStatus.internalServerError);
    }
  }

  Future<void> _handleUpload(HttpRequest req) async {
    final fileName = req.uri.queryParameters['name'] ?? '';
    if (fileName.isEmpty) {
      await _writeJson(req, {'ok': false, 'msg': '文件名不能为空'},
          statusCode: HttpStatus.badRequest);
      return;
    }

    // 检查文件大小
    if (req.contentLength != null && req.contentLength! > maxUploadBytes) {
      throw TransferFileTooLargeException(maxUploadBytes);
    }

    final bytes = await _readLimitedBytes(req, maxBytes: maxUploadBytes);

    // 获取保存路径
    final saveDir = await _getSaveDirectory();
    final safeName = _sanitizeFileName(fileName);
    final targetFile = File(p.join(saveDir.path, safeName));

    // 如果文件已存在，重命名
    var finalFile = targetFile;
    int i = 1;
    while (await finalFile.exists()) {
      final ext = p.extension(safeName);
      final stem = p.basenameWithoutExtension(safeName);
      finalFile = File(p.join(saveDir.path, '${stem}_$i$ext'));
      i++;
    }

    await finalFile.writeAsBytes(bytes);
    onFileUploaded?.call(finalFile.path);

    await _writeJson(req, {
      'ok': true,
      'msg': '文件已保存: ${p.basename(finalFile.path)}',
      'path': finalFile.path,
    });
  }

  Future<Directory> _getSaveDirectory() async {
    // 优先使用用户配置的下载路径
    final configPath = StorageManager.getSetting<String>(SettingBoxKey.downloadPath);
    if (configPath != null && configPath.isNotEmpty) {
      final dir = Directory(configPath);
      if (await dir.exists()) return dir;
      await dir.create(recursive: true);
      return dir;
    }
    // 默认回退
    final docs = await getApplicationDocumentsDirectory();
    final defaultDir = Directory(p.join(docs.path, 'transfers'));
    if (!await defaultDir.exists()) {
      await defaultDir.create(recursive: true);
    }
    return defaultDir;
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<Uint8List> _readLimitedBytes(
    HttpRequest req, {
    required int maxBytes,
  }) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in req) {
      total += chunk.length;
      if (total > maxBytes) {
        throw TransferFileTooLargeException(maxBytes);
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> _writeJson(
    HttpRequest req,
    Map<String, Object?> body, {
    int statusCode = HttpStatus.ok,
  }) async {
    req.response.headers.contentType = ContentType.json;
    req.response.statusCode = statusCode;
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  String _uploadPage() {
    final sizeLimit = (maxUploadBytes ~/ (1024 * 1024));
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WiFi 互传 · 源影</title>
<style>
:root { color-scheme: dark; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
  background: #0d1015; color: #e6e9ee;
  min-height: 100vh; display: flex; align-items: center; justify-content: center;
}
.wrap { width: min(560px, 92vw); padding: 40px 0; }
.logo { text-align: center; margin-bottom: 28px; }
.logo h1 { font-size: 24px; letter-spacing: 2px; color: #d9a94b; font-weight: 600; }
.logo p { color: #8b93a1; font-size: 13px; margin-top: 8px; letter-spacing: 1px; }
.drop {
  border: 2px dashed #3a4356; border-radius: 16px; padding: 48px 24px;
  text-align: center; cursor: pointer; transition: all .2s;
  background: #131820;
}
.drop.hover { border-color: #d9a94b; background: #1a212c; }
.drop .icon { font-size: 42px; margin-bottom: 12px; }
.drop .main { font-size: 16px; color: #d9a94b; }
.drop .sub { font-size: 13px; color: #8b93a1; margin-top: 8px; }
#file { display: none; }
.list { margin-top: 20px; }
.item {
  background: #131820; border-radius: 10px; padding: 12px 16px;
  margin-bottom: 10px; display: flex; align-items: center; gap: 12px;
}
.item .name { flex: 1; font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.item .bar { height: 4px; background: #232b38; border-radius: 2px; margin-top: 6px; overflow: hidden; }
.item .bar i { display: block; height: 100%; width: 0; background: #d9a94b; transition: width .15s; }
.item .status { font-size: 12px; color: #8b93a1; white-space: nowrap; }
.item.ok .status { color: #6fce7f; }
.item.err .status { color: #e0655a; }
.tip { margin-top: 24px; text-align: center; color: #57606e; font-size: 12px; line-height: 1.8; }
</style>
</head>
<body>
<div class="wrap">
  <div class="logo">
    <h1>📡 WiFi 互传</h1>
    <p>拖拽或点击上传文件到手机/电脑</p>
  </div>
  <div class="drop" id="drop">
    <div class="icon">📂</div>
    <div class="main">点击选择文件，或拖拽到此处</div>
    <div class="sub">支持任意格式文件 · 单个最大 $sizeLimit MB</div>
  </div>
  <input type="file" id="file" multiple>
  <div class="list" id="list"></div>
  <div class="tip">文件将保存到应用「下载路径」目录<br>上传过程中请保持此页面打开</div>
</div>
<script>
const drop = document.getElementById('drop');
const input = document.getElementById('file');
const list = document.getElementById('list');
drop.addEventListener('click', () => input.click());
drop.addEventListener('dragover', e => { e.preventDefault(); drop.classList.add('hover'); });
drop.addEventListener('dragleave', () => drop.classList.remove('hover'));
drop.addEventListener('drop', e => {
  e.preventDefault(); drop.classList.remove('hover');
  uploadAll(e.dataTransfer.files);
});
input.addEventListener('change', () => { uploadAll(input.files); input.value=''; });

async function uploadAll(files) {
  for (const f of files) { await uploadOne(f); }
}

function uploadOne(file) {
  return new Promise(resolve => {
    const row = document.createElement('div');
    row.className = 'item';
    row.innerHTML = '<div style="flex:1"><div class="name"></div>' +
      '<div class="bar"><i></i></div></div><div class="status">等待中</div>';
    row.querySelector('.name').textContent = file.name;
    list.prepend(row);
    const bar = row.querySelector('.bar i');
    const status = row.querySelector('.status');
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/upload?name=' + encodeURIComponent(file.name));
    xhr.upload.onprogress = e => {
      if (e.lengthComputable) {
        bar.style.width = Math.round(e.loaded / e.total * 100) + '%';
        status.textContent = Math.round(e.loaded / e.total * 100) + '%';
      }
    };
    xhr.onload = () => {
      try {
        const r = JSON.parse(xhr.responseText);
        status.textContent = r.msg || (r.ok ? '成功' : '失败');
        row.classList.add(r.ok ? 'ok' : 'err');
      } catch (e) {
        status.textContent = '完成';
        row.classList.add('ok');
      }
      resolve();
    };
    xhr.onerror = () => { status.textContent = '网络错误'; row.classList.add('err'); resolve(); };
    xhr.send(file);
  });
}
</script>
</body>
</html>
''';
  }
}