import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:qjs_ultra/qjs_ultra.dart';

import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/utils/qjs_platform_helper.dart';

// ============================================================
// 模块加载器（只用于 drpy-core-lite 和 drpy2）
// ============================================================
class _Drpy2ModuleLoader implements JsModuleLoader {
  final Map<String, String> _sources;
  _Drpy2ModuleLoader(this._sources);

  String _basename(String name) {
    var n = name;
    final q = n.indexOf('?');
    if (q >= 0) n = n.substring(0, q);
    final h = n.indexOf('#');
    if (h >= 0) n = n.substring(0, h);
    final slash = n.lastIndexOf('/');
    if (slash >= 0) n = n.substring(slash + 1);
    return n;
  }

  @override
  Uint8List? getModuleBytecode(String name) => null;

  @override
  String? getModuleSource(String name) {
    final n = _basename(name);
    final src = _sources[n];
    if (src == null) {
      debugPrint('[QjsDrpy2/loader] getModuleSource($name) → $n (null)');
      return null;
    }
    debugPrint('[QjsDrpy2/loader] getModuleSource($name) → $n '
        '(${src.length} chars)');
    return src;
  }

  @override
  String normalizeName(String base, String name) => _basename(name);
}

class QjsDrpy2Service implements ISpiderService {
  Isolate? _worker;
  SendPort? _commandPort;
  final _responsePort = ReceivePort();
  final _readyCompleter = Completer<void>();
  final Map<int, Completer<dynamic>> _pending = {};
  int _nextId = 0;

  HttpServer? _syncProxyServer;
  int _syncProxyPort = 0;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    validateStatus: (_) => true,
    responseType: ResponseType.bytes,
  ));

  bool _ready = false;
  bool _initializing = false;
  final isReady = false.obs;

  String? _currentKey;
  String? _pendingApiUrl;
  String? _pendingSiteKey;
  dynamic _pendingExt;

  static const _assetPublicDir = 'assets/js/lib/';
  static const _assetDir = 'assets/js/lib/drpy2/';
  static const _coreFileName = 'drpy-core-lite.min.js';
  static const _drpy2FileName = 'drpy2.min.js';
  static const _cheerioFileName = 'cheerio.min.js';

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

    if (!QjsPlatformHelper.isSupported) {
      debugPrint('[QjsDrpy2] 当前平台不支持 qjs_ultra');
      return false;
    }

    try {
      await _startSyncProxyServer();

      final drpyCore = await rootBundle.loadString('$_assetDir$_coreFileName');
      final drpy2Js = await rootBundle.loadString('$_assetDir$_drpy2FileName');
      final cheerioJs = await rootBundle.loadString('$_assetPublicDir$_cheerioFileName');
      debugPrint('[QjsDrpy2] 文件加载: '
          '$_coreFileName=${drpyCore.length}, '
          '$_drpy2FileName=${drpy2Js.length}, '
          '$_cheerioFileName=${cheerioJs.length}');

      _responsePort.listen(_onWorkerMessage);
      _worker = await Isolate.spawn(_workerMain, {
        'port': _responsePort.sendPort,
        'proxyPort': _syncProxyPort,
        'libPath': QjsPlatformHelper.libPath,
        'drpyCore': drpyCore,
        'drpy2Js': drpy2Js,
        'cheerioJs': cheerioJs,
      });

      await _readyCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('worker 就绪超时'),
      );

      if (_pendingApiUrl != null && _pendingSiteKey != null) {
        final url = _pendingApiUrl!;
        final key = _pendingSiteKey!;
        final ext = _pendingExt;
        _pendingApiUrl = null;
        _pendingSiteKey = null;
        _pendingExt = null;
        switchSite(url, key, ext: ext);
      }

      _ready = true;
      isReady.value = true;
      debugPrint('[QjsDrpy2] 初始化完成');
      return true;
    } catch (e, st) {
      debugPrint('[QjsDrpy2] 初始化失败: $e\n$st');
      return false;
    }
  }

  Future<void> _startSyncProxyServer() async {
    _syncProxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _syncProxyPort = _syncProxyServer!.port;
    _syncProxyServer!.listen(_handleSyncFetch);
    debugPrint('[QjsDrpy2] 同步代理服务器已启动: 127.0.0.1:$_syncProxyPort');
  }

  Future<void> _handleSyncFetch(HttpRequest req) async {
    if (req.method != 'POST' || req.uri.path != '/sync-fetch') {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }

    Map<String, dynamic> respJson;
    try {
      final bodyStr = await utf8.decoder.bind(req).join();
      final params = jsonDecode(bodyStr) as Map<String, dynamic>;

      final url = params['url'] as String;
      final method = (params['method'] as String? ?? 'GET').toUpperCase();
      final rawHeaders = (params['headers'] as Map?) ?? {};
      final headers = <String, String>{};
      rawHeaders.forEach((k, v) {
        if (v == null) return;
        final ks = k.toString();
        final lk = ks.toLowerCase();
        if (lk == 'host' || lk == 'connection' || lk == 'content-length') return;
        headers[ks] = v is List ? v.join(', ') : v.toString();
      });
      if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
        headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 11; Pixel 5) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36';
      }

      dynamic reqBody = params['body'];
      if (params['data'] != null && reqBody == null) {
        reqBody = jsonEncode(params['data']);
        headers.putIfAbsent('Content-Type', () => 'application/json');
      }

      final bufferType = params['buffer'];

      final dioResp = await _dio.request(
        url,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (_) => true,
        ),
        data: reqBody,
      );

      final bytes = (dioResp.data as List).cast<int>();
      String content;
      if (bufferType == 1 || bufferType == 2) {
        content = base64Encode(bytes);
      } else {
        content = utf8.decode(bytes, allowMalformed: true);
      }

      final respHeaders = <String, String>{};
      dioResp.headers.forEach((k, v) {
        if (v.isNotEmpty) respHeaders[k] = v.first;
      });

      respJson = {
        'status': dioResp.statusCode ?? 200,
        'headers': respHeaders,
        'content': content,
        'buffer': bufferType,
      };
    } catch (e) {
      debugPrint('[QjsDrpy2] sync-fetch 失败: $e');
      respJson = {
        'status': 500,
        'headers': <String, String>{'error': e.toString()},
        'content': '',
      };
    }

    final respBytes = utf8.encode(jsonEncode(respJson));
    req.response
      ..statusCode = 200
      ..headers.contentType =
          ContentType('application', 'json', charset: 'utf-8')
      ..headers.set('Content-Length', respBytes.length.toString())
      ..headers.set('Connection', 'close');
    req.response.add(respBytes);
    await req.response.close();
  }

  void _onWorkerMessage(dynamic msg) {
    if (msg is SendPort) {
      _commandPort = msg;
      return;
    }
    if (msg is Map && msg['ready'] == true) {
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
      return;
    }
    if (msg is Map && msg['ready'] == false) {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.completeError(msg['error'] ?? 'worker 启动失败');
      }
      return;
    }
    if (msg is Map && msg['id'] != null) {
      final id = msg['id'] as int;
      final c = _pending.remove(id);
      if (c == null || c.isCompleted) return;
      if (msg['ok'] == true) {
        c.complete(msg['result']);
      } else {
        c.completeError(msg['error'] ?? 'unknown');
      }
    }
  }

  Future<dynamic> _send(String cmd, [List? args]) async {
    if (_commandPort == null) throw Exception('worker 未就绪');
    final id = ++_nextId;
    final c = Completer<dynamic>();
    _pending[id] = c;
    _commandPort!.send({'id': id, 'cmd': cmd, 'args': args ?? []});
    return c.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        _pending.remove(id);
        throw Exception('worker 调用超时: $cmd');
      },
    );
  }

  // ============================================================
  // worker isolate
  // ============================================================
  static Future<void> _workerMain(Map<String, dynamic> init) async {
    final mainPort = init['port'] as SendPort;
    final proxyPort = init['proxyPort'] as int;
    final libPath = init['libPath'] as String;
    final drpyCore = init['drpyCore'] as String;
    final drpy2Js = init['drpy2Js'] as String;
    final cheerioJs = init['cheerioJs'] as String;

    final commandPort = ReceivePort();
    mainPort.send(commandPort.sendPort);

    try {
      final engine = QuickjsEngine.createWith(
        const JsEngineConfig(
          stackSize: 1 * 1024 * 1024,
          memoryLimit: 64 * 1024 * 1024,
          timeoutMs: 10 * 1000,
        ),
        libPath: libPath,
      );

      // ===== 1. console + 浏览器垫片 =====
      _injectConsole(engine);
      engine.evaluate(_browserShim);

      // ===== 2. 直接执行 cheerio.min.js（已手动改过，无 export 语法）=====
      debugPrint('[QjsDrpy2/worker] 加载 cheerio.min.js '
          '(${cheerioJs.length} chars)');
      try {
        engine.evaluate(cheerioJs);
        final check = await engine.evaluateAsync(r'''
          JSON.stringify({
            exists: typeof globalThis.__full_cheerio__ !== 'undefined',
            hasLoad: !!(globalThis.__full_cheerio__
                        && typeof globalThis.__full_cheerio__.load === 'function'),
            hasJp: !!(globalThis.__full_cheerio__
                      && typeof globalThis.__full_cheerio__.jp === 'function'),
            hasJinja2: !!(globalThis.__full_cheerio__
                          && typeof globalThis.__full_cheerio__.jinja2 === 'function'),
          })
        ''');
        debugPrint('[QjsDrpy2/worker] cheerio 加载结果: $check');
        if (check is String) {
          final p = jsonDecode(check) as Map<String, dynamic>;
          if (p['hasLoad'] != true) {
            throw Exception('cheerio.load 不可用: $check');
          }
        }
      } catch (e, st) {
        debugPrint('[QjsDrpy2/worker] ❌ cheerio 加载失败: $e\n$st');
        rethrow;
      }

      // ===== 3. 注入宿主函数 =====
      _registerHostFunctions(engine, proxyPort);

      engine.evaluate(r'''
        var __qjs_local_store__ = {};
        globalThis.local = {
          get: function(key, k, v) {
            var kk = String(key) + '|' + String(k);
            return __qjs_local_store__.hasOwnProperty(kk)
              ? __qjs_local_store__[kk] : (v === undefined ? null : v);
          },
          set: function(key, k, v) {
            __qjs_local_store__[String(key) + '|' + String(k)] = String(v);
          },
          delete: function(key, k) {
            delete __qjs_local_store__[String(key) + '|' + String(k)];
          }
        };
      ''');

      // ===== 4. 用 __full_cheerio__ 实现 pdfh/pdfa/pd/pdfl =====
      engine.evaluate(_htmlParserJs);
      final parseCheck = await engine.evaluateAsync(r'''
        JSON.stringify({
          hasPdfh: typeof globalThis.pdfh === 'function',
          hasPdfa: typeof globalThis.pdfa === 'function',
          hasPd: typeof globalThis.pd === 'function',
          hasPdfl: typeof globalThis.pdfl === 'function',
        })
      ''');
      debugPrint('[QjsDrpy2/worker] pdfh 注入结果: $parseCheck');

      // ===== 5. 设置模块加载器 =====
      final loader = _Drpy2ModuleLoader({
        'drpy-core-lite.min.js': drpyCore,
        'drpy2.min.js': drpy2Js,
      });
      engine.setModuleLoader(loader);

      // ===== 6. import drpy2.min.js =====
      final loadResult = await engine.evaluateAsync(r'''
        (async () => {
          try {
            const mod = await import('./drpy2.min.js');
            const exp = (mod && mod.default) || mod;

            if (!globalThis.window) globalThis.window = globalThis;
            globalThis.__drpy2 = exp;
            globalThis.window.__drpy2 = exp;

            for (const k in exp) {
              if (typeof exp[k] === 'function') globalThis[k] = exp[k];
            }

            return JSON.stringify({
              ok: true,
              hasInit: typeof exp.init === 'function',
              hasHome: typeof exp.home === 'function',
              hasCategory: typeof exp.category === 'function',
              hasDetail: typeof exp.detail === 'function',
              hasPlay: typeof exp.play === 'function',
              hasSearch: typeof exp.search === 'function',
            });
          } catch (e) {
            return JSON.stringify({
              ok: false,
              error: String(e && e.message || e),
              stack: String(e && e.stack || ''),
            });
          }
        })()
      ''');
      debugPrint('[QjsDrpy2/worker] drpy2 模块加载: $loadResult');

      if (loadResult is String) {
        final parsed = jsonDecode(loadResult) as Map<String, dynamic>;
        if (parsed['ok'] != true) {
          throw Exception('drpy2 模块加载失败: $loadResult');
        }
      }

      mainPort.send({'ready': true});

      // ===== 7. 命令循环 =====
      await for (final msg in commandPort) {
        if (msg is! Map) continue;
        final id = msg['id'] as int?;
        final cmd = msg['cmd'] as String?;
        final args = msg['args'] as List? ?? [];
        if (id == null || cmd == null) continue;

        try {
          switch (cmd) {
            case 'switchSite':
              final apiUrl = args[0] as String? ?? '';
              final siteKey = args[1] as String? ?? '';
              final ext = args.length > 2 ? args[2] : null;
              await _switchSite(engine, proxyPort, apiUrl, siteKey, ext);
              mainPort.send({'id': id, 'ok': true, 'result': true});
              break;

            case 'call':
              final fn = args[0] as String;
              final callArgs = args[1] as List? ?? [];
              final result = await _callEngine(engine, fn, callArgs);
              mainPort.send({'id': id, 'ok': true, 'result': result});
              break;

            case 'dispose':
              engine.dispose();
              mainPort.send({'id': id, 'ok': true, 'result': true});
              return;
          }
        } catch (e, st) {
          mainPort.send({
            'id': id,
            'ok': false,
            'error': e.toString(),
            'stack': st.toString(),
          });
        }
      }
    } catch (e, st) {
      mainPort.send({
        'ready': false,
        'error': e.toString(),
        'stack': st.toString(),
      });
    }
  }

  static void _injectConsole(QuickjsEngine engine) {
    engine.evaluate(r'''
      (function() {
        var nativeLog = (typeof console !== 'undefined'
                         && typeof console.log === 'function') ? console.log : null;
        if (typeof globalThis.console === 'undefined') globalThis.console = {};

        var safeLog = function() {
          try {
            var args = Array.prototype.slice.call(arguments);
            var msg = args.map(String).join(' ');
            if (nativeLog) {
              try { nativeLog.call(console, msg); return; } catch (_) {}
            }
            if (typeof globalThis.print === 'function') {
              try { globalThis.print(msg); return; } catch (_) {}
            }
          } catch (_) {}
        };

        console.log = safeLog;
        console.error = safeLog;
        console.warn = safeLog;
        console.info = safeLog;
        console.debug = safeLog;
        console.stdout = { write: function(s) { safeLog(String(s)); } };
        console.stderr = { write: function(s) { safeLog(String(s)); } };
      })();
    ''');
  }

  static const _browserShim = r'''
    if (typeof globalThis.window === 'undefined') globalThis.window = globalThis;
    if (typeof globalThis.self === 'undefined') globalThis.self = globalThis;
    if (typeof globalThis.navigator === 'undefined') {
      globalThis.navigator = {
        userAgent: 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36',
        platform: 'drpy', language: 'zh-CN',
      };
    }
    if (typeof globalThis.location === 'undefined') {
      globalThis.location = {
        href: 'file:///drpy2/', protocol: 'file:',
        host: 'localhost', hostname: 'localhost',
        origin: 'file://', pathname: '/', search: '', hash: '',
      };
    }
    if (typeof globalThis.document === 'undefined') {
      globalThis.document = {
        createElement: function() {
          return { style: {}, setAttribute: function(){},
                   appendChild: function(){}, innerHTML: '' };
        },
        currentScript: { src: '' },
        addEventListener: function(){}, removeEventListener: function(){},
        getElementsByTagName: function() { return []; },
        querySelector: function() { return null; },
        querySelectorAll: function() { return []; },
        body: { appendChild: function(){}, removeChild: function(){} },
        head: { appendChild: function(){}, removeChild: function(){} },
      };
    }
    if (typeof globalThis.XMLHttpRequest === 'undefined') {
      globalThis.XMLHttpRequest = function() {
        this.open = function(){}; this.send = function(){};
        this.setRequestHeader = function(){}; this.addEventListener = function(){};
        this.readyState = 0; this.status = 0; this.responseText = '';
      };
    }
    if (typeof globalThis.setImmediate === 'undefined') {
      globalThis.setImmediate = function(fn) { return setTimeout(fn, 0); };
    }
    if (typeof globalThis.Buffer === 'undefined') {
      globalThis.Buffer = {
        from: function(data) {
          if (typeof data === 'string') return new TextEncoder().encode(data);
          return data;
        },
        isBuffer: function() { return false; },
        concat: function(arr) {
          var total = 0;
          for (var i = 0; i < arr.length; i++) total += arr[i].length;
          var out = new Uint8Array(total), off = 0;
          for (var i = 0; i < arr.length; i++) { out.set(arr[i], off); off += arr[i].length; }
          return out;
        },
      };
    }
    if (typeof globalThis.process === 'undefined') {
      globalThis.process = { env: {}, platform: 'drpy', version: 'v18.0.0' };
    }
  ''';

  static void _registerHostFunctions(QuickjsEngine engine, int proxyPort) {
    engine.registerFunction('req', (args) {
      try {
        final url = args[0] as String;
        final opts = (args.length > 1 && args[1] is Map)
            ? (args[1] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        return _syncFetch(proxyPort, url, opts);
      } catch (e) {
        return {
          'content': '',
          'headers': <String, String>{'error': e.toString()},
        };
      }
    });

    engine.registerFunction('joinUrl', (args) {
      try {
        final base = args.isNotEmpty ? (args[0]?.toString() ?? '') : '';
        final rel = args.length > 1 ? (args[1]?.toString() ?? '') : '';
        if (rel.isEmpty) return '';
        if (base.isEmpty) return rel;
        try {
          return Uri.parse(base).resolve(rel).toString();
        } catch (_) {
          return rel;
        }
      } catch (_) {
        return '';
      }
    });

    engine.registerFunction('batchFetch', (args) {
      try {
        final items = (args.isNotEmpty && args[0] is List)
            ? (args[0] as List)
            : <dynamic>[];
        final out = <String>[];
        for (final item in items) {
          try {
            if (item is! Map) { out.add(''); continue; }
            final url = item['url']?.toString() ?? '';
            final opts = (item['options'] is Map)
                ? (item['options'] as Map).cast<String, dynamic>()
                : <String, dynamic>{};
            final r = _syncFetch(proxyPort, url, opts);
            out.add((r['content'] as String?) ?? '');
          } catch (_) {
            out.add('');
          }
        }
        return out;
      } catch (_) {
        return <String>[];
      }
    });
  }

  static Map<String, dynamic> _syncFetch(
    int proxyPort,
    String url,
    Map<String, dynamic> opts,
  ) {
    RawSynchronousSocket? socket;
    try {
      socket = RawSynchronousSocket.connectSync('127.0.0.1', proxyPort);

      final payload = jsonEncode({
        'url': url,
        'method': opts['method'] ?? 'GET',
        'headers': opts['headers'] ?? {},
        'body': opts['body'],
        'data': opts['data'],
        'buffer': opts['buffer'],
      });
      final payloadBytes = utf8.encode(payload);
      final head = 'POST /sync-fetch HTTP/1.1\r\n'
          'Host: 127.0.0.1\r\n'
          'Content-Type: application/json; charset=utf-8\r\n'
          'Content-Length: ${payloadBytes.length}\r\n'
          'Connection: close\r\n'
          '\r\n';
      final headBytes = utf8.encode(head);

      socket.writeFromSync(headBytes);
      socket.writeFromSync(payloadBytes);

      final buf = <int>[];
      final chunk = List<int>.filled(16384, 0);
      while (true) {
        int n;
        try {
          n = socket.readIntoSync(chunk);
        } catch (_) {
          break;
        }
        if (n <= 0) break;
        for (var i = 0; i < n; i++) {
          buf.add(chunk[i]);
        }
      }

      final respText = utf8.decode(buf, allowMalformed: true);
      final sep = respText.indexOf('\r\n\r\n');
      if (sep < 0) {
        return {
          'content': '',
          'headers': <String, String>{'error': 'invalid response'},
        };
      }
      final bodyText = respText.substring(sep + 4);
      final respJson = jsonDecode(bodyText) as Map<String, dynamic>;

      final result = <String, dynamic>{
        'content': respJson['content'] ?? '',
        'headers':
            (respJson['headers'] as Map?)?.cast<String, dynamic>() ?? {},
      };
      if (respJson['buffer'] != null) result['buffer'] = respJson['buffer'];
      return result;
    } finally {
      try {
        socket?.closeSync();
      } catch (_) {}
    }
  }

  static Future<void> _switchSite(
    QuickjsEngine engine,
    int proxyPort,
    String apiUrl,
    String siteKey,
    dynamic ext,
  ) async {
    String ruleContent = '';
    if (ext is String && ext.isNotEmpty) {
      if (ext.startsWith('http://') || ext.startsWith('https://')) {
        final r = _syncFetch(proxyPort, ext, {});
        ruleContent = (r['content'] as String?) ?? '';
      } else if (ext.contains('var rule') || ext.contains('{')) {
        ruleContent = ext;
      } else {
        final r = _syncFetch(proxyPort, ext, {});
        ruleContent = (r['content'] as String?) ?? '';
      }
    } else if (apiUrl.isNotEmpty) {
      final r = _syncFetch(proxyPort, apiUrl, {});
      ruleContent = (r['content'] as String?) ?? '';
    }

    if (ruleContent.isEmpty) {
      throw Exception('drpy2 源为空: apiUrl=$apiUrl, ext=$ext');
    }

    final codeJson = jsonEncode(ruleContent);
    final keyJson = jsonEncode(siteKey);

    final r = await engine.evaluateAsync("""
      (async () => {
        try {
          const drpy2 = globalThis.window && globalThis.window.__drpy2;
          if (!drpy2 || typeof drpy2.init !== 'function') {
            return JSON.stringify({ ok: false, error: 'window.__drpy2.init 不存在' });
          }
          try { globalThis.key = $keyJson; } catch(e) {}
          const sourceCode = $codeJson;
          await drpy2.init(sourceCode);
          return JSON.stringify({ ok: true });
        } catch(e) {
          return JSON.stringify({
            ok: false,
            error: String(e && e.message || e),
            stack: String(e && e.stack || ''),
          });
        }
      })()
    """);
    debugPrint('[QjsDrpy2/worker] init 结果: $r');

    if (r is String) {
      final parsed = jsonDecode(r) as Map<String, dynamic>;
      if (parsed['ok'] != true) {
        throw Exception('drpy2 init 失败: $r');
      }
    }
    debugPrint('[QjsDrpy2/worker] 源已加载: $siteKey (${ruleContent.length} chars)');
  }

  static Future<dynamic> _callEngine(
    QuickjsEngine engine,
    String fn,
    List args,
  ) async {
    final argStr = args.map(_toJsLiteral).join(',');
    final source = 'window.__drpy2.$fn($argStr)';

    final result = await engine.evaluateAsync(source);
    if (result is String) {
      try {
        return jsonDecode(result);
      } catch (_) {
        return result;
      }
    }
    return result;
  }

  static String _toJsLiteral(dynamic v) {
    if (v == null) return 'null';
    if (v is String) {
      final escaped = v
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "\\'")
          .replaceAll('\n', '\\n')
          .replaceAll('\r', '\\r');
      return "'$escaped'";
    }
    if (v is num || v is bool) return v.toString();
    if (v is List) return '[${v.map(_toJsLiteral).join(',')}]';
    if (v is Map) {
      final entries = v.entries
          .map((e) =>
              '${_toJsLiteral(e.key.toString())}:${_toJsLiteral(e.value)}')
          .join(',');
      return '{$entries}';
    }
    return jsonEncode(v);
  }

  // ============================================================
  // pdfh/pdfa/pd/pdfl —— 用 __full_cheerio__
  // ============================================================
  static const _htmlParserJs = r'''
(function() {
  var cheerio = globalThis.__full_cheerio__;
  if (!cheerio || typeof cheerio.load !== 'function') {
    if (typeof globalThis.print === 'function') {
      globalThis.print('[QjsDrpy2] ❌ __full_cheerio__ 不可用');
    }
    return;
  }

  var NOADD_INDEX = ':eq|:lt|:gt|:first|:last|:not|:even|:odd|:has|:contains|:matches|:empty|^body$|^#';
  var URLJOIN_ATTR = '(url|src|href|-original|-src|-play|-url|style)$|^(data-|url-|src-)';
  var SPECIAL_URL = '^(ftp|magnet|thunder|ws):';

  function test(text, string) {
    try { return new RegExp(text, 'mi').test(string); } catch (e) { return false; }
  }
  function contains(text, match) { return String(text).indexOf(match) !== -1; }

  function urljoin(from, to) {
    try {
      var resolvedUrl = new URL(to, new URL(from, 'resolve://'));
      if (resolvedUrl.protocol === 'resolve:') {
        return resolvedUrl.pathname + resolvedUrl.search + resolvedUrl.hash;
      }
      return resolvedUrl.href;
    } catch (e) { return (from || '') + (to || ''); }
  }

  function parseHikerToJq(parse, first) {
    if (contains(parse, '&&')) {
      var parses = parse.split('&&');
      var new_parses = [];
      for (var i = 0; i < parses.length; i++) {
        var ps_list = parses[i].split(' ');
        var ps = ps_list[ps_list.length - 1];
        if (!test(NOADD_INDEX, ps)) {
          if (!first && i >= parses.length - 1) {
            new_parses.push(parses[i]);
          } else {
            new_parses.push(parses[i] + ':eq(0)');
          }
        } else {
          new_parses.push(parses[i]);
        }
      }
      parse = new_parses.join(' ');
    } else {
      var ps_list2 = parse.split(' ');
      var ps2 = ps_list2[ps_list2.length - 1];
      if (!test(NOADD_INDEX, ps2) && first) parse = parse + ':eq(0)';
    }
    return parse;
  }

  function getParseInfo(nparse) {
    var excludes = [];
    var nparse_index = 0;
    var nparse_rule = nparse;

    if (contains(nparse, ':eq')) {
      nparse_rule = nparse.split(':eq')[0];
      var nparse_pos = nparse.split(':eq')[1];
      if (contains(nparse_rule, '--')) {
        excludes = nparse_rule.split('--').slice(1);
        nparse_rule = nparse_rule.split('--')[0];
      } else if (contains(nparse_pos, '--')) {
        excludes = nparse_pos.split('--').slice(1);
        nparse_pos = nparse_pos.split('--')[0];
      }
      try {
        nparse_index = parseInt(nparse_pos.split('(')[1].split(')')[0], 10);
      } catch (e) {}
    } else if (contains(nparse, '--')) {
      nparse_rule = nparse.split('--')[0];
      excludes = nparse.split('--').slice(1);
    }

    return { nparse_rule: nparse_rule, nparse_index: nparse_index, excludes: excludes };
  }

  function reorderAdjacentLtAndGt(selector) {
    var adjacentPattern = /:gt\((\d+)\):lt\((\d+)\)/;
    var match;
    while ((match = adjacentPattern.exec(selector)) !== null) {
      var replacement = ':lt(' + match[2] + '):gt(' + match[1] + ')';
      selector = selector.substring(0, match.index) + replacement
               + selector.substring(match.index + match[0].length);
      adjacentPattern.lastIndex = match.index;
    }
    return selector;
  }

  function parseOneRule(doc, nparse, ret) {
    var info = getParseInfo(nparse);
    var nparse_rule = reorderAdjacentLtAndGt(info.nparse_rule);
    if (!ret) ret = doc(nparse_rule);
    else ret = ret.find(nparse_rule);

    if (contains(nparse, ':eq')) ret = ret.eq(info.nparse_index);

    if (info.excludes.length > 0 && ret) {
      try {
        ret = ret.clone();
        for (var i = 0; i < info.excludes.length; i++) {
          ret.find(info.excludes[i]).remove();
        }
      } catch (e) {}
    }

    return ret;
  }

  function parseText(text) {
    if (text == null) return '';
    text = String(text).replace(/[\s]+/gm, '\n');
    text = text.replace(/\n+/g, '\n').replace(/^\s+/, '');
    text = text.replace(/\n/g, ' ');
    return text;
  }

  globalThis.pdfa = function(html, parse) {
    if (!html || !parse) return [];
    parse = parseHikerToJq(parse, false);
    var doc = cheerio.load(html);
    var parses = parse.split(' ');
    var ret = null;
    for (var i = 0; i < parses.length; i++) {
      ret = parseOneRule(doc, parses[i], ret);
      if (!ret) return [];
    }
    var arr = [];
    try { arr = (ret && ret.toArray) ? ret.toArray() : []; } catch (e) { arr = []; }
    var res = [];
    for (var j = 0; j < arr.length; j++) {
      try { var h = doc.html(arr[j]); if (h) res.push(h); } catch (e) {}
    }
    return res;
  };

  globalThis.pdfh = function(html, parse, baseUrl) {
    if (!html || !parse) return '';
    var doc = cheerio.load(html);
    if (parse === 'body&&Text' || parse === 'Text') return parseText(doc.text());
    if (parse === 'body&&Html' || parse === 'Html') return doc.html();

    var option;
    if (contains(parse, '&&')) {
      var parts = parse.split('&&');
      option = parts.pop();
      parse = parts.join('&&');
    }

    parse = parseHikerToJq(parse, true);
    var parses = parse.split(' ');
    var ret = null;
    for (var i = 0; i < parses.length; i++) {
      ret = parseOneRule(doc, parses[i], ret);
      if (!ret) return '';
    }

    if (option) {
      if (option === 'Text') {
        ret = ret ? parseText(ret.text()) : '';
      } else if (option === 'Html') {
        ret = ret ? ret.html() : '';
      } else {
        var originalRet = ret.clone();
        var options = option.split('||');
        for (var k = 0; k < options.length; k++) {
          var opt = options[k];
          ret = originalRet ? (originalRet.attr(opt) || '') : '';
          if (contains(opt.toLowerCase(), 'style') && contains(ret, 'url(')) {
            try {
              ret = ret.match(/url\((.*?)\)/)[1];
              ret = ret.replace(/^['"]|['"]$/g, '');
            } catch (e) {}
          }
          if (ret && baseUrl) {
            var needAdd = test(URLJOIN_ATTR, opt) && !test(SPECIAL_URL, ret);
            if (needAdd) {
              ret = ret.indexOf('http') >= 0
                ? ret.slice(ret.indexOf('http'))
                : urljoin(baseUrl, ret);
            }
          }
          if (ret) break;
        }
      }
    } else { ret = String(ret); }
    return ret;
  };

  globalThis.pd = function(html, parse, baseUrl) {
    return globalThis.pdfh(html, parse, baseUrl || '');
  };

  globalThis.pdfl = function(html, parse, listText, listUrl, myUrl) {
    if (!html || !parse) return [];
    parse = parseHikerToJq(parse, false);
    var doc = cheerio.load(html);
    var parses = parse.split(' ');
    var ret = null;
    for (var i = 0; i < parses.length; i++) {
      ret = parseOneRule(doc, parses[i], ret);
      if (!ret) return [];
    }
    var new_list = [];
    try {
      ret.each(function(_, element) {
        try {
          var h = doc.html(element);
          var title = globalThis.pdfh(h, listText);
          var url = globalThis.pd(h, listUrl, myUrl);
          new_list.push(title + '$' + url);
        } catch (e) {}
      });
    } catch (e) {}
    return new_list;
  };

  if (typeof globalThis.jsp === 'undefined') {
    globalThis.jsp = { pdfh: globalThis.pdfh, pdfa: globalThis.pdfa, pd: globalThis.pd };
  }
  if (typeof globalThis.print === 'function') {
    globalThis.print('[QjsDrpy2] pdfh/pdfa/pd/pdfl 已注入（__full_cheerio__）');
  }
})();
''';

  // ============================================================
  // ISpiderService
  // ============================================================
  @override
  void setBaseUrl(String url) {}

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    _currentKey = siteKey;
    if (!_ready) {
      _pendingApiUrl = apiUrl;
      _pendingSiteKey = siteKey;
      _pendingExt = ext;
      unawaited(ensureInitialized());
      return;
    }
    unawaited(_send('switchSite', [apiUrl, siteKey, ext]));
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    final r = await _send('call', ['home', [filter]]);
    return r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> fetchCate(String cateId, int page,
      {String? ext}) async {
    final r = await _send('call', ['category', [cateId, page, false, {}]]);
    return r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> search(String wd, int page,
      {int quick = 0}) async {
    final r = await _send('call', ['search', [wd, quick == 1, page]]);
    return r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
  }

  @override
  Future<VideoDetail?> getDetail(
      {required String vodId, required String pwd}) async {
    final r = await _send('call', ['detail', [vodId]]);
    if (r is! Map) return null;
    final list = r['list'];
    if (list is! List || list.isEmpty) return null;
    return VideoDetail.fromJson((list[0] as Map).cast<String, dynamic>());
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    final r = await _send('call', ['play', [flag, playParams, []]]);
    if (r is Map) return PlayUrl.fromJson(r.cast<String, dynamic>());
    return null;
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    final r = await _send('call', ['detail', [ids]]);
    return r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play,
      {String? flag}) async {
    final r = await _send('call', ['play', [flag ?? '', play, []]]);
    return r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) =>
      search(wd, page, quick: quick);

  void dispose() {
    try {
      _commandPort?.send({'id': -1, 'cmd': 'dispose', 'args': []});
    } catch (_) {}
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _commandPort = null;
    _syncProxyServer?.close(force: true);
    _syncProxyServer = null;
    _ready = false;
    isReady.value = false;
  }
}