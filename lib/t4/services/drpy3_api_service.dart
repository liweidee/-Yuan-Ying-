// drpy3 专用 Service
// - 引擎：flutter_js（Android 上是 QuickJS，iOS 上是 JavaScriptCore）
// - 引擎文件：assets/js/lib/ 下的 5 个 JS
// - 只处理 drpy3 新源（export default / lang: 'dr3'），固定走 rt.load()
// - drpy2 老源请走 Drpy2ApiService（Headless WebView）

import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip, HttpServer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:get/get.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/services/debug_log_service.dart';

class Drpy3ApiService implements ISpiderService {
  // ===== JS 运行时 =====
  JavascriptRuntime? _rt;
  Timer? _pumpTimer;

  // ===== 状态 =====
  bool _ready = false;
  bool _initializing = false;
  final isReady = false.obs;

  // ===== 当前站点 =====
  String? _currentKey;
  String? _pendingExt;
  String? _pendingApiUrl;
  String? _pendingSiteKey;

  // 当前源的 URL 基址（用于 loadAsset 解析相对路径）
  // 走 sourceUrl 加载源文件时记下该 URL（含 query，如 ?pwd=xxx）；
  // 内联源（inlineCode）没有基址，置 null。
  String? _currentSourceBase;

  // ===== 切换锁 =====
  int _siteVersion = 0;
  Completer<void>? _siteReady;

  // ===== stage / load 回调表 =====
  int _nextStageId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _stagePending = {};
  int _nextLoadId = 0;
  final Map<int, Completer<bool>> _loadPending = {};

  // ===== 代理服务器（drpy3 proxy 通道）=====
  HttpServer? _proxyServer;
  int _proxyPort = 0;
  int _nextProxyId = 0;
  final Map<int, Completer<List<dynamic>>> _proxyPending = {};

  // ===== Dio =====
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    validateStatus: (_) => true,
    responseType: ResponseType.bytes,
  ));

  // ===== 引擎文件加载顺序（顺序敏感） =====
  static const _assetDir = 'assets/js/lib/';
  static const _loadOrder = <String>[
    'drpy3-globals-capture.js',
    'drpy-core_dr3.min.js',
    'drpy3-peer.js',
    'htmlParser_dr3.js',
    'drpy3.esm.min.js',
  ];

  @override
  String? get currentKey => _currentKey;
  bool get isRunning => _ready;

  // ============================================================
  // 初始化
  // ============================================================
  Future<bool> ensureInitialized() async {
    if (_ready) return true;
    if (_initializing) {
      while (_initializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _ready;
    }
    _initializing = true;
    try {
      return await init();
    } finally {
      _initializing = false;
    }
  }

  Future<bool> init() async {
    if (_ready) return true;
    try {
      // flutter_js 的 evaluate 不会自动排空 job 队列，
      // 依赖 _pumpTimer 手动推进 Promise 链
      _rt = getJavascriptRuntime();
      debugPrint('[drpy3] flutter_js runtime created');

      _injectConsole();
      _injectTimers();
      _injectHostEnv();

      // 启动代理 server（必须在 Runtime 构造前，因为 getProxy 需要端口号）
      await _startProxyServer();

      for (final name in _loadOrder) {
        final code = await rootBundle.loadString('$_assetDir$name');
        final t0 = DateTime.now();
        _rt!.evaluate(code);
        debugPrint('[drpy3] loaded $name ('
            '${code.length} chars, '
            '${DateTime.now().difference(t0).inMilliseconds}ms)');
      }

      // 注入全局 fetch，供随源 JS（如 emscripten 胶水）使用
      _injectGlobalFetch();

      // 主泵：每 8ms 排空一次 job 队列，推进 drpy3 的 async 链
      _pumpTimer?.cancel();
      _pumpTimer = Timer.periodic(const Duration(milliseconds: 8), (_) {
        try {
          _rt?.executePendingJob();
        } catch (_) {}
      });

      // 构造 Runtime（用普通字符串拼接，把 _proxyPort 注入到 getProxy 里）
      final proxyUrl = 'http://127.0.0.1:$_proxyPort/proxy?do=js';
      final initJs = r'''
        (function () {
          try {
            if (typeof DRPY3 === 'undefined') {
              return JSON.stringify({ ok: false, err: 'DRPY3 not defined' });
            }
            if (typeof globalThis.pdfh !== 'function') {
              return JSON.stringify({ ok: false, err: 'pdfh not defined' });
            }
            globalThis.__rt = new DRPY3.Runtime({
              req:   globalThis.__host_req,
              pdfh:  globalThis.pdfh,
              pdfa:  globalThis.pdfa,
              pd:    globalThis.pd,
              pdfl:  globalThis.pdfl,
              log:   function () {
                try {
                  var a = Array.prototype.slice.call(arguments).map(String);
                  sendMessage('drpy_log', a.join(' '));
                } catch (_) {}
              },
              getProxy: function (isPublic) {
                return '__PROXY_URL__';
              },
              loadAsset: globalThis.__host_loadAsset,
              engine:  'flutter_js',
              version: '0.1.5',
            });
            return JSON.stringify({
              ok: true,
              version: DRPY3.VERSION,
              caps: globalThis.__rt.capabilities,
            });
          } catch (e) {
            return JSON.stringify({ ok: false, err: String(e && e.message || e) });
          }
        })()
      '''.replaceAll('__PROXY_URL__', proxyUrl);

      final initResult = _rt!.evaluate(initJs);

      final initMap = jsonDecode(initResult.stringResult) as Map;
      if (initMap['ok'] != true) {
        debugPrint('[drpy3] Runtime init FAILED: ${initMap['err']}');
        return false;
      }
      debugPrint('[drpy3] Runtime ready: version=${initMap['version']}');
      debugPrint('[drpy3] capabilities=${jsonEncode(initMap['caps'])}');

      if (_pendingApiUrl != null && _pendingSiteKey != null) {
        final url = _pendingApiUrl!;
        final key = _pendingSiteKey!;
        final ext = _pendingExt;
        _pendingApiUrl = null;
        _pendingSiteKey = null;
        _pendingExt = null;
        final version = _siteVersion;
        await _loadSource(version, url, key, ext: ext);
      }

      _ready = true;
      isReady.value = true;
      debugPrint('[drpy3] marked ready');
      return true;
    } catch (e, st) {
      debugPrint('[drpy3] init exception: $e\n$st');
      return false;
    }
  }

  // ============================================================
  // console 注入
  // ============================================================
  void _injectConsole() {
    _rt!.evaluate(r'''
      if (typeof globalThis.console === 'undefined') globalThis.console = {};
      if (typeof console.log !== 'function') {
        console.log = function () {
          try {
            var a = Array.prototype.slice.call(arguments).map(String);
            sendMessage('drpy_log', a.join(' '));
          } catch (_) {}
        };
      }
      if (typeof console.error !== 'function') console.error = console.log;
      if (typeof console.warn  !== 'function') console.warn  = console.log;
      if (typeof console.debug !== 'function') console.debug = console.log;
    ''');

    _rt!.onMessage('drpy_log', (dynamic msg) {
      debugPrint('[drpy3] $msg');
    });
  }

  // ============================================================
  // timer 注入（QuickJS 无事件循环，需要桥接到 Dart）
  // ============================================================
  void _injectTimers() {
    _rt!.evaluate(r'''
      globalThis.__timer_pending__ = {};
      globalThis.__timer_next_id__ = 1;

      globalThis.setTimeout = function (fn, ms) {
        var id = globalThis.__timer_next_id__++;
        globalThis.__timer_pending__[id] = fn;
        try {
          sendMessage('drpy_timer', JSON.stringify({ id: id, ms: ms || 0 }));
        } catch (_) {}
        return id;
      };
      globalThis.setImmediate = function (fn) { return globalThis.setTimeout(fn, 0); };
      globalThis.clearTimeout = function (id) {
        delete globalThis.__timer_pending__[id];
      };
      globalThis.__fire_timer__ = function (id) {
        var fn = globalThis.__timer_pending__[id];
        if (fn) {
          delete globalThis.__timer_pending__[id];
          try { fn(); } catch (e) { console.error('[timer]', e); }
        }
      };
    ''');

    _rt!.onMessage('drpy_timer', (dynamic msg) {
      try {
        final p = _asMap(msg);
        final id = p['id'] as int;
        final ms = p['ms'] as int;
        Future.delayed(Duration(milliseconds: ms), () {
          try {
            _rt?.evaluate('globalThis.__fire_timer__($id)');
          } catch (_) {}
        });
      } catch (e) {
        debugPrint('[drpy3] timer parse error: $e');
      }
    });
  }

  // ============================================================
  // HostEnv 注入
  // ============================================================
  void _injectHostEnv() {
    _rt!.evaluate(r'''
      globalThis.__host_req_pending__ = {};
      globalThis.__host_req_next_id__ = 0;

      globalThis.__host_req = function (url, optionsJson) {
        return new Promise(function (resolve, reject) {
          var id = globalThis.__host_req_next_id__++;
          globalThis.__host_req_pending__[id] = { resolve: resolve, reject: reject };
          try {
            sendMessage('drpy_req', JSON.stringify({
              id: id,
              url: url,
              options: optionsJson || {},
            }));
          } catch (e) {
            delete globalThis.__host_req_pending__[id];
            reject('sendMessage failed: ' + e);
          }
        });
      };

      globalThis.__host_resolve = function (id, respJson) {
        var p = globalThis.__host_req_pending__[id];
        if (!p) return;
        delete globalThis.__host_req_pending__[id];
        try {
          var resp = JSON.parse(respJson);
          if (resp && resp.buffer === 1 && typeof resp.content === 'string') {
            try { resp.content = Uint8Array.fromBase64(resp.content); } catch (_) {}
          }
          p.resolve(resp);
        } catch (e) { p.reject('parse resp failed: ' + e); }
      };

      globalThis.__host_reject = function (id, errMsg) {
        var p = globalThis.__host_req_pending__[id];
        if (!p) return;
        delete globalThis.__host_req_pending__[id];
        p.reject(errMsg);
      };
    ''');

    // loadAsset 桥（drpy3 wasm.js / 模块加载器需要）
    // JS 侧 wasm.load('path') -> sendMessage('drpy_loadasset') -> Dart 侧 Dio 拉字节
    // -> 分块 base64 回传 -> JS 侧分块解码后拼接为 Uint8Array 交给 wasm.js
    //
    // 分块原因：随源 wasm 资产可达数 MB，一次性通过 evaluate 传入会让
    // QuickJS 在解析巨型字符串 + for-of 解码 base64 上被钉住，
    // 进而阻塞 _pumpTimer，整条 async 链卡死。分块后每次量级 64KB，
    // QuickJS 可快速处理并让出主线程。
    _rt!.evaluate(r'''
      globalThis.__host_loadAsset_pending__ = {};
      globalThis.__host_loadAsset_next_id__ = 0;

      globalThis.__host_loadAsset = function (path) {
        return new Promise(function (resolve, reject) {
          var id = globalThis.__host_loadAsset_next_id__++;
          globalThis.__host_loadAsset_pending__[id] = {
            resolve: resolve,
            reject: reject,
            chunks: []
          };
          try {
            sendMessage('drpy_loadasset', JSON.stringify({ id: id, path: path }));
          } catch (e) {
            delete globalThis.__host_loadAsset_pending__[id];
            reject('sendMessage failed: ' + e);
          }
        });
      };

      globalThis.__host_loadAsset_chunk = function (id, b64, isLast) {
        var p = globalThis.__host_loadAsset_pending__[id];
        if (!p) return;
        try {
          if (b64 && b64.length > 0) {
            p.chunks.push(Uint8Array.fromBase64(b64));
          }
          if (isLast) {
            var total = 0;
            for (var i = 0; i < p.chunks.length; i++) total += p.chunks[i].length;
            var out = new Uint8Array(total);
            var off = 0;
            for (var i = 0; i < p.chunks.length; i++) {
              out.set(p.chunks[i], off);
              off += p.chunks[i].length;
            }
            delete globalThis.__host_loadAsset_pending__[id];
            p.resolve(out);
          }
        } catch (e) {
          delete globalThis.__host_loadAsset_pending__[id];
          p.reject('chunk decode failed: ' + e);
        }
      };

      globalThis.__host_loadAsset_reject = function (id, errMsg) {
        var p = globalThis.__host_loadAsset_pending__[id];
        if (!p) return;
        delete globalThis.__host_loadAsset_pending__[id];
        p.reject(errMsg);
      };
    ''');

    _rt!.onMessage('drpy_req', (dynamic msg) async {
      try {
        final p = _asMap(msg);
        final id = p['id'] as int;
        final url = p['url'] as String;
        final opts = (p['options'] as Map?)?.cast<String, dynamic>() ?? {};

        try {
          final resp = await _doDioRequest(url, opts);
          final respJson = jsonEncode(resp);
          _rt?.evaluate(
              'globalThis.__host_resolve($id, ${jsonEncode(respJson)})');
        } catch (e) {
          _rt?.evaluate(
              'globalThis.__host_reject($id, ${jsonEncode(e.toString())})');
        }
      } catch (e) {
        debugPrint('[drpy3] req parse error: $e');
      }
    });

    // loadAsset 请求处理
    // 相对路径（./ 或 ../ 开头，或非 http(s)）用 _currentSourceBase 做 resolve，
    // 并继承 base 的 query（如 ?pwd=xxx），否则鉴权服务器会拒绝。
    _rt!.onMessage('drpy_loadasset', (dynamic msg) async {
      try {
        final p = _asMap(msg);
        final id = p['id'] as int;
        final rawPath = (p['path'] as String?) ?? '';

        String url = rawPath;
        if (!rawPath.startsWith('http://') && !rawPath.startsWith('https://')) {
          final base = _currentSourceBase;
          if (base != null && base.isNotEmpty) {
            final baseUri = Uri.parse(base);
            final resolved = baseUri.resolve(rawPath);
            // Uri.resolve 会丢弃 base 的 query，需要手动补回（rawPath 自带 ? 时不覆盖）
            if (baseUri.hasQuery && !rawPath.contains('?')) {
              url = resolved.replace(query: baseUri.query).toString();
            } else {
              url = resolved.toString();
            }
          } else {
            debugPrint('[drpy3] loadAsset 无 base URL，无法解析相对路径: $rawPath');
            _rt?.evaluate(
              'globalThis.__host_loadAsset_reject($id, '
              '${jsonEncode("无 base URL，无法解析相对路径: $rawPath")})',
            );
            return;
          }
        }

        debugPrint('[drpy3] loadAsset: $rawPath -> $url');

        final resp = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = resp.data ?? <int>[];
        debugPrint('[drpy3] loadAsset resolved: ${bytes.length} bytes');

        // 分块回传给 JS，避免一次性 evaluate 巨型字符串
        // 64KB 是此处甜点：既避免 QuickJS 处理巨型字符串卡顿，
        // 也不至于因为 evaluate 次数过多而让主线程承担额外调用开销。
        //
        // 分块之间 await Future.delayed(Duration.zero)，让出 Dart 事件循环：
        //   - 允许 _pumpTimer 推进 QuickJS job 队列
        //   - 避免 Dart 主线程被连续多次 evaluate 长时间占用
        const chunkSize = 64 * 1024;
        final total = bytes.length;
        if (total == 0) {
          _rt?.evaluate('globalThis.__host_loadAsset_chunk($id, "", true)');
          return;
        }
        for (var off = 0; off < total; off += chunkSize) {
          final end = (off + chunkSize > total) ? total : off + chunkSize;
          final chunk = bytes.sublist(off, end);
          final b64 = base64Encode(chunk);
          final isLast = end >= total;
          _rt?.evaluate(
            'globalThis.__host_loadAsset_chunk($id, ${jsonEncode(b64)}, '
            '${isLast ? 'true' : 'false'})',
          );
          await Future.delayed(Duration.zero);
        }
      } catch (e) {
        debugPrint('[drpy3] loadAsset error: $e');
        try {
          final p = _asMap(msg);
          final id = p['id'] as int;
          _rt?.evaluate(
            'globalThis.__host_loadAsset_reject($id, ${jsonEncode(e.toString())})',
          );
        } catch (_) {}
      }
    });

    _rt!.onMessage('drpy_stage', (dynamic msg) {
      try {
        final p = _asMap(msg);
        final id = p['id'] as int;
        final c = _stagePending.remove(id);
        if (c == null || c.isCompleted) return;
        if (p['ok'] == true) {
          final d = p['data'];
          c.complete(
              d is Map ? d.cast<String, dynamic>() : <String, dynamic>{});
        } else {
          c.complete({
            'success': false,
            'error': p['error'],
            'stack': p['stack'] ?? '',
          });
        }
      } catch (e) {
        debugPrint('[drpy3] stage parse error: $e');
      }
    });

    _rt!.onMessage('drpy_load', (dynamic msg) {
      try {
        final p = _asMap(msg);
        final id = p['id'] as int;
        final c = _loadPending.remove(id);
        if (c == null || c.isCompleted) return;
        if (p['ok'] == true) {
          debugPrint('[drpy3] source loaded: ${p['siteKey']}');
          c.complete(true);
        } else {
          debugPrint('[drpy3] source load FAILED: ${p['error']}');
          c.complete(false);
        }
      } catch (e) {
        debugPrint('[drpy3] load parse error: $e');
      }
    });

    // drpy3 proxy 回环：server 收到请求 -> 调 JS proxy -> 五元组回传
    _rt!.onMessage('drpy_proxy', (dynamic msg) {
      try {
        final p = _asMap(msg);
        final id = p['id'] as int;
        final c = _proxyPending.remove(id);
        if (c == null || c.isCompleted) return;
        if (p['ok'] == true) {
          final d = p['data'];
          c.complete(d is List ? d : <dynamic>[]);
        } else {
          c.complete([500, 'text/plain', 'Proxy error: ${p['error']}']);
        }
      } catch (e) {
        debugPrint('[drpy3][proxy] callback parse error: $e');
      }
    });
  }

  // ============================================================
  // 全局 fetch 注入
  //
  // 目的：drpy3 源里随源的 emscripten 胶水（如 _lib.cctv.worker.new.js）
  //      需要 fetch 能力去请求同目录的 .wasm；
  //      QuickJS 里没有 fetch，drpy3.js 的 makeShim 又把 XMLHttpRequest
  //      实现成了空函数。这里注入一个基于 __host_loadAsset 的 fetch，
  //      让 emscripten 至少能走到 WebAssembly.instantiate 才失败，
  //      而不是在 XHR 上死等。
  //
  // 说明：QuickJS 编译不带 BigInt，WebAssembly 在 Windows/Android 上
  //      无法可用，因此依赖 wasm 的源（如央视频加密 TS）在这些平台
  //      上无法工作。fetch 注入保留是为了让流程能失败得清晰、不卡死。
  // ============================================================
  void _injectGlobalFetch() {
    _rt!.evaluate(r'''
      if (typeof globalThis.fetch !== 'function') {
        globalThis.fetch = function (url) {
          var urlStr = typeof url === 'string'
              ? url
              : (url && url.url) ? url.url : String(url);
          return globalThis.__host_loadAsset(urlStr).then(function (bytes) {
            return {
              ok: true,
              status: 200,
              statusText: 'OK',
              url: urlStr,
              headers: {
                get: function (name) {
                  return String(name).toLowerCase() === 'content-length'
                      ? String(bytes.length) : null;
                },
              },
              arrayBuffer: function () {
                return Promise.resolve(
                  bytes.buffer.slice(bytes.byteOffset,
                      bytes.byteOffset + bytes.byteLength));
              },
              bytes: function () { return Promise.resolve(bytes); },
              clone: function () { return this; },
            };
          });
        };
      }
    ''');
  }

  // ============================================================
  // 参数归一化 / debug 辅助
  // ============================================================
  Map<String, dynamic> _asMap(dynamic msg) {
    if (msg is Map) return msg.cast<String, dynamic>();
    if (msg is String) return (jsonDecode(msg) as Map).cast<String, dynamic>();
    return {};
  }

  String _preview(String? s) {
    if (s == null || s.isEmpty) return '(empty)';
    final t = s.length > 200 ? s.substring(0, 200) : s;
    return 'len=${s.length} head=$t';
  }

  String _safeJson(Object? o, [int max = 300]) {
    try {
      final s = jsonEncode(o);
      return s.length > max ? '${s.substring(0, max)}...(len=${s.length})' : s;
    } catch (_) {
      return o.toString();
    }
  }

  // ============================================================
  // Dio 请求
  // ============================================================
  Future<Map<String, dynamic>> _doDioRequest(
      String url, Map<String, dynamic> opts) async {
    final method = (opts['method'] ?? 'GET').toString().toUpperCase();

    final headers = <String, String>{};
    final rawHeaders = (opts['headers'] as Map?) ?? {};
    rawHeaders.forEach((k, v) {
      if (v == null) return;
      final ks = k.toString();
      final lk = ks.toLowerCase();
      if (lk == 'host' || lk == 'connection') return;
      headers[ks] = v is List ? v.join(', ') : v.toString();
    });
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] =
          'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36';
    }

    dynamic body = opts['body'];
    if (opts['data'] != null) {
      body = jsonEncode(opts['data']);
      headers.putIfAbsent('Content-Type', () => 'application/json');
    }

    final bufferType = opts['buffer'];

    DebugLogService.instance.logRequest(
      method: method,
      url: url,
      headers: headers,
      requestBody: body?.toString(),
      source: 'drpy3',
    );
    final t0 = DateTime.now();

    final resp = await _dio.request(
      url,
      options: Options(
        method: method,
        headers: headers,
        responseType: ResponseType.bytes,
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (_) => true,
      ),
      data: body,
    );

    final bytes = (resp.data as List).cast<int>();
    String content;
    if (bufferType == 1 || bufferType == 2) {
      content = base64Encode(bytes);
    } else {
      content = utf8.decode(bytes, allowMalformed: true);
    }

    final respHeaders = <String, String>{};
    resp.headers.forEach((k, v) {
      if (v.isNotEmpty) respHeaders[k] = v.first;
    });
    respHeaders['access-control-allow-origin'] = '*';

    DebugLogService.instance.logResponse(
      url: url,
      method: method,
      statusCode: resp.statusCode,
      responseBody:
          content.length > 4096 ? content.substring(0, 4096) : content,
      responseSize: content.length,
      source: 'drpy3',
      durationMs: DateTime.now().difference(t0).inMilliseconds,
    );

    return {
      'status': resp.statusCode ?? 200,
      'content': content,
      'headers': respHeaders,
      if (bufferType != null) 'buffer': bufferType,
    };
  }

  // ============================================================
  // stage 调用
  // ============================================================
  Future<Map<String, dynamic>> _callSource(
    String fn,
    List<dynamic> args, {
    int waitRetry = 0,
  }) async {
    final ready = _siteReady;
    if (ready != null && !ready.isCompleted) {
      debugPrint('[drpy3] _callSource $fn 等待切换完成 (v=$_siteVersion)...');
      try {
        await ready.future.timeout(const Duration(seconds: 90));
      } catch (_) {}
      debugPrint('[drpy3] _callSource $fn 切换完成，继续');
    }

    if (waitRetry < 5 && _siteReady != null && !_siteReady!.isCompleted) {
      return _callSource(fn, args, waitRetry: waitRetry + 1);
    }

    if (!_ready) {
      final ok = await ensureInitialized();
      if (!ok) return {'success': false, 'error': 'not ready'};
    }
    if (_rt == null) return {'success': false, 'error': 'runtime null'};

    final id = _nextStageId++;
    final completer = Completer<Map<String, dynamic>>();
    _stagePending[id] = completer;

    final argsJson = jsonEncode(args);
    debugPrint('[drpy3] _callSource $fn args=$argsJson (id=$id)');

    _rt!.evaluate('''
      (async () => {
        try {
          if (!globalThis.__src) {
            sendMessage('drpy_stage', JSON.stringify({
              id: $id, ok: false, error: '__src not loaded yet'
            }));
            return;
          }
          const args = $argsJson;
          const r = await globalThis.__src.$fn(...args);
          sendMessage('drpy_stage', JSON.stringify({
            id: $id, ok: true, data: r || {}
          }));
        } catch (e) {
          sendMessage('drpy_stage', JSON.stringify({
            id: $id,
            ok: false,
            error: String((e && e.message) || e),
            stack: String((e && e.stack) || '')
          }));
        }
      })()
    ''');

    final t0 = DateTime.now();
    final result = await completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        _stagePending.remove(id);
        debugPrint('[drpy3] _callSource $fn TIMEOUT (id=$id)');
        return {'success': false, 'error': 'timeout'};
      },
    );
    debugPrint('[drpy3] _callSource $fn done in '
        '${DateTime.now().difference(t0).inMilliseconds}ms');

    final normalized = _normalizeUrls(result);

    if (normalized['success'] == false) {
      debugPrint('[drpy3] _callSource $fn ERROR: ${normalized['error']}');
    } else {
      final list = normalized['list'];
      if (list is List) {
        debugPrint('[drpy3] _callSource $fn OK list.length=${list.length}');
      } else {
        debugPrint('[drpy3] _callSource $fn OK keys='
            '${normalized.keys.join(",")}  body=${_safeJson(normalized)}');
      }
    }

    return normalized;
  }

  Map<String, dynamic> _normalizeUrls(Map<String, dynamic> result) {
    final list = result['list'];
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final pic = item['vod_pic'];
        if (pic is String && pic.isNotEmpty) {
          if (pic.startsWith('//')) {
            item['vod_pic'] = 'https:$pic';
          }
        }
      }
    }
    return result;
  }

  // ============================================================
  // 代理服务器（drpy3 proxy 通道）
  // ============================================================

  /// 启动本地 HTTP 服务器，用于 drpy3 proxy 回环
  ///
  /// 流程：
  ///   1. drpy3 源内部 `getProxyUrl()` -> 返回 `http://127.0.0.1:{port}/proxy?do=js`
  ///   2. 播放器请求该地址
  ///   3. 本 server 收到 -> 解析 params -> 调 `__src.proxy(params)`
  ///   4. 拿到五元组 [status, contentType, content, headers?, toBytes?]
  ///   5. 按 toBytes 语义回包
  Future<void> _startProxyServer() async {
    if (_proxyServer != null) return;

    final handler = shelf.Pipeline().addHandler((shelf.Request request) async {
      if (request.url.path != 'proxy') {
        return shelf.Response.notFound('Not Found');
      }

      try {
        final params = request.url.queryParameters;
        debugPrint('[drpy3][proxy] ${request.url}');

        final result = await _callJsProxy(params);
        return await _handleProxyResult(result, request);
      } catch (e, st) {
        debugPrint('[drpy3][proxy] error: $e\n$st');
        return shelf.Response.internalServerError(body: 'Proxy error: $e');
      }
    });

    // 动态端口，避免与 Drpy2 WebView bridge / MediaProxy(5575) 冲突
    _proxyServer = await shelf_io.serve(handler, '127.0.0.1', 0);
    _proxyPort = _proxyServer!.port;
    debugPrint('[drpy3][proxy] 已启动: http://127.0.0.1:$_proxyPort/proxy');
  }

  /// 调用 JS 侧 `__src.proxy(params)`，通过 sendMessage('drpy_proxy') 回填
  Future<List<dynamic>> _callJsProxy(Map<String, String> params) async {
    if (!_ready || _rt == null) {
      return [500, 'text/plain', 'Runtime not ready'];
    }

    final id = _nextProxyId++;
    final completer = Completer<List<dynamic>>();
    _proxyPending[id] = completer;

    final paramsJson = jsonEncode(params);

    _rt!.evaluate('''
      (async () => {
        try {
          if (!globalThis.__src) {
            sendMessage('drpy_proxy', JSON.stringify({
              id: $id, ok: false, error: '__src not loaded'
            }));
            return;
          }
          const params = $paramsJson;
          const r = await globalThis.__src.proxy(params);
          sendMessage('drpy_proxy', JSON.stringify({
            id: $id, ok: true,
            data: Array.isArray(r) ? r : [404, 'text/plain', 'Not Found']
          }));
        } catch (e) {
          sendMessage('drpy_proxy', JSON.stringify({
            id: $id, ok: false, error: String((e && e.message) || e)
          }));
        }
      })()
    ''');

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _proxyPending.remove(id);
        debugPrint('[drpy3][proxy] timeout (id=$id)');
        return [504, 'text/plain', 'Proxy timeout'];
      },
    );
  }

  /// 按五元组 [status, contentType, content, headers?, toBytes?] 回包
  ///
  /// toBytes 语义（drpy-node 契约）：
  ///   缺省 -> 文本（m3u8 重写场景）
  ///   1    -> content 为 base64，解码后作为字节（TS 分片解密场景）
  ///   2    -> content 为 URL，302 重定向
  ///   3    -> content 为 URL，服务端流式 pipe（大码率直播，支持 Range）
  Future<shelf.Response> _handleProxyResult(
    List<dynamic> result,
    shelf.Request request,
  ) async {
    if (result.length < 3) {
      return shelf.Response.internalServerError(body: 'Invalid proxy result');
    }

    final status = (result[0] as num?)?.toInt() ?? 404;
    final contentType = result[1]?.toString() ?? 'application/octet-stream';
    final content = result[2];
    final extraHeaders = result.length > 3 && result[3] is Map
        ? Map<String, String>.from((result[3] as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ))
        : <String, String>{};
    final toBytes = result.length > 4 ? result[4] : null;

    final headers = <String, String>{
      'content-type': contentType,
      'access-control-allow-origin': '*',
      ...extraHeaders,
    };

    // toBytes=1：base64 -> 字节回包（TS 分片解密）
    if (toBytes == 1 && content is String) {
      try {
        final bytes = base64Decode(content);
        return shelf.Response(status, body: bytes, headers: headers);
      } catch (e) {
        return shelf.Response.internalServerError(body: 'base64 decode failed');
      }
    }

    // toBytes=2：URL -> 302 重定向
    if (toBytes == 2 && content is String) {
      headers['location'] = content;
      return shelf.Response(302, headers: headers);
    }

    // toBytes=3：URL -> 流式 pipe（透传 Range）
    if (toBytes == 3 && content is String) {
      try {
        final reqHeaders = <String, String>{};
        final range = request.headers['range'];
        if (range != null) reqHeaders['range'] = range;

        final resp = await _dio.get(
          content,
          options: Options(
            responseType: ResponseType.stream,
            headers: reqHeaders,
            validateStatus: (_) => true,
          ),
        );

        final streamHeaders = <String, String>{
          ...headers,
          'content-type': resp.headers.value('content-type') ?? contentType,
        };
        final contentRange = resp.headers.value('content-range');
        if (contentRange != null) streamHeaders['content-range'] = contentRange;
        final acceptRanges = resp.headers.value('accept-ranges');
        if (acceptRanges != null) streamHeaders['accept-ranges'] = acceptRanges;

        final stream = (resp.data as ResponseBody).stream;
        return shelf.Response(
          resp.statusCode ?? 200,
          body: stream,
          headers: streamHeaders,
        );
      } catch (e) {
        debugPrint('[drpy3][proxy] pipe failed: $e');
        return shelf.Response.internalServerError(body: 'pipe failed: $e');
      }
    }

    // 默认：文本回包（m3u8 重写）
    return shelf.Response(
      status,
      body: content is String ? content : content.toString(),
      headers: headers,
    );
  }

  // ============================================================
  // ISpiderService 接口实现
  // ============================================================
  @override
  void setBaseUrl(String url) {}

  /// 触发 drpy3 的生命周期治理（LRU / 内存水位驱逐）
  ///
  /// drpy3 内部有 LifecycleManager 按空闲 LRU / maxHot / 内存水位自动治理实例，
  /// 但不会自动触发，需要宿主显式调用 rt.sweep()。本方法在切源时触发一次。
  ///
  /// sweep 的效果：把闲置的 hot 实例"冷化"（evict），释放其 cache 和 rule；
  /// 实例仍保留在 sources Map 中，下次访问会自动复温（重新 init + 快照回填）。
  ///
  /// 安全性（drpy3 源码保证）：
  ///   - pinned 实例跳过
  ///   - inFlight > 0（正在调用）跳过
  ///   - 只有超过 idleTTL（默认 120s）未使用的才会被冷化
  ///
  /// 调用方式：fire-and-forget，不 await；Promise 由 _pumpTimer 推进完成。
  /// 异常处理：JS 侧 + Dart 侧双层 try/catch，绝不影响主流程。
  void _triggerSweepIfReady() {
    // 前置检查：引擎未就绪时直接返回
    // _ready 为 false 说明 JS 环境还没建立，调用会报错；
    // _rt 为 null 说明 Runtime 还没创建，同理跳过。
    if (!_ready || _rt == null) {
      return;
    }

    try {
      // 通过 evaluate 触发 JS 侧的 sweep
      // 注意：这里不是直接调 __rt.sweep()，而是包一层 IIFE：
      //   1. 用 typeof 检查 __rt 和 sweep 方法是否存在（防止版本不匹配）
      //   2. JS 侧再套一层 try/catch（防止 JS 异常冒泡到 Dart）
      //   3. 不 await 返回的 Promise——交给 _pumpTimer 推进（8ms 一次）
      _rt!.evaluate('''
        (function() {
          try {
            if (globalThis.__rt && typeof globalThis.__rt.sweep === 'function') {
              // sweep 是 async 方法，这里不等它完成；
              // Promise 会被 _pumpTimer 推进，最终完成清理
              globalThis.__rt.sweep();
            }
          } catch (e) {
            // JS 侧静默失败：不影响主流程
          }
        })()
      ''');

      debugPrint('[drpy3] sweep 已触发');
    } catch (e) {
      debugPrint('[drpy3] sweep 触发失败: $e');
    }
  }

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    _siteVersion++;
    _siteReady = Completer<void>();
    final version = _siteVersion;

    if (_stagePending.isNotEmpty) {
      debugPrint(
          '[drpy3] switchSite 清空 ${_stagePending.length} 个 pending stage');
      for (final c in _stagePending.values) {
        if (!c.isCompleted) c.complete(<String, dynamic>{});
      }
      _stagePending.clear();
    }

    // 切站前触发一次 sweep
    _triggerSweepIfReady();

    debugPrint('[drpy3] switchSite(v=$version): key=$siteKey, '
        'ext=${_preview(ext is String ? ext : (ext?.toString() ?? ''))}');

    _currentKey = siteKey;
    _pendingExt = ext is String ? ext : (ext?.toString() ?? '');

    if (!_ready) {
      _pendingApiUrl = apiUrl;
      _pendingSiteKey = siteKey;
      unawaited(ensureInitialized());
      return;
    }
    unawaited(_loadSource(version, apiUrl, siteKey, ext: _pendingExt));
  }

  Future<void> _loadSource(
    int version,
    String apiUrl,
    String siteKey, {
    dynamic ext,
  }) async {
    if (!await ensureInitialized()) {
      _completeSiteReady(version);
      return;
    }
    if (_rt == null) {
      _completeSiteReady(version);
      return;
    }

    try {
      final extStr = ext is String ? ext : (ext?.toString() ?? '');
      debugPrint('[drpy3] _loadSource(v=$version): '
          'apiUrl=$apiUrl, ext=${_preview(extStr)}');

      String? sourceUrl;
      String? inlineCode;

      // 解析源文件来源
      if (extStr.isNotEmpty) {
        if (extStr.startsWith('http://') || extStr.startsWith('https://')) {
          sourceUrl = extStr;
        } else if (extStr.contains('export default') ||
            extStr.contains('defineSource') ||
            extStr.startsWith('{')) {
          inlineCode = extStr;
        } else {
          try {
            inlineCode = await rootBundle.loadString(extStr);
          } catch (_) {
            debugPrint('[drpy3] ext 无法识别: ${_preview(extStr)}');
          }
        }
      }

      if (sourceUrl == null && inlineCode == null && apiUrl.isNotEmpty) {
        debugPrint('[drpy3] WARN: ext 为空，尝试用 apiUrl 兜底：$apiUrl');
        sourceUrl = apiUrl;
      }

      if (sourceUrl == null && inlineCode == null) {
        debugPrint('[drpy3] _loadSource: 无规则来源，跳过');
        _completeSiteReady(version);
        return;
      }

      String code;
      if (inlineCode != null) {
        code = inlineCode;
        // 内联源没有 URL 基址，清空（wasm.load 相对路径将失败并报清晰错误）
        _currentSourceBase = null;
      } else {
        DebugLogService.instance.logRequest(
          method: 'GET',
          url: sourceUrl!,
          source: 'drpy3',
        );
        final resp = await _dio.get<List<int>>(
          sourceUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        code = utf8.decode((resp.data ?? []), allowMalformed: true);
        // 记录当前源的 URL（含 query，如 ?pwd=xxx），
        // 供 loadAsset 解析相对路径 + 继承鉴权参数
        _currentSourceBase = sourceUrl;
      }

      debugPrint('[drpy3] source code length=${code.length} from '
          '${sourceUrl ?? "(inline)"}');
      debugPrint('[drpy3] source base = ${_currentSourceBase ?? "(none)"}');

      // 兼容 base64+gzip 加密源（可选）
      final trimmed = code.trimLeft();
      if (trimmed.startsWith('H4sI')) {
        debugPrint('[drpy3] 检测到 base64+gzip 加密源，解码中');
        try {
          final cleaned = code.replaceAll(RegExp(r'\s'), '');
          final bytes = base64Decode(cleaned);
          code = utf8.decode(gzip.decode(bytes), allowMalformed: true);
          debugPrint('[drpy3] base64 解码后长度=${code.length}');
        } catch (e) {
          debugPrint('[drpy3] base64+gzip 解码失败: $e');
        }
      }

      // 强制走 load（drpy3 新源）
      final id = _nextLoadId++;
      final completer = Completer<bool>();
      _loadPending[id] = completer;

      final codeJson = jsonEncode(code);
      final keyJson = jsonEncode(siteKey);
      final pathJson = jsonEncode(sourceUrl ?? '');
      final extJson = jsonEncode(extStr);

      _rt!.evaluate('''
        (async () => {
          try {
            globalThis.__src = await globalThis.__rt.load(
              $codeJson,
              { key: $keyJson, path: $pathJson }
            );
            if (typeof globalThis.__src.init === 'function') {
              await globalThis.__src.init($extJson);
            }
            sendMessage('drpy_load', JSON.stringify({
              id: $id, ok: true, siteKey: $keyJson
            }));
          } catch (e) {
            sendMessage('drpy_load', JSON.stringify({
              id: $id,
              ok: false,
              error: String((e && e.message) || e),
              stack: String((e && e.stack) || '')
            }));
          }
        })()
      ''');

      await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _loadPending.remove(id);
          debugPrint('[drpy3] _loadSource TIMEOUT');
          return false;
        },
      );
    } finally {
      _completeSiteReady(version);
    }
  }

  void _completeSiteReady(int version) {
    if (version != _siteVersion) {
      debugPrint('[drpy3] _completeSiteReady(v=$version) 跳过 '
          '(当前 v=$_siteVersion)');
      return;
    }
    final c = _siteReady;
    if (c != null && !c.isCompleted) {
      debugPrint('[drpy3] _completeSiteReady(v=$version) 唤醒');
      c.complete();
    }
  }

  // ============================================================
  // 业务入口
  // ============================================================
  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) =>
      _callSource('home', [filter]);

  @override
  Future<Map<String, dynamic>> fetchCate(String cateId, int page,
          {String? ext}) =>
      _callSource('category', [cateId, page, false, {}]);

  @override
  Future<Map<String, dynamic>> search(String wd, int page,
          {int quick = 0}) =>
      _callSource('search', [wd, quick == 1, page]);

  @override
  Future<VideoDetail?> getDetail(
      {required String vodId, required String pwd}) async {
    final map = await _callSource('detail', [vodId]);
    final list = map['list'];
    if (list is! List || list.isEmpty) {
      debugPrint('[drpy3] getDetail 空列表 vodId=$vodId');
      return null;
    }
    final data = (list[0] as Map).cast<String, dynamic>();
    return VideoDetail(
      vodId: data['vod_id']?.toString() ?? vodId,
      vodName: data['vod_name']?.toString() ?? '未命名',
      vodPic: data['vod_pic']?.toString() ?? '',
      vodContent: data['vod_content']?.toString(),
      playSources: _parsePlaySources(data),
    );
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) =>
      _callSource('detail', [ids]);

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    final map = await _callSource('play', [flag, playParams, []]);
    if (map['data'] is Map) {
      return PlayUrl.fromJson((map['data'] as Map).cast<String, dynamic>());
    }
    if (map['parse'] != null || map['url'] != null) {
      return PlayUrl.fromJson(map);
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play,
          {String? flag}) =>
      _callSource('play', [flag ?? '', play, []]);

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) =>
      search(wd, page, quick: quick);

  List<PlaySource> _parsePlaySources(Map<String, dynamic> map) {
    final from = map['vod_play_from']?.toString() ?? '';
    final url = map['vod_play_url']?.toString() ?? '';
    if (from.isEmpty || url.isEmpty) return [];

    final fromList = from.split(r'$$$');
    final urlList = url.split(r'$$$');
    final out = <PlaySource>[];
    for (var i = 0; i < fromList.length && i < urlList.length; i++) {
      final eps = <Episode>[];
      for (final part in urlList[i].split('#')) {
        if (part.trim().isEmpty) continue;
        final kv = part.split(r'$');
        if (kv.length == 2) eps.add(Episode(name: kv[0], url: kv[1]));
      }
      if (eps.isNotEmpty) {
        out.add(PlaySource(name: fromList[i], episodes: eps));
      }
    }
    return out;
  }

  void dispose() {
    // 关闭代理 server
    _proxyServer?.close(force: true);
    _proxyServer = null;
    _proxyPending.clear();

    _pumpTimer?.cancel();
    _pumpTimer = null;
    _rt?.dispose();
    _rt = null;
    _ready = false;
    isReady.value = false;
    _stagePending.clear();
    _loadPending.clear();
    _siteReady = null;
    // 清掉 base 缓存，避免下次切换源时误用旧值
    _currentSourceBase = null;
  }
}