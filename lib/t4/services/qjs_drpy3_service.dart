import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip, HttpServer;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:qjs_ultra/qjs_ultra.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/services/debug_log_service.dart';
import 'package:yuanying/utils/qjs_platform_helper.dart';

class _Drpy3ModuleLoader implements JsModuleLoader {
  final Map<String, String> _sources;
  _Drpy3ModuleLoader(this._sources);

  String _normalize(String name) {
    var n = name;
    if (n.startsWith('./')) n = n.substring(2);
    while (n.startsWith('../')) n = n.substring(3);
    final q = n.indexOf('?');
    if (q >= 0) n = n.substring(0, q);
    return n;
  }

  @override
  Uint8List? getModuleBytecode(String name) => null;

  @override
  String? getModuleSource(String name) => _sources[_normalize(name)];

  @override
  String normalizeName(String base, String name) => _normalize(name);
}

class QjsDrpy3Service implements ISpiderService {
  QuickjsEngine? _engine;
  _Drpy3ModuleLoader? _moduleLoader;

  bool _ready = false;
  bool _initializing = false;
  final isReady = false.obs;

  String? _currentKey;
  String? _pendingExt;
  String? _pendingApiUrl;
  String? _pendingSiteKey;
  String? _currentSourceBase;

  int _siteVersion = 0;
  Completer<void>? _siteReady;

  HttpServer? _proxyServer;
  int _proxyPort = 0;

  final Map<String, Uint8List> _assetCache = {};

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    validateStatus: (_) => true,
    responseType: ResponseType.bytes,
  ));

  static const _assetPublicDir = 'assets/js/lib/';
  static const _assetDir = 'assets/js/lib/drpy3/';
  static const _officialFiles = <String>[
    'drpy3-globals-capture.js',
    'drpy-core-lite.min.js',
    // 'drpy-core-qjs.min.js',
    'drpy3-peer.js',
    'drpy3.esm.min.js',
  ];
  static const _entryModule = 'drpy3.esm.min.js';
  // cheerio.min.js 放在 drpy3 子目录
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
      debugPrint('[QjsDrpy3] 当前平台不支持 qjs_ultra');
      return false;
    }

    try {
      _engine = QuickjsEngine.createWith(
        const JsEngineConfig(
          stackSize: 1 * 1024 * 1024,
          memoryLimit: 64 * 1024 * 1024,
          timeoutMs: 10 * 1000,
        ),
        libPath: QjsPlatformHelper.libPath,
      );
      debugPrint('[QjsDrpy3] 引擎创建成功');

      _engine!.installTimers();
      _injectConsole();
      _injectBrowserShim();

      // ===== 加载 cheerio.min.js（手动改过 export 的普通脚本）=====
      await _loadCheerio();

      await _injectBase64Helper();
      await _startProxyServer();
      _registerHostFunctions();

      // ===== 加载官方 4 个 ESM 模块 =====
      await _loadOfficialModules();

      // ===== 用 __full_cheerio__ 实现 pdfh/pdfa/pd/pdfl =====
      await _injectHtmlParser();

      await _injectHostEnv();
      await _createRuntime();

      if (_pendingApiUrl != null && _pendingSiteKey != null) {
        final url = _pendingApiUrl!;
        final key = _pendingSiteKey!;
        final ext = _pendingExt;
        _pendingApiUrl = null;
        _pendingSiteKey = null;
        _pendingExt = null;
        await _loadSource(_siteVersion, url, key, ext: ext);
      }

      _ready = true;
      isReady.value = true;
      debugPrint('[QjsDrpy3] 初始化完成');
      return true;
    } catch (e, st) {
      debugPrint('[QjsDrpy3] 初始化失败: $e\n$st');
      return false;
    }
  }

  // ============================================================
  // 浏览器/Node 垫片（cheerio 可能用到）
  // ============================================================
  void _injectBrowserShim() {
    _engine!.evaluate(r'''
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
          href: 'file:///drpy3/', protocol: 'file:',
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
            for (var i = 0; i < arr.length; i++) {
              out.set(arr[i], off); off += arr[i].length;
            }
            return out;
          },
        };
      }
      if (typeof globalThis.process === 'undefined') {
        globalThis.process = { env: {}, platform: 'drpy', version: 'v18.0.0' };
      }
    ''');
  }

  // ============================================================
  // 加载 cheerio.min.js（手动改过，末尾无 export）
  // ============================================================
  Future<void> _loadCheerio() async {
    try {
      final cheerioJs = await rootBundle.loadString('$_assetPublicDir$_cheerioFileName');
      debugPrint('[QjsDrpy3] 加载 cheerio.min.js (${cheerioJs.length} chars)');
      _engine!.evaluate(cheerioJs);

      final check = await _engine!.evaluateAsync(r'''
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
      debugPrint('[QjsDrpy3] cheerio 加载结果: $check');
      if (check is String) {
        final p = jsonDecode(check) as Map<String, dynamic>;
        if (p['hasLoad'] != true) {
          throw Exception('cheerio.load 不可用: $check');
        }
      }
    } catch (e, st) {
      debugPrint('[QjsDrpy3] ❌ cheerio.min.js 加载失败: $e\n$st');
      rethrow;
    }
  }

  // ============================================================
  // 加载官方 dist 4 个 ESM 模块
  // ============================================================
  Future<void> _loadOfficialModules() async {
    final sources = <String, String>{};
    for (final name in _officialFiles) {
      sources[name] = await rootBundle.loadString('$_assetDir$name');
      debugPrint('[QjsDrpy3] 已读取 $name (${sources[name]!.length} chars)');
    }

    _moduleLoader = _Drpy3ModuleLoader(sources);
    _engine!.setModuleLoader(_moduleLoader!);
    debugPrint('[QjsDrpy3] 模块加载器已设置');

    final r = await _engine!.evaluateAsync('''
      (async () => {
        const m = await import('$_entryModule');
        globalThis.DRPY3 = m;
        return JSON.stringify({
          hasRuntime: typeof m.Runtime === 'function',
          hasDefineSource: typeof m.defineSource === 'function',
          hasExpose: typeof m.exposeRuntimeGlobals === 'function',
          version: m.VERSION || '',
        });
      })()
    ''');
    debugPrint('[QjsDrpy3] 官方模块加载结果: $r');

    if (r is String) {
      final parsed = jsonDecode(r) as Map<String, dynamic>;
      if (parsed['hasRuntime'] != true) {
        throw Exception('DRPY3.Runtime 未就绪: $r');
      }
    }
  }

  // ============================================================
  // 用 __full_cheerio__ 实现 pdfh/pdfa/pd/pdfl
  // 完全照抄官方 htmlParser.js 的逻辑
  // ============================================================
  Future<void> _injectHtmlParser() async {
    final r = await _engine!.evaluateAsync(r'''
      (function() {
        var cheerio = globalThis.__full_cheerio__;
        if (!cheerio || typeof cheerio.load !== 'function') {
          return JSON.stringify({ ok: false, reason: 'no __full_cheerio__' });
        }

        var NOADD_INDEX = ':eq|:lt|:gt|:first|:last|:not|:even|:odd|:has|:contains|:matches|:empty|^body$|^#';
        var URLJOIN_ATTR = '(url|src|href|-original|-src|-play|-url|style)$|^(data-|url-|src-)';
        var SPECIAL_URL = '^(ftp|magnet|thunder|ws):';

        function test(text, string) {
          try { return new RegExp(text, 'mi').test(string); } catch (e) { return false; }
        }
        function contains(text, match) {
          return String(text).indexOf(match) !== -1;
        }
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
          if (parse === 'body&&Text' || parse === 'Text') {
            return parseText(doc.text());
          } else if (parse === 'body&&Html' || parse === 'Html') {
            return doc.html();
          }
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
          } else {
            ret = String(ret);
          }
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

        return JSON.stringify({
          ok: true,
          hasPdfh: typeof globalThis.pdfh === 'function',
          hasPdfa: typeof globalThis.pdfa === 'function',
          hasPd: typeof globalThis.pd === 'function',
          hasPdfl: typeof globalThis.pdfl === 'function',
        });
      })()
    ''');
    debugPrint('[QjsDrpy3] _injectHtmlParser: $r');
    if (r is String) {
      final parsed = jsonDecode(r) as Map<String, dynamic>;
      if (parsed['ok'] != true) {
        throw Exception('pdfh 注入失败: $r');
      }
    }
  }

  // ============================================================
  // console 注入
  // ============================================================
  void _injectConsole() {
    _engine!.evaluate(r'''
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
    debugPrint('[QjsDrpy3] console 已就绪（强制健壮版）');
  }

  // ============================================================
  // base64 助手
  // ============================================================
  Future<void> _injectBase64Helper() async {
    await _engine!.evaluateAsync(r'''
      globalThis.__to_base64 = function(data) {
        var u8 = null;
        if (data instanceof Uint8Array) u8 = data;
        else if (data instanceof ArrayBuffer) u8 = new Uint8Array(data);
        else if (data && data.buffer instanceof ArrayBuffer
                 && typeof data.byteLength === 'number')
          u8 = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
        else if (Array.isArray(data)) u8 = new Uint8Array(data);
        else return '';
        if (typeof Buffer !== 'undefined' && typeof Buffer.from === 'function') {
          try { return Buffer.from(u8.buffer, u8.byteOffset, u8.byteLength).toString('base64'); } catch (_) {}
        }
        var bin = '', len = u8.length, CH = 0x8000;
        for (var i = 0; i < len; i += CH) {
          var e = Math.min(i + CH, len);
          for (var j = i; j < e; j++) bin += String.fromCharCode(u8[j]);
        }
        return btoa(bin);
      };
      globalThis.__from_base64 = function(b64) {
        try {
          var bin = atob(b64), len = bin.length, u8 = new Uint8Array(len);
          for (var i = 0; i < len; i++) u8[i] = bin.charCodeAt(i);
          return u8;
        } catch (e1) {
          try {
            if (typeof Buffer !== 'undefined') {
              var buf = Buffer.from(b64, 'base64');
              return new Uint8Array(buf);
            }
          } catch (e2) {}
          throw new Error('base64 解码失败: ' + (e1 && e1.message || e1));
        }
      };
    ''');
  }

  // ============================================================
  // 宿主函数
  // ============================================================
  void _registerHostFunctions() {
    _engine!.registerAsyncFunction('req', (args) async {
      try {
        final url = args[0] as String;
        final opts = (args.length > 1 && args[1] is Map)
            ? (args[1] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        return await _doDioRequest(url, opts);
      } catch (e) {
        debugPrint('[QjsDrpy3] req 失败: $e');
        return {'status': 500, 'content': '', 'headers': <String, String>{}};
      }
    });

    _engine!.registerAsyncFunction('loadAsset', (args) async {
      final rawPath = args[0] as String;
      try {
        final bytes = await _loadAsset(rawPath);
        return base64Encode(bytes);
      } catch (e, st) {
        debugPrint('[QjsDrpy3] loadAsset 失败: $e\n$st');
        return '';
      }
    });
    debugPrint('[QjsDrpy3] 宿主函数已注册');
  }

  // ============================================================
  // 桥接器
  // ============================================================
  Future<void> _injectHostEnv() async {
    await _engine!.evaluateAsync(r'''
      globalThis.__host_req = async function(url, optionsJson) {
        var opts = {};
        if (typeof optionsJson === 'string' && optionsJson.length > 0) {
          try { opts = JSON.parse(optionsJson); } catch (_) {}
        } else if (optionsJson && typeof optionsJson === 'object') {
          opts = optionsJson;
        }
        var resp = await req(url, opts);
        if (resp && (resp.buffer === 1 || resp.buffer === 2)
            && typeof resp.content === 'string') {
          try {
            if (resp.buffer === 1) resp.content = globalThis.__from_base64(resp.content);
          } catch (e) { console.log('[__host_req] base64 解码失败:', e); }
        }
        return resp;
      };
      globalThis.__host_loadAsset = async function(path) {
        var b64 = await loadAsset(path);
        if (typeof b64 !== 'string' || b64.length === 0)
          throw new Error('loadAsset 空返回: ' + path);
        return globalThis.__from_base64(b64);
      };
    ''');
  }

  // ============================================================
  // 构造 Runtime
  // ============================================================
  Future<void> _createRuntime() async {
    final proxyUrl = 'http://127.0.0.1:$_proxyPort/proxy?do=js';
    await _engine!.evaluateAsync('''
      (async () => {
        if (typeof DRPY3 === 'undefined' || !DRPY3.Runtime)
          throw new Error('DRPY3.Runtime 未就绪');
        if (typeof globalThis.pdfh !== 'function')
          throw new Error('pdfh 未注入');
        globalThis.__rt = new DRPY3.Runtime({
          req:      globalThis.__host_req,
          pdfh:     globalThis.pdfh,
          pdfa:     globalThis.pdfa,
          pd:       globalThis.pd,
          pdfl:     globalThis.pdfl,
          loadAsset: globalThis.__host_loadAsset,
          log:      function() {
            try {
              var a = Array.prototype.slice.call(arguments).map(String);
              console.log('[drpy3]', a.join(' '));
            } catch (_) {}
          },
          getProxy: function(isPublic) { return ${jsonEncode(proxyUrl)}; },
          engine:  'qjs_ultra',
          version: '1.0.0',
        });
        if (typeof DRPY3.exposeRuntimeGlobals === 'function') {
          try { DRPY3.exposeRuntimeGlobals(globalThis.__rt); } catch (e) {
            console.log('[createRuntime] exposeRuntimeGlobals 失败:', e);
          }
        }
        return true;
      })()
    ''');
    debugPrint('[QjsDrpy3] Runtime 构造完成');
  }

  // ============================================================
  // 代理服务器
  // ============================================================
  Future<void> _startProxyServer() async {
    if (_proxyServer != null) return;
    final handler = shelf.Pipeline().addHandler((shelf.Request request) async {
      if (request.url.path != 'proxy') return shelf.Response.notFound('Not Found');
      try {
        final params = request.url.queryParameters;
        debugPrint('[QjsDrpy3][proxy] do=${params['do']}, '
            '_type=${params['_type']}, url=${_shortUrl(params['url'] ?? '')}');
        final result = await _callJsProxy(params);
        return await _handleProxyResult(result, request);
      } catch (e, st) {
        debugPrint('[QjsDrpy3][proxy] 异常: $e\n$st');
        return shelf.Response.internalServerError(body: 'Proxy error: $e');
      }
    });
    _proxyServer = await shelf_io.serve(handler, '127.0.0.1', 0);
    _proxyPort = _proxyServer!.port;
    debugPrint('[QjsDrpy3][proxy] 已启动: http://127.0.0.1:$_proxyPort/proxy');
  }

  String _shortUrl(String u) {
    if (u.length <= 80) return u;
    return '${u.substring(0, 80)}...(${u.length})';
  }

  Future<List<dynamic>> _callJsProxy(Map<String, String> params) async {
    if (!_ready || _engine == null) return [500, 'text/plain', 'not ready'];
    final paramsJson = jsonEncode(params);
    try {
      final jsonStr = await _engine!.evaluateAsync('''
        (async () => {
          let r;
          try {
            if (!globalThis.__src)
              return JSON.stringify({ s: 500, t: 'text/plain', c: 'no src', h: {}, b: null });
            r = await globalThis.__src.proxy($paramsJson);
          } catch (innerErr) {
            var name = (innerErr && innerErr.name) || 'UnknownError';
            var msg  = (innerErr && innerErr.message) || String(innerErr);
            return JSON.stringify({ s: 500, t: 'text/plain',
              c: 'proxy_inner [' + name + '] ' + msg, h: {}, b: null });
          }
          let status, ct, content, headers, toBytes;
          if (Array.isArray(r)) {
            status = typeof r[0] === 'number' ? r[0] : 404;
            ct = typeof r[1] === 'string' ? r[1] : 'application/octet-stream';
            content = r[2];
            headers = (r[3] && typeof r[3] === 'object') ? r[3] : {};
            toBytes = r[4];
          } else return JSON.stringify({ s: 404, t: 'text/plain', c: 'Not Found', h: {}, b: null });
          let cs = '', fb = toBytes;
          if (content == null) cs = '';
          else if (typeof content === 'string') cs = content;
          else if (content instanceof Uint8Array || content instanceof ArrayBuffer
                   || (content && content.buffer instanceof ArrayBuffer
                       && typeof content.byteLength === 'number')
                   || Array.isArray(content)) {
            cs = globalThis.__to_base64(content);
            fb = 1;
          } else cs = String(content);
          return JSON.stringify({ s: status, t: ct, c: cs, h: headers, b: fb });
        })()
      ''');
      if (jsonStr is! String) return [500, 'text/plain', 'not string'];
      final p = jsonDecode(jsonStr) as Map<String, dynamic>;
      final st = (p['s'] as num?)?.toInt() ?? 404;
      final ct = p['t']?.toString() ?? 'text/plain';
      final c = p['c']?.toString() ?? '';
      final h = (p['h'] as Map?)?.cast<String, dynamic>() ?? {};
      final b = p['b'];
      debugPrint('[QjsDrpy3][proxy] s=$st, t=$ct, c.len=${c.length}, b=$b');
      if (st >= 400) debugPrint('[QjsDrpy3][proxy] ⚠️ $c');
      return [st, ct, c, h, b];
    } catch (e) {
      debugPrint('[QjsDrpy3][proxy] $e');
      return [500, 'text/plain', 'err: $e'];
    }
  }

  Future<shelf.Response> _handleProxyResult(
      List<dynamic> result, shelf.Request request) async {
    if (result.length < 3) {
      return shelf.Response.internalServerError(body: 'invalid');
    }
    final status = (result[0] as num?)?.toInt() ?? 404;
    final ct = result[1]?.toString() ?? 'application/octet-stream';
    final content = result[2];
    final extra = result.length > 3 && result[3] is Map
        ? Map<String, String>.from((result[3] as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString())))
        : <String, String>{};
    final toBytes = result.length > 4 ? result[4] : null;
    final headers = <String, String>{
      'content-type': ct, 'access-control-allow-origin': '*', ...extra,
    };
    if (toBytes == 1 && content is String) {
      try { return shelf.Response(status, body: base64Decode(content), headers: headers); }
      catch (e) {
        return shelf.Response.internalServerError(body: 'b64 decode failed');
      }
    }
    if (toBytes == 2 && content is String) {
      headers['location'] = content;
      return shelf.Response(302, headers: headers);
    }
    if (toBytes == 3 && content is String) {
      try {
        final rq = <String, String>{};
        final range = request.headers['range'];
        if (range != null) rq['range'] = range;
        final resp = await _dio.get(content, options: Options(
            responseType: ResponseType.stream, headers: rq,
            validateStatus: (_) => true));
        final sh = <String, String>{
          ...headers, 'content-type': resp.headers.value('content-type') ?? ct,
        };
        final cr = resp.headers.value('content-range');
        if (cr != null) sh['content-range'] = cr;
        final ar = resp.headers.value('accept-ranges');
        if (ar != null) sh['accept-ranges'] = ar;
        return shelf.Response(resp.statusCode ?? 200,
            body: (resp.data as ResponseBody).stream, headers: sh);
      } catch (e) {
        return shelf.Response.internalServerError(body: 'pipe failed: $e');
      }
    }
    return shelf.Response(status,
        body: content is String ? content : content.toString(), headers: headers);
  }

  Future<Map<String, dynamic>> _doDioRequest(
      String url, Map<String, dynamic> opts) async {
    final method = (opts['method'] ?? 'GET').toString().toUpperCase();
    final headers = <String, String>{};
    ((opts['headers'] as Map?) ?? {}).forEach((k, v) {
      if (v == null) return;
      final ks = k.toString();
      final lk = ks.toLowerCase();
      if (lk == 'host' || lk == 'connection') return;
      headers[ks] = v is List ? v.join(', ') : v.toString();
    });
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 11; Pixel 5) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36';
    }
    dynamic body = opts['body'];
    if (opts['data'] != null) {
      body = jsonEncode(opts['data']);
      headers.putIfAbsent('Content-Type', () => 'application/json');
    }
    final bufferType = opts['buffer'];
    try {
      final resp = await _dio.request(url, options: Options(
          method: method, headers: headers, responseType: ResponseType.bytes,
          followRedirects: true, maxRedirects: 5, validateStatus: (_) => true),
          data: body);
      final bytes = (resp.data as List).cast<int>();
      final content = (bufferType == 1 || bufferType == 2)
          ? base64Encode(bytes) : utf8.decode(bytes, allowMalformed: true);
      final rh = <String, String>{};
      resp.headers.forEach((k, v) { if (v.isNotEmpty) rh[k] = v.first; });
      rh['access-control-allow-origin'] = '*';
      return {
        'status': resp.statusCode ?? 200,
        'content': content,
        'headers': rh,
        if (bufferType != null) 'buffer': bufferType,
      };
    } catch (e) {
      debugPrint('[QjsDrpy3][req] $e');
      rethrow;
    }
  }

  Future<Uint8List> _loadAsset(String rawPath) async {
    final cached = _assetCache[rawPath];
    if (cached != null) return cached;

    String url = rawPath;
    if (!rawPath.startsWith('http://') && !rawPath.startsWith('https://')) {
      final base = _currentSourceBase;
      if (base == null || base.isEmpty) {
        throw Exception('无 base URL: $rawPath');
      }
      final bu = Uri.parse(base);
      final r = bu.resolve(rawPath);
      url = (bu.hasQuery && !rawPath.contains('?'))
          ? r.replace(query: bu.query).toString()
          : r.toString();
    }
    final resp = await _dio.get<List<int>>(url,
        options: Options(responseType: ResponseType.bytes));
    if (resp.statusCode != 200) {
      throw Exception('loadAsset HTTP ${resp.statusCode}: $url');
    }
    final bytes = Uint8List.fromList(resp.data ?? <int>[]);
    final isSource = (rawPath == _currentSourceBase);
    if (!isSource && (
        rawPath.endsWith('.js') || rawPath.endsWith('.mjs')
        || rawPath.endsWith('.cjs') || rawPath.endsWith('.wasm')
        || rawPath.contains('wasm') || rawPath.contains('worker'))) {
      _assetCache[rawPath] = bytes;
    }
    return bytes;
  }

  // ============================================================
  // 源加载
  // ============================================================
  @override
  void setBaseUrl(String url) {}

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    _siteVersion++;
    _siteReady = Completer<void>();
    final version = _siteVersion;
    debugPrint('[QjsDrpy3] switchSite(v=$version): $siteKey');
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

  Future<void> _loadSource(int version, String apiUrl, String siteKey,
      {dynamic ext}) async {
    if (!await ensureInitialized()) { _completeSiteReady(version); return; }
    if (_engine == null) { _completeSiteReady(version); return; }
    try {
      _assetCache.clear();
      final extStr = ext is String ? ext : (ext?.toString() ?? '');
      String? sourceUrl;
      String? inlineCode;
      if (extStr.isNotEmpty) {
        if (extStr.startsWith('http')) sourceUrl = extStr;
        else if (extStr.contains('export default') ||
            extStr.contains('defineSource') || extStr.startsWith('{')) {
          inlineCode = extStr;
        }
      }
      if (sourceUrl == null && inlineCode == null && apiUrl.isNotEmpty) {
        sourceUrl = apiUrl;
      }
      if (sourceUrl == null && inlineCode == null) {
        _completeSiteReady(version);
        return;
      }
      String code;
      if (inlineCode != null) {
        code = inlineCode;
        _currentSourceBase = null;
      } else {
        final resp = await _dio.get<List<int>>(sourceUrl!,
            options: Options(responseType: ResponseType.bytes));
        code = utf8.decode((resp.data ?? []), allowMalformed: true);
        _currentSourceBase = sourceUrl;
        debugPrint('[QjsDrpy3] 源下载完成: ${code.length} chars, '
            'base=$_currentSourceBase');
      }
      final trimmed = code.trimLeft();
      if (trimmed.startsWith('H4sI')) {
        try {
          final cleaned = code.replaceAll(RegExp(r'\s'), '');
          code = utf8.decode(gzip.decode(base64Decode(cleaned)),
              allowMalformed: true);
        } catch (e) { debugPrint('[QjsDrpy3] b64+gzip 失败: $e'); }
      }
      final codeJson = jsonEncode(code);
      final keyJson = jsonEncode(siteKey);
      final pathJson = jsonEncode(sourceUrl ?? '');
      final extJson = jsonEncode(extStr);
      await _engine!.evaluateAsync('''
        (async () => {
          globalThis.__src = await globalThis.__rt.load($codeJson,
            { key: $keyJson, path: $pathJson });
          if (typeof globalThis.__src.init === 'function')
            await globalThis.__src.init($extJson);
          return true;
        })()
      ''');
      final ok = await _engine!.evaluateAsync(
          'typeof globalThis.__src !== "undefined" && globalThis.__src !== null');
      debugPrint('[QjsDrpy3] 源加载${ok == true ? "成功" : "失败"}: $siteKey');
    } catch (e, st) {
      debugPrint('[QjsDrpy3] 源加载异常: $e\n$st');
    } finally {
      _completeSiteReady(version);
    }
  }

  void _completeSiteReady(int version) {
    if (version != _siteVersion) return;
    final c = _siteReady;
    if (c != null && !c.isCompleted) c.complete();
  }

  // ============================================================
  // 业务入口
  // ============================================================
  Future<Map<String, dynamic>> _callSource(
      String fn, List<dynamic> args) async {
    final ready = _siteReady;
    if (ready != null && !ready.isCompleted) {
      try { await ready.future.timeout(const Duration(seconds: 90)); } catch (_) {}
    }
    if (!_ready) {
      final ok = await ensureInitialized();
      if (!ok) return {'success': false, 'error': 'not ready'};
    }
    if (_engine == null) return {'success': false, 'error': 'runtime null'};
    final argsJson = jsonEncode(args);
    try {
      final result = await _engine!.evaluateAsync('''
        (async () => {
          try {
            if (!globalThis.__src)
              return { success: false, error: '__src not loaded yet' };
            const args = $argsJson;
            const r = await globalThis.__src.$fn(...args);
            return r || {};
          } catch (e) {
            return { success: false, error: String((e && e.message) || e) };
          }
        })()
      ''');
      if (result is Map) return _normalizeUrls(result.cast<String, dynamic>());
      return {'success': false, 'error': 'unexpected'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Map<String, dynamic> _normalizeUrls(Map<String, dynamic> result) {
    final list = result['list'];
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final pic = item['vod_pic'];
        if (pic is String && pic.isNotEmpty && pic.startsWith('//')) {
          item['vod_pic'] = 'https:$pic';
        }
      }
    }
    return result;
  }

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
    if (list is! List || list.isEmpty) return null;
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
    final fl = from.split(r'$$$');
    final ul = url.split(r'$$$');
    final out = <PlaySource>[];
    for (var i = 0; i < fl.length && i < ul.length; i++) {
      final eps = <Episode>[];
      for (final part in ul[i].split('#')) {
        if (part.trim().isEmpty) continue;
        final kv = part.split(r'$');
        if (kv.length == 2) eps.add(Episode(name: kv[0], url: kv[1]));
      }
      if (eps.isNotEmpty) out.add(PlaySource(name: fl[i], episodes: eps));
    }
    return out;
  }

  void dispose() {
    _proxyServer?.close(force: true);
    _proxyServer = null;
    _engine?.dispose();
    _engine = null;
    _moduleLoader = null;
    _ready = false;
    isReady.value = false;
    _siteReady = null;
    _currentSourceBase = null;
    _assetCache.clear();
  }
}