import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:xml/xml.dart';

import '../models/webdav_server.dart';
import '../models/webdav_entry.dart';

class WebDavService {
  WebDavService._();
  static final WebDavService instance = WebDavService._();

  // ------------------------------------------------------------------
  // 构建请求用 Dio 实例
  // ------------------------------------------------------------------
  Dio _buildDio({
    required String url,
    String username = '',
    String password = '',
    bool allowSelfSigned = false,
  }) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (_) => true, // WebDAV 响应码可能不是 2xx
    ));
    if (username.isNotEmpty) {
      final auth =
          'Basic ${base64Encode(utf8.encode('$username:$password'))}';
      dio.options.headers['Authorization'] = auth;
    }
    if (allowSelfSigned) {
      dio.httpClientAdapter = _permissiveAdapter();
    }
    return dio;
  }

  /// 允许自签名证书的 adapter（Dio 5.x 写法）
  HttpClientAdapter _permissiveAdapter() {
    return IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );
  }

  // ------------------------------------------------------------------
  // 提取 server URL 的 base path
  // http://host:8080/dav  →  /dav
  // http://host:8080      →  ''
  // ------------------------------------------------------------------
  String _serverBasePath(String serverUrl) {
    final uri = Uri.parse(serverUrl);
    var p = uri.path;
    if (p == '/' || p.isEmpty) return '';
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  /// server 根 URL（去尾斜杠）
  String _serverRoot(String serverUrl) {
    return serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
  }

  /// 拼接完整请求 URL
  /// [relativePath] 是相对 WebDAV 根的路径（空串 / '/' 表示根）
  String _buildUrl(String serverUrl, String relativePath) {
    final base = _serverRoot(serverUrl);
    if (relativePath.isEmpty || relativePath == '/') return base;
    final clean =
        relativePath.startsWith('/') ? relativePath : '/$relativePath';
    final encoded = clean
        .split('/')
        .map((seg) => Uri.encodeComponent(seg))
        .join('/');
    return '$base$encoded';
  }

  // ------------------------------------------------------------------
  // 测试连接（PROPFIND depth 0）
  // ------------------------------------------------------------------
  Future<({bool ok, String? error})> testConnection({
    required String url,
    String username = '',
    String password = '',
    bool allowSelfSigned = false,
  }) async {
    try {
      final dio = _buildDio(
        url: url,
        username: username,
        password: password,
        allowSelfSigned: allowSelfSigned,
      );
      final base = _serverRoot(url);
      final resp = await dio.request(
        base,
        options: Options(
          method: 'PROPFIND',
          headers: {'Depth': '0'},
        ),
      );
      final code = resp.statusCode ?? 0;
      if (code == 207 || code == 200) return (ok: true, error: null);
      if (code == 401) return (ok: false, error: '认证失败');
      if (code == 403) return (ok: false, error: '无权限访问');
      if (code == 404) return (ok: false, error: '路径不存在');
      return (ok: false, error: 'HTTP $code');
    } on SocketException catch (e) {
      return (ok: false, error: '无法连接：${e.osError?.message ?? e.message}');
    } on HandshakeException {
      return (ok: false, error: '证书不被信任（可尝试开启"允许自签名"）');
    } on DioException catch (e) {
      return (ok: false, error: '连接失败：${e.message}');
    } catch (e) {
      return (ok: false, error: '$e');
    }
  }

  // ------------------------------------------------------------------
  // 列目录（PROPFIND depth 1 + XML 解析）
  // ------------------------------------------------------------------
  Future<List<WebDavEntry>> listDirectory(
    WebDavServer server,
    String path,
  ) async {
    final dio = _buildDio(
      url: server.url,
      username: server.username,
      password: server.password,
      allowSelfSigned: server.allowSelfSigned,
    );

    final serverBasePath = _serverBasePath(server.url);

    // 归一化 relativePath
    final cleanPath = (path.isEmpty || path == '/')
        ? ''
        : (path.startsWith('/') ? path : '/$path');

    final fullUrl = _buildUrl(server.url, cleanPath);

    final resp = await dio.request(
      fullUrl,
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '1'},
      ),
    );

    final code = resp.statusCode ?? 0;
    if (code != 207 && code != 200) {
      if (code == 401) throw Exception('认证失败');
      if (code == 403) throw Exception('无权限访问');
      if (code == 404) throw Exception('路径不存在');
      throw Exception('HTTP $code');
    }

    final body = resp.data;
    final xmlStr = body is String ? body : '';
    return _parseMultiStatus(
      xmlStr,
      serverBasePath: serverBasePath,
      currentPath: cleanPath.isEmpty ? '/' : cleanPath,
    );
  }

  // ------------------------------------------------------------------
  // 解析 WebDAV multistatus XML
  //
  // [serverBasePath] 是 server.url 的路径部分（如 `/dav`），
  // 用于从 href 中剥离出相对 WebDAV 根的路径。
  // [currentPath] 是当前请求的相对路径（用于跳过响应里的"自身"）。
  // ------------------------------------------------------------------
  List<WebDavEntry> _parseMultiStatus(
    String xmlStr, {
    required String serverBasePath,
    required String currentPath,
  }) {
    if (xmlStr.isEmpty) return const [];

    final doc = XmlDocument.parse(xmlStr);
    final responses =
        doc.descendantElements.where((e) => e.name.local == 'response');

    final items = <WebDavEntry>[];

    // 归一化 currentPath 用于跳过自身
    final currentClean = currentPath.endsWith('/') && currentPath.length > 1
        ? currentPath.substring(0, currentPath.length - 1)
        : currentPath;

    for (final resp in responses) {
      String? href;
      bool isDir = false;
      int size = 0;
      DateTime? modified;

      for (final el in resp.descendantElements) {
        switch (el.name.local) {
          case 'href':
            href ??= el.innerText;
            break;
          case 'collection':
            isDir = true;
            break;
          case 'getcontentlength':
            size = int.tryParse(el.innerText) ?? 0;
            break;
          case 'getlastmodified':
            try {
              modified = DateTime.parse(el.innerText);
            } catch (_) {}
            break;
        }
      }

      if (href == null || href.isEmpty) continue;

      // 解析 href 为完整路径（含 server base path）
      String fullPath;
      try {
        final parsed = Uri.parse(href);
        fullPath = parsed.path.isNotEmpty
            ? Uri.decodeComponent(parsed.path)
            : Uri.decodeComponent(href);
      } catch (_) {
        fullPath = href;
      }

      // ★ 关键：剥离 server base path，得到相对 WebDAV 根的路径
      var relativePath = fullPath;
      if (serverBasePath.isNotEmpty &&
          fullPath.startsWith(serverBasePath)) {
        relativePath = fullPath.substring(serverBasePath.length);
      }
      // 确保以 / 开头
      if (!relativePath.startsWith('/')) relativePath = '/$relativePath';
      // 去掉末尾斜杠
      if (relativePath.endsWith('/') && relativePath.length > 1) {
        relativePath =
            relativePath.substring(0, relativePath.length - 1);
      }

      // 跳过"自身"条目
      if (relativePath == currentClean || relativePath.isEmpty) continue;

      final name =
          relativePath.split('/').where((s) => s.isNotEmpty).last;
      if (name.isEmpty) continue;

      items.add(WebDavEntry(
        name: name,
        path: relativePath,
        isDirectory: isDir,
        size: size,
        modified: modified,
      ));
    }

    // 目录在前，按名称排序
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  // ------------------------------------------------------------------
  // 构造播放直链
  // ------------------------------------------------------------------
  String buildPlayableUrl(WebDavServer server, String path) {
    final cleanPath = (path.isEmpty || path == '/')
        ? ''
        : (path.startsWith('/') ? path : '/$path');
    return _buildUrl(server.url, cleanPath);
  }

  // ------------------------------------------------------------------
  // 生成播放器请求头（Basic 认证）
  // ------------------------------------------------------------------
  Map<String, String> buildHeaders(WebDavServer server) {
    if (server.username.isEmpty) return const {};
    return {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('${server.username}:${server.password}'))}',
    };
  }

  // ------------------------------------------------------------------
  // 下载文件
  // ------------------------------------------------------------------
  Future<void> download({
    required WebDavServer server,
    required String remotePath,
    required String localPath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dio = _buildDio(
      url: server.url,
      username: server.username,
      password: server.password,
      allowSelfSigned: server.allowSelfSigned,
    );
    final url = buildPlayableUrl(server, remotePath);
    await dio.download(
      url,
      localPath,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );
  }
}