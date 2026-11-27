import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter/foundation.dart';
import 'package:yuanying/utils/storage.dart';
import '../models/play_url.dart';
import '../models/video_detail.dart';
import 'i_spider_service.dart';
import 'package:yuanying/services/debug_log_service.dart';
import 'package:yuanying/t4/services/qjs_catvod_runtime_js.dart';
import 'package:yuanying/utils/error_formatter.dart';
import 'site_switch_result.dart';

class CatvodOpenService implements ISpiderService {
  String? _currentKey;
  Map<String, dynamic>? _currentExtMap;
  Map<String, String>? _methodMap;

  bool _isBroken = false;
  bool get isBroken => _isBroken;
  String? _lastSwitchError;
  dynamic _currentRawExt;

  late JavascriptRuntime _runtime;
  final Dio _reqDio = _createReqDio();

  static String? _cheerioSource;
  Future<void> _operationChain = Future<void>.value();

  /// 防止 _resetRuntime 重入的标志
  bool _resetting = false;

  CatvodOpenService() {
    _runtime = getJavascriptRuntime();
    _initRuntime();
    print('[CatvodOpen] Service created, initial runtime created.');
  }

  static Dio _createReqDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient()
          ..idleTimeout = const Duration(seconds: 15)
          ..autoUncompress = true
          ..badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );
    dio.options.validateStatus = (_) => true;
    return dio;
  }

  void _resetRuntime() {
    try {
      _runtime.dispose();
      print('[CatvodOpen] Old runtime disposed.');
    } catch (e) {
      print('[CatvodOpen] Dispose error: $e');
    }
    _runtime = getJavascriptRuntime();
    _initRuntime();
    print('[CatvodOpen] New runtime created and initialized.');
  }

  void _safeResetRuntime([Object? expectedRuntime]) {
    if (_resetting) return;
    // 如果调用方提供了快照 runtime，且当前 _runtime 已被他人替换，
    // 则不再重置，避免覆盖其他流程刚建立的新 runtime。
    if (expectedRuntime != null && !identical(_runtime, expectedRuntime)) {
      return;
    }
    _resetting = true;
    try {
      _resetRuntime();
    } finally {
      _resetting = false;
    }
  }

  void _initRuntime() {
    _runtime.evaluate('window = globalThis;');

    _runtime.evaluate('''
      (function() {
        globalThis.print = function() {
          console.log.apply(console, arguments);
        };
        globalThis.log = globalThis.print;
        if (typeof sendMessage === 'undefined') {
          window.sendMessage = function(channel, message) {
            console.error('sendMessage not available');
          };
        }

        if (typeof atob === 'undefined') {
          globalThis.atob = function(input) {
            const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
            let output = '';
            let buffer = 0;
            let bits = 0;
            for (let i = 0; i < input.length; i++) {
              const ch = input.charAt(i);
              if (ch === '=') break;
              const value = chars.indexOf(ch);
              if (value < 0 || value >= 64) continue;
              buffer = (buffer << 6) | value;
              bits += 6;
              if (bits >= 8) {
                bits -= 8;
                output += String.fromCharCode((buffer >> bits) & 0xff);
              }
            }
            return output;
          };
        }

        window.req = async function(url, options) {
          console.log('[CatJS] req called with URL:', url);
          return new Promise((resolve) => {
            const id = Date.now() + '_' + Math.random();
            window._reqCallbacks = window._reqCallbacks || {};
            window._reqCallbacks[id] = resolve;
            if (typeof sendMessage === 'function') {
              sendMessage('catReq', JSON.stringify({id, url, options: options || {}}));
            } else {
              resolve({content: '', headers: {}});
            }
          });
        };

        window._localCallbacks = {};
        window.local = {
          get: async (scope, key) => {
            return new Promise((resolve) => {
              const id = Date.now() + '_' + Math.random();
              window._localCallbacks[id] = resolve;
              if (typeof sendMessage === 'function') {
                sendMessage('catLocalGet', JSON.stringify({id, scope, key}));
              } else {
                resolve(null);
              }
            });
          },
          set: async (scope, key, value) => {
            return new Promise((resolve) => {
              const id = Date.now() + '_' + Math.random();
              window._localCallbacks[id] = resolve;
              if (typeof sendMessage === 'function') {
                sendMessage('catLocalSet', JSON.stringify({id, scope, key, value}));
              } else {
                resolve(null);
              }
            });
          },
          delete: async (scope, key) => {
            return new Promise((resolve) => {
              const id = Date.now() + '_' + Math.random();
              window._localCallbacks[id] = resolve;
              if (typeof sendMessage === 'function') {
                sendMessage('catLocalDelete', JSON.stringify({id, scope, key}));
              } else {
                resolve(null);
              }
            });
          }
        };

        globalThis.req = window.req;
        globalThis.local = window.local;

        // 二进制响应经 JSON 桥传入时先恢复为 Uint8Array。
        window.__catNormalizeResponse = function(value) {
          if (value && value.buffer === 1 && typeof value.content === 'string') {
            const binary = atob(value.content);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) {
              bytes[i] = binary.charCodeAt(i);
            }
            value.content = bytes;
          }
          return value;
        };

        var BaseSpider = class BaseSpider {
          constructor() {}
          async fetch(url, options = {}, headers = {}) {
            const reqOptions = {
              method: options.method || 'GET',
              headers: headers || {},
              body: options.body || null,
              timeout: options.timeout || 15000,
            };
            if (reqOptions.method === 'POST' && typeof reqOptions.body === 'object') {
              reqOptions.body = JSON.stringify(reqOptions.body);
              reqOptions.headers['Content-Type'] = 'application/json';
            }
            const response = await req(url, reqOptions);
            let data;
            try {
              data = JSON.parse(response.content);
            } catch(e) {
              data = { content: response.content };
            }
            return { data };
          }
          formatCount(num) {
            if (num > 1e8) return (num / 1e8).toFixed(2) + '亿';
            if (num > 1e4) return (num / 1e4).toFixed(2) + '万';
            return num.toString();
          }
          getSafe(obj, path, defaultValue = '') {
            if (!obj || typeof obj !== 'object') return defaultValue;
            try {
              return path.split('.').reduce((o, key) => {
                if (o == null) return defaultValue;
                return o[key];
              }, obj) ?? defaultValue;
            } catch {
              return defaultValue;
            }
          }
        };
        window.BaseSpider = BaseSpider;
        globalThis.BaseSpider = BaseSpider;
        console.log('[CatJS] BaseSpider defined as global class');
      })();
    ''');

    _runtime.onMessage('catReq', (args) {
      dynamic payload = args;
      if (args is List && args.isNotEmpty) payload = args.first;
      if (payload is Map) payload = jsonEncode(payload);
      if (payload is String && payload.isNotEmpty) handleCatReq(payload);
      return null;
    });
    _runtime.onMessage('catLocalGet', (args) {
      dynamic payload = args;
      if (args is List && args.isNotEmpty) payload = args.first;
      if (payload is Map) payload = jsonEncode(payload);
      if (payload is String && payload.isNotEmpty) {
        unawaited(handleCatLocalGet(payload));
      }
      return null;
    });
    _runtime.onMessage('catLocalSet', (args) {
      dynamic payload = args;
      if (args is List && args.isNotEmpty) payload = args.first;
      if (payload is Map) payload = jsonEncode(payload);
      if (payload is String && payload.isNotEmpty) {
        unawaited(handleCatLocalSet(payload));
      }
      return null;
    });
    _runtime.onMessage('catLocalDelete', (args) {
      dynamic payload = args;
      if (args is List && args.isNotEmpty) payload = args.first;
      if (payload is Map) payload = jsonEncode(payload);
      if (payload is String && payload.isNotEmpty) {
        unawaited(handleCatLocalDelete(payload));
      }
      return null;
    });
  }

  @override
  String? get currentKey => _currentKey;

  void handleCatReq(String payload) {
    String id = '';
    try {
      final data = jsonDecode(payload);
      id = data['id'] as String;
      final url = data['url'] as String;
      final options = data['options'] as Map<String, dynamic>? ?? {};
      _executeReq(id, url, options);
    } catch (e) {
      if (id.isNotEmpty) {
        _runtime.evaluate('''
          (function() {
            const cb = window._reqCallbacks && window._reqCallbacks["$id"];
            if (cb) {
              cb({ content: '', headers: {} });
              delete window._reqCallbacks["$id"];
            }
          })();
        ''');
      }
    }
  }

  Future<void> handleCatLocalGet(String payload) async {
    try {
      final data = jsonDecode(payload);
      final id = data['id'] as String;
      final scope = data['scope'] as String;
      final key = data['key'] as String;
      final fullKey = 'cat_${scope}_$key';
      final value = GStorage.setting.get(fullKey);
      final encoded = _encodeLocalValue(value);
      _runtime.evaluate('''
        (function() {
          const cb = window._localCallbacks && window._localCallbacks["$id"];
          if (cb) {
            cb($encoded);
            delete window._localCallbacks["$id"];
          }
        })();
      ''');
    } catch (e) {}
  }

  String _encodeLocalValue(dynamic value) {
    if (value == null) return 'null';
    try {
      return jsonEncode(value);
    } catch (_) {
      return jsonEncode(value.toString());
    }
  }

  Future<void> handleCatLocalSet(String payload) async {
    try {
      final data = jsonDecode(payload);
      final id = data['id'] as String;
      final scope = data['scope'] as String;
      final key = data['key'] as String;
      final value = data['value'];
      final fullKey = 'cat_${scope}_$key';
      await GStorage.setting.put(fullKey, value);
      _runtime.evaluate('''
        (function() {
          const cb = window._localCallbacks && window._localCallbacks["$id"];
          if (cb) {
            cb(null);
            delete window._localCallbacks["$id"];
          }
        })();
      ''');
    } catch (e) {}
  }

  Future<void> handleCatLocalDelete(String payload) async {
    try {
      final data = jsonDecode(payload);
      final id = data['id'] as String;
      final scope = data['scope'] as String;
      final key = data['key'] as String;
      final fullKey = 'cat_${scope}_$key';
      await GStorage.setting.delete(fullKey);
      _runtime.evaluate('''
        (function() {
          const cb = window._localCallbacks && window._localCallbacks["$id"];
          if (cb) {
            cb(null);
            delete window._localCallbacks["$id"];
          }
        })();
      ''');
    } catch (e) {}
  }

  Future<void> _executeReq(
    String id,
    String url,
    Map<String, dynamic> options,
  ) async {
    var method = 'GET';
    final headers = <String, String>{};
    String? body;
    try {
      method = (options['method']?.toString() ?? 'GET').toUpperCase();
      final rawHeaders = options['headers'];
      if (rawHeaders is Map) {
        rawHeaders.forEach((key, value) {
          if (value == null) return;
          final name = key.toString();
          final lower = name.toLowerCase();
          if (lower == 'host' ||
              lower == 'content-length' ||
              lower == 'connection') {
            return;
          }
          headers[name] = value is List ? value.join(', ') : value.toString();
        });
      }

      final rawBody = options['body'];
      if (rawBody is String) {
        body = rawBody;
      } else if (rawBody is Map || rawBody is List) {
        body = jsonEncode(rawBody);
        headers.putIfAbsent('Content-Type', () => 'application/json');
      }

      final data = options['data'];
      if (data != null) {
        if (data is Map) {
          body = Uri(queryParameters: Map.from(data)).query;
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
        } else if (data is String) {
          body = data;
        } else {
          body = jsonEncode(data);
          headers['Content-Type'] = 'application/json';
        }
      }

      DebugLogService.instance.logRequest(
        method: method,
        url: url,
        headers: headers,
        requestBody: body,
        source: 'catvod',
      );

      final startTime = DateTime.now();
      final response = await _reqDio.request<List<int>>(
        url,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
        ),
        data: body,
      );
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      final bytes = response.data ?? const <int>[];
      final rawBufferType = options['buffer'];
      final bufferType = rawBufferType is num
          ? rawBufferType.toInt()
          : int.tryParse(rawBufferType?.toString() ?? '');
      final content = bufferType == 1 || bufferType == 2
          ? base64Encode(bytes)
          : utf8.decode(bytes, allowMalformed: true);
      final resultHeaders = response.headers.map.map(
        (key, value) => MapEntry(key, value.join(',')),
      );

      DebugLogService.instance.logResponse(
        url: url,
        method: method,
        statusCode: response.statusCode,
        responseBody: utf8.decode(bytes, allowMalformed: true),
        responseSize: bytes.length,
        source: 'catvod',
        durationMs: duration,
      );

      _resolveReq(
        id,
        content: content,
        headers: resultHeaders,
        statusCode: response.statusCode,
        responseUrl: response.realUri.toString(),
        bufferType: bufferType,
      );
    } catch (error) {
      DebugLogService.instance.logResponse(
        url: url,
        method: method,
        statusCode: null,
        responseBody: error.toString(),
        source: 'catvod',
      );
      _resolveReq(
        id,
        content: '',
        headers: {'error': error.toString()},
        statusCode: 500,
        responseUrl: url,
      );
    }
  }

  void _resolveReq(
    String id, {
    required String content,
    required Map<String, String> headers,
    required int? statusCode,
    required String responseUrl,
    dynamic bufferType,
  }) {
    final status = statusCode ?? 500;
    final result = <String, dynamic>{
      'content': content,
      'headers': headers,
      'status': status,
      'statusCode': status,
      'url': responseUrl,
      'ok': status >= 200 && status < 300,
      if (bufferType != null) 'buffer': bufferType,
    };
    _runtime.evaluate('''
      (function() {
        const cb = window._reqCallbacks && window._reqCallbacks["$id"];
        if (cb) {
          cb(window.__catNormalizeResponse(${jsonEncode(result)}));
          delete window._reqCallbacks["$id"];
        }
      })();
    ''');
  }

  Future<void> _ensureHtmlParser() async {
    final currentType = _runtime
        .evaluate('typeof globalThis.pdfh')
        .stringResult;
    if (currentType == 'function') return;
    _cheerioSource ??= await rootBundle.loadString(
      'assets/js/lib/cheerio.min.js',
    );
    _runtime.evaluate(_cheerioSource!);
    _runtime.evaluate(qjsCatVodHtmlParserJs);
  }

  Future<void> _loadRule(String ruleContent) async {
    _runtime.evaluate('''
      (function() {
        window.__defaultExports = null;
        window.__jsEvalReturn = null;
        window.Spider = undefined;
        window._catApi = null;
        window._reqCallbacks = {};
        window._localCallbacks = {};
        delete window.Spider;
      })();
    ''');
    await _ensureHtmlParser();

    try {
      var lines = ruleContent.split('\n');
      var outputLines = <String>[];
      var inDefaultExport = false;
      var buffer = <String>[];

      for (var line in lines) {
        var trimmed = line.trim();
        if (trimmed.startsWith('import ')) continue;

        if (trimmed.startsWith('export function __jsEvalReturn')) {
          line = line.replaceFirst(
            'export function ',
            'window.__jsEvalReturn = function ',
          );
          outputLines.add(line);
          outputLines.add(
            'if (typeof window.__jsEvalReturn === "undefined") window.__jsEvalReturn = __jsEvalReturn;',
          );
          continue;
        }

        if (trimmed.startsWith('export default ')) {
          var rest = line.replaceFirst('export default ', '');
          if (rest.trim().endsWith(';') ||
              rest.trim().endsWith('}') ||
              rest.trim().endsWith(')')) {
            outputLines.add('window.__defaultExports = $rest');
          } else {
            inDefaultExport = true;
            buffer.add(rest);
          }
          continue;
        }

        if (inDefaultExport) {
          buffer.add(line);
          var combined = buffer.join('\n');
          if (combined.trim().endsWith(';') ||
              combined.trim().endsWith('}') ||
              combined.trim().endsWith(')')) {
            outputLines.add('window.__defaultExports = $combined');
            inDefaultExport = false;
            buffer.clear();
          }
          continue;
        }

        if (trimmed.contains('export')) {
          if (trimmed.startsWith('export function ')) {
            line = line.replaceFirst('export function ', 'function ');
          } else if (trimmed.startsWith('export const ')) {
            line = line.replaceFirst('export const ', 'const ');
          } else if (trimmed.startsWith('export let ')) {
            line = line.replaceFirst('export let ', 'let ');
          } else if (trimmed.startsWith('export var ')) {
            line = line.replaceFirst('export var ', 'var ');
          } else if (trimmed.startsWith('export {')) {
            continue;
          } else {
            line = line.replaceAll('export', '');
          }
        }
        if (line.isNotEmpty) outputLines.add(line);
      }
      if (inDefaultExport && buffer.isNotEmpty) {
        outputLines.add('window.__defaultExports = ' + buffer.join('\n'));
      }

      final processed = outputLines.join('\n');
      final finalCode = 'var req = window.req;\n' + processed;

      try {
        _runtime.evaluate(finalCode);
      } catch (e) {
        rethrow;
      }

      var defType = _runtime.evaluate('typeof window.__defaultExports');
      var defVal = _runtime.evaluate('window.__defaultExports');
      if (defType.stringResult != 'object' || defVal.stringResult == 'null') {
        var jsEvalType = _runtime.evaluate('typeof window.__jsEvalReturn');
        if (jsEvalType.stringResult == 'function') {
          _runtime.evaluate('''
            (function() {
              try {
                var obj = window.__jsEvalReturn();
                if (obj && typeof obj === 'object') {
                  window.__defaultExports = obj;
                }
              } catch(e) {}
            })();
          ''');
        }
      }

      final result = _runtime.evaluate('''
        (function() {
          var standardNames = ['init', 'home', 'homeVod', 'category', 'detail', 'play', 'search'];
          var altNames = {
            home: ['home', 'homeContent'],
            homeVod: ['homeVod', 'homeVodContent'],
            category: ['category', 'categoryContent'],
            detail: ['detail', 'detailContent'],
            play: ['play', 'playerContent'],
            search: ['search', 'searchContent']
          };
          var apiObj = null;
          var methodMap = {};

          if (typeof window.__defaultExports !== 'undefined' && window.__defaultExports !== null) {
            var val = window.__defaultExports;
            if (typeof val === 'function') {
              try { apiObj = val(); } catch(e) {}
            } else if (typeof val === 'object') {
              apiObj = val;
            }
          }

          if (!apiObj && typeof window.__jsEvalReturn !== 'undefined' && window.__jsEvalReturn !== null) {
            var val = window.__jsEvalReturn;
            if (typeof val === 'function') {
              try { apiObj = val(); } catch(e) {}
            } else if (typeof val === 'object') {
              apiObj = val;
            }
          }

          if (!apiObj && typeof window.Spider === 'function') {
            try { apiObj = new window.Spider(); } catch(e) {}
          }

          if (!apiObj || typeof apiObj !== 'object' || apiObj === null) {
            return null;
          }

          for (var i = 0; i < standardNames.length; i++) {
            var std = standardNames[i];
            var candidates = altNames[std] || [std];
            for (var j = 0; j < candidates.length; j++) {
              var name = candidates[j];
              if (typeof apiObj[name] === 'function') {
                methodMap[std] = name;
                break;
              }
            }
          }
          if (Object.keys(methodMap).length === 0) {
            return null;
          }

          window._catApi = apiObj;
          return JSON.stringify(methodMap);
        })();
      ''');

      if (result.stringResult == 'null' || result.stringResult.isEmpty) {
        throw Exception('No Cat API functions found');
      }

      final methodMap = jsonDecode(result.stringResult) as Map<String, dynamic>;
      if (methodMap.isEmpty) throw Exception('API object has no methods');

      _methodMap = Map<String, String>.from(
        methodMap.map((k, v) => MapEntry(k, v.toString())),
      );
      print('[CatvodOpen] ✅ Rule loaded, method map: $_methodMap');
    } catch (e) {
      print('[CatvodOpen] ❌ Rule load error: $e');
      rethrow;
    }
  }

  @override
  void setBaseUrl(String url) {}

  @override
  Future<void> switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    return _serial(
      () => _switchSiteInternal(apiUrl, siteKey, ext: ext),
    );
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _operationChain;
    final completer = Completer<T>();
    _operationChain = () async {
      try {
        await previous;
      } catch (_) {}
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  @override
  Future<SiteSwitchResult> switchSiteSafe(
    String apiUrl,
    String siteKey, {
    dynamic ext,
  }) async {
    try {
      await switchSite(apiUrl, siteKey, ext: ext);
      if (_isBroken) {
        return SiteSwitchResult.failure(
          _lastSwitchError ?? '规则加载失败',
          siteKey: siteKey,
        );
      }
      return SiteSwitchResult.success(siteKey: siteKey);
    } catch (e) {
      return SiteSwitchResult.failure(e.toString(), siteKey: siteKey);
    }
  }

  Future<void> _switchSiteInternal(
    String apiUrl,
    String siteKey, {
    dynamic ext,
  }) async {
    print('[CatvodOpen] 🔄 switchSite: $siteKey');

    // 保存旧 runtime 引用，用于成功后 dispose
    final oldRuntime = _runtime;

    // 直接创建新 runtime 并切换，不保存其他旧状态
    final newRuntime = getJavascriptRuntime();
    _runtime = newRuntime;
    _initRuntime();

    // 直接更新为新站点状态
    _currentKey = siteKey;
    _currentRawExt = ext ?? '';
    _methodMap = null;
    _isBroken = false;
    _lastSwitchError = null;

    if (ext is String && ext.isNotEmpty) {
      try {
        _currentExtMap = jsonDecode(ext) as Map<String, dynamic>;
      } catch (_) {
        _currentExtMap = null;
      }
    } else {
      _currentExtMap = null;
    }

    try {
      // 加载规则
      if (apiUrl.startsWith('http')) {
        final response = await _reqDio.get(
          apiUrl,
          options: Options(responseType: ResponseType.plain),
        );
        if (response.statusCode != 200) {
          throw Exception('规则下载失败: HTTP ${response.statusCode}');
        }
        final content = response.data as String? ?? '';
        if (content.isEmpty) {
          throw Exception('规则内容为空');
        }
        await _loadRule(content);
      } else if (File(apiUrl).existsSync()) {
        // 本地文件源
        final content = await File(apiUrl).readAsString();
        if (content.isEmpty) {
          throw Exception('本地规则文件为空: $apiUrl');
        }
        print('[CatvodOpen] 本地源文件: $apiUrl (${content.length} chars)');
        await _loadRule(content);
      } else {
        await _loadRule(apiUrl);
      }

      if (_methodMap?.containsKey('init') == true) {
        final initResult = await _callAsync('init', [
          <String, dynamic>{
            'stype': 4,
            'skey': siteKey,
            'sourceKey': siteKey,
            'ext': _currentRawExt,
          },
        ]);
        final initError = initResult['error']?.toString() ?? '';
        if (initError.isNotEmpty) {
          throw Exception('规则初始化失败：$initError');
        }
      }

      // 成功：dispose 旧 runtime
      try {
        oldRuntime.dispose();
        print('[CatvodOpen] Old runtime disposed after successful switch.');
      } catch (e) {
        print('[CatvodOpen] Old runtime dispose error: $e');
      }

      _isBroken = false;
      print('[CatvodOpen] ✅ switchSite completed');
    } catch (e) {
      // 失败：不回滚，标记为 broken
      print('[CatvodOpen] ❌ switchSite error: $e，标记为 broken（不回滚）');

      // 新 runtime 保留（虽然规则加载失败，但 runtime 可用）
      // _currentKey 保持为新站点
      // _methodMap 保持 null（规则未加载成功）
      _isBroken = true;
      _lastSwitchError = e.toString();

      // dispose 旧 runtime，避免资源泄漏
      try {
        oldRuntime.dispose();
      } catch (_) {}

      // 不 rethrow：让调用方正常继续
      // 后续 _callApi 检查 _isBroken，返回错误给 UI
      print('[CatvodOpen] ⚠️ 已进入 broken 状态，key=$siteKey');
    }
  }

  Future<Map<String, dynamic>> _callAsync(
    String method,
    List<dynamic> args,
  ) async {
    final runtime = _runtime;
    final methodMap = _methodMap;
    if (methodMap == null || !methodMap.containsKey(method)) {
      return {'error': ErrorFormatter.formatScriptError('方法不存在: $method')};
    }

    final actualMethod = methodMap[method]!;
    final argsJson = jsonEncode(args);

    final jsCode =
        '''
      (function() {
        try {
          if (typeof window.req === 'undefined') {
            window.req = async function(url, options) {
              return new Promise((resolve) => {
                if (typeof sendMessage !== 'function') {
                  resolve({content: '', headers: {}});
                  return;
                }
                const id = Date.now() + '_' + Math.random();
                window._reqCallbacks = window._reqCallbacks || {};
                window._reqCallbacks[id] = resolve;
                sendMessage('catReq', JSON.stringify({id, url, options: options || {}}));
              });
            };
          }

          var api = window._catApi || window.__defaultExports;
          if (!api) throw new Error('API not ready');

          var fn = api['$actualMethod'];
          if (typeof fn !== 'function') throw new Error('Method not found: $actualMethod');

          var result = fn.apply(api, $argsJson);
          if (result && typeof result.then === 'function') {
            return result
              .then(r => JSON.stringify(r === undefined || r === null ? {} : r))
              .catch(e => JSON.stringify({error: e.message}));
          }
          if (result === undefined || result === null) {
            return JSON.stringify({});
          }
          return JSON.stringify(result);
        } catch(e) {
          return JSON.stringify({error: e.message});
        }
      })();
    ''';

    try {
      final jsResult = await runtime.evaluateAsync(jsCode);
      runtime.executePendingJob();

      // 关键：handlePromise 加超时，防止挂起的 Promise 永久阻塞业务调用
      final finalResult = await runtime
          .handlePromise(jsResult)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException('JS Promise 超时（20s）'),
          );

      final raw = finalResult.stringResult;
      try {
        dynamic parsed = jsonDecode(raw);
        if (parsed is String) parsed = jsonDecode(parsed);
        if (parsed is Map<String, dynamic>) {
          if (parsed.containsKey('error')) {
            return {'error': parsed['error'].toString()};
          }
          return parsed;
        }
        return {'error': '脚本执行失败：响应格式异常'};
      } catch (e) {
        return {'error': '脚本执行失败：响应解析失败'};
      }
    } on TimeoutException catch (e) {
      // 挂起的 Promise 会污染当前 runtime，标记 broken 并重建
      _isBroken = true;
      debugPrint('[CatvodOpen] _callAsync 超时: $e');
      _safeResetRuntime(runtime);
      return {'error': ErrorFormatter.formatScriptError('脚本执行超时')};
    } catch (e) {
      return {'error': ErrorFormatter.formatScriptError(e)};
    }
  }

  Future<Map<String, dynamic>> _callApi(
    String method, {
    List<dynamic> args = const [],
  }) async {
    return _serial(() async {
      if (_isBroken) {
        return {'error': '脚本执行失败：规则未加载，请切换其他源'};
      }
      try {
        await _ensureHtmlParser();
        return await _callAsync(method, args);
      } catch (error) {
        return {'error': error.toString()};
      }
    });
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    return await _callApi('home', args: [filter]);
  }

  @override
  Future<Map<String, dynamic>> fetchCate(
    String cateId,
    int page, {
    String? ext,
  }) async {
    // 快照 _currentExtMap，避免 await 期间被 switchSite 替换
    final extend = Map<String, dynamic>.from(_currentExtMap ?? {});
    if (ext != null && ext.isNotEmpty) {
      try {
        String decodedStr = ext;
        try {
          final decodedBytes = base64Decode(ext);
          decodedStr = utf8.decode(decodedBytes);
        } catch (_) {}
        final parsed = jsonDecode(decodedStr) as Map<String, dynamic>;
        extend.addAll(parsed);
      } catch (_) {}
    }
    return await _callApi('category', args: [cateId, page, null, extend]);
  }

  @override
  Future<Map<String, dynamic>> search(
    String wd,
    int page, {
    int quick = 0,
  }) async {
    return await _callApi('search', args: [wd, quick, page]);
  }

  @override
  Future<VideoDetail?> getDetail({
    required String vodId,
    required String pwd,
  }) async {
    final map = await _callApi('detail', args: [vodId]);
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
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    return await _callApi('detail', args: [ids]);
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    final map = await _callApi('play', args: [flag, playParams, []]);
    final playData = _normalizePlayData(_extractPlayData(map));
    if (playData.containsKey('error') ||
        (!playData.containsKey('parse') &&
            !playData.containsKey('url') &&
            !playData.containsKey('urls'))) {
      return null;
    }
    try {
      final playUrl = PlayUrl.fromJson(playData);
      final url = playUrl.defaultUrl?.trim() ?? '';
      return url.isEmpty ? null : playUrl;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) async {
    final map = await _callApi('play', args: [flag ?? '', play, []]);
    return _normalizePlayData(_extractPlayData(map));
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

  Map<String, dynamic> _extractPlayData(Map<String, dynamic> result) {
    dynamic data = result['data'];
    if (data is String && data.trim().isNotEmpty) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }
    if (data is Map) return data.cast<String, dynamic>();
    return result;
  }

  Map<String, dynamic> _normalizePlayData(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    for (final key in const ['parse', 'jx', 'isDash', 'is_dash', 'dash']) {
      final value = normalized[key];
      if (value is bool) {
        normalized[key] = value ? 1 : 0;
      } else if (value is num) {
        normalized[key] = value.toInt();
      } else if (value is String) {
        final text = value.trim().toLowerCase();
        if (text == 'true') {
          normalized[key] = 1;
        } else if (text == 'false') {
          normalized[key] = 0;
        } else {
          normalized[key] = int.tryParse(text);
        }
      }
    }
    final header = normalized['header'] ?? normalized['headers'];
    if (header is Map) {
      normalized['header'] = header.map(
        (key, value) => MapEntry(
          key.toString(),
          value is List ? value.join(', ') : '$value',
        ),
      );
    }
    return normalized;
  }

  void dispose() {
    try {
      _runtime.dispose();
    } catch (e) {}
  }
}
