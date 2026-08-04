import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/services/debug_log_service.dart';

class Drpy2ApiService implements ISpiderService {
  // ===== 静态资源缓存（内存） =====
  final Map<String, Uint8List> _fileCache = {};

  // ===== WebView 相关 =====
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _ctrl;

  // ===== HTTP 服务器 =====
  HttpServer? _httpServer;
  int _port = 0;

  // ===== 状态 =====
  bool _ready = false;
  bool _initializing = false;
  final isReady = false.obs;

  // ===== 站点信息 =====
  String? _currentKey;
  String? _pendingExt;
  Map<String, dynamic>? _currentExtMap;

  // ===== Dio 实例 =====
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    validateStatus: (_) => true,
    responseType: ResponseType.plain,
  ));

  // ===== 接口实现 =====
  String? get currentKey => _currentKey;
  bool get isRunning => _ready;

  // ============================================================
  // 初始化（懒加载）
  // ============================================================
  Future<bool> ensureInitialized() async {
    if (_ready) return true;
    if (_initializing) {
      while (_initializing) await Future.delayed(Duration(milliseconds: 100));
      return _ready;
    }
    _initializing = true;
    try {
      final success = await init();
      return success;
    } finally {
      _initializing = false;
    }
  }

  Future<bool> init() async {
    if (_ready) return true;

    try {
      await _loadFilesToMemory();
      await _startHttpServer();
      await _createHeadlessWebView();
      await _loadHostPage();
      await _waitReady();

      if (_pendingExt != null && _pendingExt!.isNotEmpty) {
        await reinit(_pendingExt!);
      }

      _ready = true;
      isReady.value = true;
      debugPrint('[drpy2] init SUCCESS');
      return true;
    } catch (e, st) {
      debugPrint('[drpy2] init failed: $e\n$st');
      return false;
    }
  }

  // ============================================================
  // 加载静态资源到内存
  // ============================================================
  Future<void> _loadFilesToMemory() async {
    final files = {
      'drpy-core.min.js': 'assets/js/lib/drpy-core.min.js',
      'inject.js': 'assets/js/lib/inject.js',
      'drpy2.min.js': 'assets/js/lib/drpy2.min.js',
      'htmlParser.js': 'assets/js/lib/htmlParser.js',
    };

    for (final entry in files.entries) {
      final data = await rootBundle.load(entry.value);
      _fileCache[entry.key] = data.buffer.asUint8List();
    }

    _fileCache['drpy_host.html'] =
        Uint8List.fromList(utf8.encode(_generateHostHtml()));
  }

  String _generateHostHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8" />
<script type="importmap">
{
  "imports": {
    "./drpy-core.min.js": "./drpy-core.min.js",
    "./inject.js": "./inject.js",
    "./drpy2.min.js": "./drpy2.min.js"
  }
}
</script>
<script>
const _origLog = console.log;
console.log = function(...args) {
  _origLog.apply(console, args);
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('drpy_log', args.join(' '));
  }
};
const _origErr = console.error;
console.error = function(...args) {
  _origErr.apply(console, args);
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('drpy_error', args.join(' '));
  }
};
window.addEventListener('error', function(e) {
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('drpy_error', e.message + ' at ' + e.filename + ':' + e.lineno);
  }
});
</script>
</head>
<body>
<script type="module">
try {
  console.log('[host] step0: importing inject.js...');
  const inject = await import('./inject.js');
  console.log('[host] step0 done, inject keys:', Object.keys(inject).join(','));

  for (const k in inject) {
    if (typeof inject[k] !== 'undefined') {
      window[k] = inject[k];
    }
  }

  console.log('[host] step1: importing drpy2.min.js...');
  const mod = await import('./drpy2.min.js');
  const exp = mod.default || mod;
  console.log('[host] step2: drpy2 loaded, keys:', Object.keys(exp).join(','));

  for (const k in exp) {
    if (typeof exp[k] === 'function') {
      window[k] = exp[k];
    }
  }
  window.__drpy2 = exp;

  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('drpy_ready', 'ok');
    console.log('[host] >>> WebView ready <<<');
  }
} catch(e) {
  console.error('[host] FATAL:', e.message || e);
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('drpy_error', e.message || String(e));
  }
}
</script>
</body>
</html>
''';
  }

  // ============================================================
  // HTTP 服务器（包含静态文件和 /__bridge__ 路由）
  // ============================================================
  Future<void> _startHttpServer() async {
    if (_httpServer != null) return;

    final handler = shelf.Pipeline().addHandler((request) async {
      // --- 处理 /__bridge__ 代理请求 ---
      if (request.url.path == '__bridge__') {
        print('========== BRIDGE REQUEST ==========');
        final body = await request.readAsString();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        final url = payload['url'] as String;
        final method = payload['method'] as String? ?? 'GET';
        final rawHeaders = payload['headers'] as Map? ?? {};

        print('[bridge] URL: $url');
        print('[bridge] Method: $method');
        print('[bridge] Headers: $rawHeaders');

        // ---- 构建 headers，过滤 Host/Connection，补充默认头 ----
        final headers = <String, String>{};
        rawHeaders.forEach((key, value) {
          final keyStr = key.toString();
          final lowerKey = keyStr.toLowerCase();
          if (lowerKey == 'host' || lowerKey == 'connection') {
            return;
          }
          if (value != null) {
            if (value is List) {
              headers[keyStr] = value.map((e) => e.toString()).join(', ');
            } else {
              headers[keyStr] = value.toString();
            }
          }
        });

        // 补充 Accept
        if (!headers.containsKey('Accept')) {
          headers['Accept'] = 'application/json, text/plain, */*';
        }
        // 补充 Origin（如果有 Referer）
        if (headers.containsKey('Referer') && !headers.containsKey('Origin')) {
          final ref = headers['Referer']!;
          try {
            final uri = Uri.parse(ref);
            final origin = '${uri.scheme}://${uri.host}';
            headers['Origin'] = origin;
          } catch (_) {}
        }
        // 确保有 User-Agent（如果规则未提供）
        if (!headers.containsKey('User-Agent')) {
          headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36';
        }

        print('[bridge] Final headers: $headers');

        // 请求记录
        DebugLogService.instance.logRequest(
          method: method,
          url: url,
          headers: headers,
          requestBody: payload['body'] is String ? payload['body'] : null,
          source: 'drpy2',
        );

        final startTime = DateTime.now();

        try {
          final response = await _dio.request(
            url,
            options: Options(
              method: method,
              headers: headers,
              followRedirects: true,
              maxRedirects: 5,
              responseType: ResponseType.plain,
            ),
            data: payload['body'] is String ? payload['body'] : null,
          );

          print('========== BRIDGE RESPONSE ==========');
          print('[bridge] Status: ${response.statusCode}');
          print('[bridge] Headers: ${response.headers}');
          final duration = DateTime.now().difference(startTime).inMilliseconds;
          String respBody = response.data ?? '';

          DebugLogService.instance.logResponse(
            url: url,
            method: method,
            statusCode: response.statusCode,
            responseBody: respBody,
            responseSize: respBody.length,
            source: 'drpy2',
            durationMs: duration,
          );
          if (respBody.length > 2000) {
            print('[bridge] Body (first 2000 chars): ${respBody.substring(0, 2000)}');
            print('[bridge] Body length: ${respBody.length}');
          } else {
            print('[bridge] Body: $respBody');
          }

          final respHeaders = <String, String>{};
          response.headers.forEach((key, values) {
            if (values.isNotEmpty) respHeaders[key] = values.first;
          });
          respHeaders['access-control-allow-origin'] = '*';

          return shelf.Response.ok(
            jsonEncode({
              'status': response.statusCode ?? 200,
              'headers': respHeaders,
              'body': respBody,
            }),
            headers: {'content-type': 'application/json'},
          );
        } catch (e) {
          DebugLogService.instance.logResponse(
            url: url,
            method: method,
            statusCode: null,
            responseBody: e.toString(),
            source: 'drpy2',
          );
          print('[bridge] ERROR: $e');
          return shelf.Response.ok(
            jsonEncode({'status': 500, 'body': '', 'error': e.toString()}),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      // --- 静态文件服务 ---
      final path = request.url.path.isEmpty ? 'drpy_host.html' : request.url.path;
      final data = _fileCache[path];
      if (data == null) {
        return shelf.Response.notFound('Not Found');
      }
      final contentType = _getContentType(path);
      return shelf.Response.ok(data, headers: {'content-type': contentType});
    });

    _httpServer = await shelf_io.serve(handler, '127.0.0.1', 0);
    _port = _httpServer!.port;
    debugPrint('[drpy2] HTTP server on http://127.0.0.1:$_port/');
  }

  String _getContentType(String filename) {
    if (filename.endsWith('.html') || filename.endsWith('.htm')) {
      return 'text/html; charset=utf-8';
    }
    if (filename.endsWith('.js') || filename.endsWith('.mjs')) {
      return 'application/javascript; charset=utf-8';
    }
    if (filename.endsWith('.css')) return 'text/css; charset=utf-8';
    if (filename.endsWith('.json')) return 'application/json; charset=utf-8';
    if (filename.endsWith('.wasm')) return 'application/wasm';
    return 'application/octet-stream';
  }

  // ============================================================
  // WebView 创建与加载
  // ============================================================
  Future<void> _createHeadlessWebView() async {
    _headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useHybridComposition: true,
        allowUniversalAccessFromFileURLs: true,
        allowFileAccessFromFileURLs: true,
      ),
      onWebViewCreated: (ctrl) {
        _ctrl = ctrl;
        debugPrint('[drpy2] WebView created');
      },
      onConsoleMessage: (ctrl, msg) {
        debugPrint('[drpy2][console] ${msg.message}');
      },
    );

    await _headless!.run();
    debugPrint('[drpy2] HeadlessInAppWebView.run() done');

    _ctrl!.addJavaScriptHandler(
      handlerName: 'drpy_ready',
      callback: (args) {
        _ready = true;  // 注意：这里设置 _ready 为 true，但 isReady 仍然在 init 末尾设置
        debugPrint('[drpy2] >>> WebView ready <<<');
        return 'ok';
      },
    );
    _ctrl!.addJavaScriptHandler(
      handlerName: 'drpy_log',
      callback: (args) {
        debugPrint('[drpy2][js] ${args.first}');
        return 'ok';
      },
    );
    _ctrl!.addJavaScriptHandler(
      handlerName: 'drpy_error',
      callback: (args) {
        debugPrint('[drpy2][ERROR] ${args.first}');
        return 'ok';
      },
    );
  }

  Future<void> _loadHostPage() async {
    final url = 'http://127.0.0.1:$_port/drpy_host.html';
    debugPrint('[drpy2] loading: $url');
    await _ctrl!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _waitReady() async {
    for (var i = 0; i < 150 && !_ready; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!_ready) {
      throw Exception('drpy2 WebView ready timeout');
    }
  }

  // ============================================================
  // 规则重新加载（快速切换站点）
  // ============================================================
  Future<void> reinit(String ext) async {
    if (!_ready || _ctrl == null) {
      _pendingExt = ext;
      return;
    }
    final encodedExt = Uri.encodeFull(ext);
    await _ctrl!.evaluateJavascript(source: "window.reinit('$encodedExt')");
    debugPrint('[drpy2] reinit applied');
  }

  // ============================================================
  // ISpiderService 实现
  // ============================================================
  @override
  void setBaseUrl(String url) {}

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    _currentKey = siteKey;
    final extStr = ext is String ? ext : (ext?.toString() ?? '');
    if (extStr.isNotEmpty) {
      try {
        _currentExtMap = jsonDecode(extStr) as Map<String, dynamic>;
      } catch (_) {
        _currentExtMap = null;
      }
    } else {
      _currentExtMap = null;
    }

    if (_ready) {
      reinit(extStr);
    } else {
      _pendingExt = extStr;
      ensureInitialized();
    }
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) {
    return _call('home', []);
  }

  @override
  Future<Map<String, dynamic>> fetchCate(String cateId, int page, {String? ext}) {
    final filter = <String, dynamic>{};
    final extend = _currentExtMap ?? <String, dynamic>{};
    return _call('category', [cateId, page, filter, extend]);
  }

  @override
  Future<Map<String, dynamic>> search(String wd, int page, {int quick = 0}) {
    return _call('search', [wd, quick, page]);
  }

  @override
  Future<VideoDetail?> getDetail({required String vodId, required String pwd}) async {
    final map = await _call('detail', [vodId]);
    final list = map['list'];
    if (list is List && list.isNotEmpty) {
      final dataMap = list[0] as Map<String, dynamic>;
      try {
        return VideoDetail.fromJson(dataMap);
      } catch (e) {
        return VideoDetail(
          vodId: dataMap['vod_id']?.toString() ?? vodId,
          vodName: dataMap['vod_name']?.toString() ?? '未命名',
          vodPic: dataMap['vod_pic']?.toString() ?? '',
          vodContent: dataMap['vod_content']?.toString(),
          playSources: _parsePlaySources(dataMap),
        );
      }
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) {
    return _call('detail', [ids]);
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    final map = await _call('play', [flag, playParams, []]);
    Map<String, dynamic>? playData;
    if (map['data'] is Map) {
      playData = map['data'] as Map<String, dynamic>;
    } else if (map.containsKey('parse')) {
      playData = map;
    }
    if (playData != null) {
      return PlayUrl.fromJson(playData);
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) {
    return _call('play', [flag ?? '', play, []]);
  }

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) {
    return search(wd, page, quick: quick);
  }

  // ============================================================
  // 私有辅助方法
  // ============================================================
  String _toJsArg(dynamic arg) {
    if (arg == null) return 'null';
    if (arg is String) {
      final escaped = arg.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      return "'$escaped'";
    }
    if (arg is bool || arg is num) return arg.toString();
    if (arg is List) {
      final items = arg.map(_toJsArg).join(',');
      return '[$items]';
    }
    if (arg is Map) {
      final entries = arg.entries.map((e) {
        final key = _toJsArg(e.key.toString());
        final value = _toJsArg(e.value);
        return '$key:$value';
      }).join(',');
      return '{$entries}';
    }
    return jsonEncode(arg);
  }

  Future<Map<String, dynamic>> _call(String fn, List<dynamic> args) async {
    if (!_ready || _ctrl == null) {
      // 等待就绪（最多 15 秒）
      for (var i = 0; i < 150 && !_ready; i++) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      if (!_ready) {
        return {'success': false, 'error': 'not ready'};
      }
    }
    final argStr = args.map(_toJsArg).join(',');
    final source = "window.__drpy2.$fn($argStr)";
    debugPrint('[drpy2] _call: $source');

    try {
      final result = await _ctrl!.evaluateJavascript(source: source);
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      } else if (result is String) {
        return jsonDecode(result) as Map<String, dynamic>;
      } else {
        return {'success': false, 'error': 'invalid result type: ${result.runtimeType}'};
      }
    } catch (e) {
      debugPrint('[drpy2] _call $fn error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  List<PlaySource> _parsePlaySources(Map<String, dynamic> map) {
    final from = map['vod_play_from']?.toString() ?? '';
    final url = map['vod_play_url']?.toString() ?? '';
    if (from.isEmpty || url.isEmpty) return [];

    final fromList = from.split('\$\$\$');
    final urlList = url.split('\$\$\$');
    final sources = <PlaySource>[];
    for (int i = 0; i < fromList.length && i < urlList.length; i++) {
      final episodes = _parseEpisodes(urlList[i]);
      if (episodes.isNotEmpty) {
        sources.add(PlaySource(name: fromList[i], episodes: episodes));
      }
    }
    return sources;
  }

  List<Episode> _parseEpisodes(String urlStr) {
    final episodes = <Episode>[];
    for (final part in urlStr.split('#')) {
      if (part.trim().isEmpty) continue;
      final parts = part.split('\$');
      if (parts.length == 2) {
        episodes.add(Episode(name: parts[0], url: parts[1]));
      }
    }
    return episodes;
  }

  // ============================================================
  // 资源释放
  // ============================================================
  void dispose() {
    _headless?.dispose();
    _httpServer?.close();
    _ready = false;
    isReady.value = false;
  }
}