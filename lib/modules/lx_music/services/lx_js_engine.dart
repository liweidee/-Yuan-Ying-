import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';

import '../models/lx_music_model.dart';
import '../models/lx_script_model.dart';
import '../storage/lx_storage.dart';
import '../utils/lx_logger.dart';

/// 洛雪音乐 JS 引擎
///
/// 兼容洛雪 lx 协议：注入 `lx` 全局对象，脚本通过 `lx.send('inited', ...)`
/// 注册音源，通过 `lx.on('request', handler)` 处理取 URL/歌词请求。
///
/// 核心机制：
/// - JS 互斥锁（高优抢占低优）
/// - HTTP 请求队列轮询 + 微任务刷新
/// - 并行取 URL（独立临时运行时）
class LxJsEngine {
  LxJsEngine._();
  static final LxJsEngine instance = LxJsEngine._();

  // ==================== 状态 ====================

  final Map<String, LxScript> _scripts = {};
  LxScript? _currentScript;
  bool _isInitialized = false;
  JavascriptRuntime? _jsRuntime;
  Map<String, LxScriptSource> _sources = {};
  bool _scriptInitialized = false;
  String? _updateUrl;

  /// 最后一次脚本错误信息（供上层展示）
  String? lastScriptError;

  /// 最后一次激活/初始化失败原因
  String? lastActivationError;

  // ==================== 事件流 ====================

  final _stateController = StreamController<LxEngineState>.broadcast();
  final _eventController = StreamController<LxEngineEvent>.broadcast();

  Stream<LxEngineState> get stateStream => _stateController.stream;
  Stream<LxEngineEvent> get eventStream => _eventController.stream;

  // ==================== Getters ====================

  LxScript? get currentScript => _currentScript;
  bool get isInitialized => _isInitialized;
  bool get isActive => _currentScript != null && _scriptInitialized;
  Map<String, LxScriptSource> get sources => _sources;
  String? get updateUrl => _updateUrl;

  List<LxScript> getAllScripts() => _scripts.values.toList();
  LxScript? getScript(String id) => _scripts[id];

  // ==================== dio 单例 ====================

  /// 独立 Dio，专供 JS 脚本 request 使用
  /// 不自动解析 JSON（保持与波点 http 一致），手动处理
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
    responseType: ResponseType.plain,
    // 不校验状态码，让 JS 脚本自己处理
    validateStatus: (_) => true,
    followRedirects: true,
    maxRedirects: 5,
  ));

  // ==================== JS 锁 ====================

  Completer<void> _jsLockCompleter = Completer<void>()..complete();
  int _lockEpoch = 0;
  bool _preemptRequested = false;

  Future<T> _withJsLock<T>(
    Future<T> Function() action, {
    required bool priority,
    Duration timeout = const Duration(seconds: 10),
  }) {
    final prev = _jsLockCompleter;
    final completer = Completer<void>();
    _jsLockCompleter = completer;
    if (priority) {
      _preemptRequested = true;
    }
    final myEpoch = ++_lockEpoch;

    Future<T> runWithTimeout() async {
      final waitStart = DateTime.now();
      while (!prev.isCompleted) {
        if (DateTime.now().difference(waitStart) > timeout) {
          LxLogger.warn('JS 锁等待超时');
          throw TimeoutException('JS lock wait timeout');
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (priority) _preemptRequested = false;
      return action().timeout(timeout, onTimeout: () {
        LxLogger.warn('JS 任务执行超时');
        throw TimeoutException('JS task timeout');
      });
    }

    final resultFuture = runWithTimeout();
    resultFuture.whenComplete(() => completer.complete());
    return resultFuture;
  }

  void _checkPreempted() {
    if (_preemptRequested) {
      throw TimeoutException('preempted by user request');
    }
  }

  // ==================== 初始化 ====================

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _loadScriptsFromStorage();
    _stateController.add(LxEngineState.loaded);
  }

  Future<void> _loadScriptsFromStorage() async {
    try {
      final stored = await LxStorage.instance.loadScripts();
      if (stored.isEmpty) return;
      for (final script in stored) {
        if (script.content.isEmpty) continue;
        _scripts[script.id] = script;
      }
      if (_scripts.isNotEmpty) {
        LxLogger.info('从本地加载 ${_scripts.length} 个脚本');
      }
    } catch (e) {
      LxLogger.error('加载脚本失败: $e');
    }
  }

  Future<void> _saveScriptsToStorage() async {
    try {
      await LxStorage.instance.saveScripts(_scripts.values.toList());
    } catch (e) {
      LxLogger.error('保存脚本失败: $e');
    }
  }

  // ==================== 导入脚本 ====================

  Future<LxScript> importScript(String scriptContent) async {
    try {
      _stateController.add(LxEngineState.loading);
      final info = _parseScriptMetadata(scriptContent);
      final scriptId = _generateId();
      final script = LxScript(
        id: scriptId,
        name: info['name'] ?? 'Unnamed Script',
        description: info['description'] ?? '',
        author: info['author'] ?? '',
        version: info['version'] ?? '1.0.0',
        homepage: info['homepage'] ?? '',
        content: scriptContent,
        importedAt: DateTime.now(),
      );
      _scripts[scriptId] = script;
      await _saveScriptsToStorage();
      _stateController.add(LxEngineState.loaded);
      _eventController.add(LxEngineEvent.scriptImported(script));
      LxLogger.info('导入脚本: ${script.name} v${script.version}');
      return script;
    } catch (e) {
      _stateController.add(LxEngineState.error);
      LxLogger.error('导入脚本失败: $e');
      throw Exception('Failed to import script: $e');
    }
  }

  /// 从远程 URL 导入脚本
  Future<LxScript> importScriptFromUrl(String url) async {
    LxLogger.info('从 URL 下载脚本: $url');
    try {
      final resp = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );
      final statusCode = resp.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        throw Exception('下载失败: HTTP $statusCode');
      }
      final content = resp.data?.toString() ?? '';
      if (content.isEmpty) {
        throw Exception('脚本内容为空');
      }
      return importScript(content);
    } catch (e) {
      LxLogger.error('远程导入失败: $e');
      rethrow;
    }
  }

  Map<String, String> _parseScriptMetadata(String script) {
    final info = <String, String>{};
    final commentMatch = RegExp(r'^/\*[\s\S]+?\*/').firstMatch(script);
    if (commentMatch == null) {
      throw Exception('Script must start with a block comment for metadata');
    }
    final commentBlock = commentMatch.group(0)!;
    final nameMatch = RegExp(r'@name\s+(.+)').firstMatch(commentBlock);
    if (nameMatch != null) info['name'] = _truncate(nameMatch.group(1)!.trim(), 24);
    final descMatch = RegExp(r'@description\s+(.+)').firstMatch(commentBlock);
    if (descMatch != null) {
      info['description'] = _truncate(descMatch.group(1)!.trim(), 36);
    }
    final authorMatch = RegExp(r'@author\s+(.+)').firstMatch(commentBlock);
    if (authorMatch != null) {
      info['author'] = _truncate(authorMatch.group(1)!.trim(), 56);
    }
    final versionMatch = RegExp(r'@version\s+(.+)').firstMatch(commentBlock);
    if (versionMatch != null) {
      info['version'] = _truncate(versionMatch.group(1)!.trim(), 36);
    }
    final homepageMatch = RegExp(r'@homepage\s+(.+)').firstMatch(commentBlock);
    if (homepageMatch != null) {
      info['homepage'] = _truncate(homepageMatch.group(1)!.trim(), 1024);
    }
    if (!info.containsKey('name')) {
      info['name'] = 'user_api_${DateTime.now().millisecondsSinceEpoch}';
    }
    return info;
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  String _generateId() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final randomStr = (random % 1000).toString().padLeft(3, '0');
    return 'user_api_${randomStr}_$random';
  }

  // ==================== 激活/停用 ====================

  Future<void> activateScript(String scriptId) async {
    if (!_scripts.containsKey(scriptId)) {
      throw Exception('Script not found: $scriptId');
    }
    final script = _scripts[scriptId]!;
    _currentScript = script;
    _scriptInitialized = false;
    _sources = {};
    _updateUrl = null;
    lastActivationError = null;
    lastScriptError = null;

    await LxStorage.instance.setActiveScriptId(scriptId);
    _stateController.add(LxEngineState.loading);
    _eventController.add(LxEngineEvent.scriptActivated(script));

    unawaited(_initScriptRuntime(script));
  }

  Completer<void>? _initCompleter;

  Future<void> _initScriptRuntime(LxScript script) async {
    final scriptId = script.id;
    if (_currentScript?.id != scriptId) return;
    final completer = Completer<void>();
    _initCompleter = completer;
    try {
      await _initJsRuntime(script);
      if (_currentScript?.id != scriptId) return;
      if (_scriptInitialized) {
        LxLogger.info('脚本激活完成: ${script.name}');
        _stateController.add(LxEngineState.active);
      } else {
        lastActivationError = '脚本初始化超时，未收到音源注册数据';
        LxLogger.warn('脚本激活失败: $lastActivationError');
        _stateController.add(LxEngineState.error);
        _eventController.add(
            LxEngineEvent.scriptError(script, lastActivationError));
      }
    } catch (e) {
      if (_currentScript?.id != scriptId) return;
      lastActivationError = e.toString();
      LxLogger.error('脚本激活异常: $e');
      _stateController.add(LxEngineState.error);
      _eventController.add(LxEngineEvent.scriptError(script, lastActivationError));
    } finally {
      if (identical(_initCompleter, completer)) _initCompleter = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _waitForScriptInit() async {
    final initWait = _initCompleter;
    if (initWait != null && !initWait.isCompleted) {
      LxLogger.info('等待脚本初始化完成...');
      try {
        await initWait.future.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        LxLogger.warn('等待脚本初始化超时');
      }
    }
  }

  Future<void> deactivateScript() async {
    _jsRuntime?.dispose();
    _jsRuntime = null;
    _currentScript = null;
    _scriptInitialized = false;
    _sources = {};
    _updateUrl = null;
    lastActivationError = null;
    lastScriptError = null;
    await LxStorage.instance.setActiveScriptId(null);
    _stateController.add(LxEngineState.idle);
    _eventController.add(LxEngineEvent.scriptDeactivated());
  }

  Future<void> removeScript(String scriptId) async {
    if (_currentScript?.id == scriptId) {
      await deactivateScript();
    }
    _scripts.remove(scriptId);
    await _saveScriptsToStorage();
    _eventController.add(LxEngineEvent.scriptRemoved(scriptId));
  }

  Future<String?> getPersistedActiveScriptId() async {
    return LxStorage.instance.getActiveScriptId();
  }

  /// 启动时恢复激活脚本
  Future<void> restoreActiveScript() async {
    final id = await LxStorage.instance.getActiveScriptId();
    if (id == null) return;
    if (!_scripts.containsKey(id)) {
      LxLogger.warn('恢复失败：脚本不存在 $id');
      return;
    }
    await activateScript(id);
  }

  // ==================== JS 运行时初始化 ====================

  Future<void> _initJsRuntime(LxScript script) async {
    LxLogger.clear();
    LxLogger.info('=== 初始化用户 API 脚本 ===');
    _jsRuntime?.dispose();
    _jsRuntime = getJavascriptRuntime();
    _setupLxApi(script);
    LxLogger.info('执行脚本 (${script.name} v${script.version})...');
    final result = _jsRuntime!.evaluate(script.content);
    if (result.isError) {
      LxLogger.error('脚本执行错误: ${result.stringResult}');
      throw Exception('Script execution error: ${result.stringResult}');
    }
    LxLogger.info('脚本执行成功');

    // 同步脚本立即检查
    var initData = _jsRuntime!.evaluate('globalThis.__lx_init_data__');
    if (!initData.isError &&
        initData.stringResult != 'null' &&
        initData.stringResult.isNotEmpty) {
      LxLogger.info('收到初始化数据(同步): ${_truncate(initData.stringResult, 200)}');
      _parseInitData(initData.stringResult);
      _checkUpdateAlert();
      _scriptInitialized = true;
      LxLogger.info('脚本初始化成功，已注册音源: ${_sources.keys.join(', ')}');
      return;
    }

    LxLogger.info('同步阶段未收到 init 数据，进入异步轮询...');
    for (var i = 0; i < 100; i++) {
      await _processPendingRequests(null, 50);
      for (var j = 0; j < 20; j++) {
        _jsRuntime!.executePendingJob();
      }
      await Future.delayed(Duration.zero);

      final alertCheck = _jsRuntime!.evaluate('globalThis.__lx_update_alert__');
      if (!alertCheck.isError &&
          alertCheck.stringResult != 'null' &&
          alertCheck.stringResult.isNotEmpty) {
        _checkUpdateAlert();
        final msg = _updateUrl != null
            ? '脚本已停用，请更新: $_updateUrl'
            : '脚本已停用，请获取最新版本';
        LxLogger.warn('脚本停用检测: $msg');
        throw Exception(msg);
      }
      _checkUpdateAlert();
      initData = _jsRuntime!.evaluate('globalThis.__lx_init_data__');
      if (!initData.isError &&
          initData.stringResult != 'null' &&
          initData.stringResult.isNotEmpty) {
        LxLogger.info(
            '收到初始化数据(异步轮询 #${i + 1}): ${_truncate(initData.stringResult, 200)}');
        _parseInitData(initData.stringResult);
        _checkUpdateAlert();
        _scriptInitialized = true;
        LxLogger.info('脚本初始化成功，已注册音源: ${_sources.keys.join(', ')}');
        return;
      }
      final qLen = _jsRuntime!.evaluate('globalThis.__lx_request_queue__.length');
      if (qLen.isError || qLen.stringResult == '0') break;
    }
    LxLogger.warn('初始化完成但未收到 init 数据，音源未注册');
    throw Exception('脚本初始化失败，未收到音源注册数据');
  }

  void _checkUpdateAlert() {
    final alert = _jsRuntime!.evaluate('globalThis.__lx_update_alert__');
    if (alert.isError || alert.stringResult == 'null' || alert.stringResult.isEmpty) {
      return;
    }
    _jsRuntime!.evaluate('globalThis.__lx_update_alert__ = null');
    try {
      final data = jsonDecode(alert.stringResult);
      final log = data['log']?.toString() ?? '';
      final updateUrl = data['updateUrl']?.toString();
      LxLogger.warn('脚本版本更新提示: $log${updateUrl != null ? ' ($updateUrl)' : ''}');
      if (updateUrl != null && updateUrl.isNotEmpty) {
        _updateUrl = updateUrl;
      }
    } catch (e) {
      LxLogger.warn('updateAlert 解析失败: $e');
    }
  }

  // ==================== lx 桥接环境 ====================

  void _setupLxApi(LxScript script, [JavascriptRuntime? targetRuntime]) {
    final rawScript = script.content;
    final runtime = targetRuntime ?? _jsRuntime!;

    void evalOrThrow(String code, String label) {
      final r = runtime.evaluate(code);
      if (r.isError) {
        LxLogger.error('JS 环境[$label] 加载失败: ${r.stringResult}');
        throw Exception('LxEngine JS env [$label] error: ${r.stringResult}');
      }
    }

    evalOrThrow('''
      globalThis.__lx_handlers__ = {};
      globalThis.__lx_init_data__ = null;
      globalThis.__lx_result__ = null;
      globalThis.__lx_request_queue__ = [];
      globalThis.__lx_update_alert__ = null;
      globalThis.__lx_inited__ = false;
    ''', 'slots');

    // ===== Polyfill =====
    runtime.evaluate('''
      if (typeof globalThis.clearTimeout !== 'function') {
        globalThis.clearTimeout = function(id) {
          try {
            if (typeof __NATIVE_FLUTTER_JS__setTimeoutCallbacks !== 'undefined') {
              delete __NATIVE_FLUTTER_JS__setTimeoutCallbacks[String(id)];
            }
          } catch (e) {}
        };
      }
      var __lx_intervals__ = {};
      if (typeof globalThis.setInterval !== 'function') {
        globalThis.setInterval = function(fn, ms) {
          if (typeof fn !== 'function') throw new Error('callback required a function');
          var args = Array.prototype.slice.call(arguments, 2);
          var id = null;
          var stopped = false;
          var run = function() {
            if (stopped) return;
            try { fn.apply(null, args); } catch (e) {}
            id = setTimeout(run, ms);
          };
          id = setTimeout(run, ms);
          __lx_intervals__[id] = true;
          return id;
        };
      }
      if (typeof globalThis.clearInterval !== 'function') {
        globalThis.clearInterval = function(id) {
          if (id in __lx_intervals__) {
            delete __lx_intervals__[id];
          }
          clearTimeout(id);
        };
      }
      if (typeof console.info !== 'function') console.info = console.log;
      if (typeof console.debug !== 'function') console.debug = console.log;
      if (typeof globalThis.btoa !== 'function') {
        globalThis.btoa = function(input) {
          var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
          var bytes = [];
          for (var i = 0; i < input.length; i++) {
            var c = input.charCodeAt(i);
            if (c < 128) bytes.push(c);
            else if (c < 2048) { bytes.push((c >> 6) | 192, (c & 63) | 128); }
            else { bytes.push((c >> 12) | 224, ((c >> 6) & 63) | 128, (c & 63) | 128); }
          }
          var out = '';
          for (var j = 0; j < bytes.length; j += 3) {
            var b1 = bytes[j], b2 = j + 1 < bytes.length ? bytes[j + 1] : -1, b3 = j + 2 < bytes.length ? bytes[j + 2] : -1;
            out += chars.charAt(b1 >> 2);
            out += chars.charAt(((b1 & 3) << 4) | (b2 >= 0 ? b2 >> 4 : 0));
            out += b2 >= 0 ? chars.charAt(((b2 & 15) << 2) | (b3 >= 0 ? b3 >> 6 : 0)) : '=';
            out += b3 >= 0 ? chars.charAt(b3 & 63) : '=';
          }
          return out;
        };
      }
      if (typeof globalThis.atob !== 'function') {
        globalThis.atob = function(input) {
          var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
          var clean = String(input).replace(/[^A-Za-z0-9+\\/]/g, '');
          var out = '';
          for (var i = 0; i < clean.length; i += 4) {
            var a = chars.indexOf(clean[i]);
            var b = chars.indexOf(clean[i + 1]);
            var c = chars.indexOf(clean[i + 2]);
            var d = chars.indexOf(clean[i + 3]);
            out += String.fromCharCode((a << 2) | (b >> 4));
            if (c >= 0 && c < 64) out += String.fromCharCode(((b & 15) << 4) | (c >> 2));
            if (d >= 0 && d < 64) out += String.fromCharCode(((c & 3) << 6) | d);
          }
          return out;
        };
      }
      globalThis.__lx_wrap_headers__ = function(headers) {
        if (!headers || typeof headers !== 'object') return headers;
        try {
          return new Proxy(headers, {
            get: function(target, prop) {
              if (prop in target) return target[prop];
              var l = String(prop).toLowerCase();
              for (var k in target) {
                if (k.toLowerCase() === l) return target[k];
              }
              return undefined;
            },
            has: function(target, prop) {
              if (prop in target) return true;
              var l = String(prop).toLowerCase();
              for (var k in target) {
                if (k.toLowerCase() === l) return true;
              }
              return false;
            }
          });
        } catch (e) {
          return headers;
        }
      };
    ''');

    // ===== MD5 =====
    evalOrThrow('''
(function() {
  function safeAdd(x, y) {
    var lsw = (x & 0xffff) + (y & 0xffff)
    var msw = (x >> 16) + (y >> 16) + (lsw >> 16)
    return (msw << 16) | (lsw & 0xffff)
  }
  function bitRotateLeft(num, cnt) {
    return (num << cnt) | (num >>> (32 - cnt))
  }
  function md5cmn(q, a, b, x, s, t) {
    return safeAdd(bitRotateLeft(safeAdd(safeAdd(a, q), safeAdd(x, t)), s), b)
  }
  function md5ff(a, b, c, d, x, s, t) {
    return md5cmn((b & c) | (~b & d), a, b, x, s, t)
  }
  function md5gg(a, b, c, d, x, s, t) {
    return md5cmn((b & d) | (c & ~d), a, b, x, s, t)
  }
  function md5hh(a, b, c, d, x, s, t) {
    return md5cmn(b ^ c ^ d, a, b, x, s, t)
  }
  function md5ii(a, b, c, d, x, s, t) {
    return md5cmn(c ^ (b | ~d), a, b, x, s, t)
  }
  function binlMD5(x, len) {
    x[len >> 5] |= 0x80 << len % 32
    x[(((len + 64) >>> 9) << 4) + 14] = len
    var i, olda, oldb, oldc, oldd
    var a = 1732584193
    var b = -271733879
    var c = -1732584194
    var d = 271733878
    for (i = 0; i < x.length; i += 16) {
      olda = a; oldb = b; oldc = c; oldd = d
      a = md5ff(a, b, c, d, x[i], 7, -680876936)
      d = md5ff(d, a, b, c, x[i + 1], 12, -389564586)
      c = md5ff(c, d, a, b, x[i + 2], 17, 606105819)
      b = md5ff(b, c, d, a, x[i + 3], 22, -1044525330)
      a = md5ff(a, b, c, d, x[i + 4], 7, -176418897)
      d = md5ff(d, a, b, c, x[i + 5], 12, 1200080426)
      c = md5ff(c, d, a, b, x[i + 6], 17, -1473231341)
      b = md5ff(b, c, d, a, x[i + 7], 22, -45705983)
      a = md5ff(a, b, c, d, x[i + 8], 7, 1770035416)
      d = md5ff(d, a, b, c, x[i + 9], 12, -1958414417)
      c = md5ff(c, d, a, b, x[i + 10], 17, -42063)
      b = md5ff(b, c, d, a, x[i + 11], 22, -1990404162)
      a = md5ff(a, b, c, d, x[i + 12], 7, 1804603682)
      d = md5ff(d, a, b, c, x[i + 13], 12, -40341101)
      c = md5ff(c, d, a, b, x[i + 14], 17, -1502002290)
      b = md5ff(b, c, d, a, x[i + 15], 22, 1236535329)
      a = md5gg(a, b, c, d, x[i + 1], 5, -165796510)
      d = md5gg(d, a, b, c, x[i + 6], 9, -1069501632)
      c = md5gg(c, d, a, b, x[i + 11], 14, 643717713)
      b = md5gg(b, c, d, a, x[i], 20, -373897302)
      a = md5gg(a, b, c, d, x[i + 5], 5, -701558691)
      d = md5gg(d, a, b, c, x[i + 10], 9, 38016083)
      c = md5gg(c, d, a, b, x[i + 15], 14, -660478335)
      b = md5gg(b, c, d, a, x[i + 4], 20, -405537848)
      a = md5gg(a, b, c, d, x[i + 9], 5, 568446438)
      d = md5gg(d, a, b, c, x[i + 14], 9, -1019803690)
      c = md5gg(c, d, a, b, x[i + 3], 14, -187363961)
      b = md5gg(b, c, d, a, x[i + 8], 20, 1163531501)
      a = md5gg(a, b, c, d, x[i + 13], 5, -1444681467)
      d = md5gg(d, a, b, c, x[i + 2], 9, -51403784)
      c = md5gg(c, d, a, b, x[i + 7], 14, 1735328473)
      b = md5gg(b, c, d, a, x[i + 12], 20, -1926607734)
      a = md5hh(a, b, c, d, x[i + 5], 4, -378558)
      d = md5hh(d, a, b, c, x[i + 8], 11, -2022574463)
      c = md5hh(c, d, a, b, x[i + 11], 16, 1839030562)
      b = md5hh(b, c, d, a, x[i + 14], 23, -35309556)
      a = md5hh(a, b, c, d, x[i + 1], 4, -1530992060)
      d = md5hh(d, a, b, c, x[i + 4], 11, 1272893353)
      c = md5hh(c, d, a, b, x[i + 7], 16, -155497632)
      b = md5hh(b, c, d, a, x[i + 10], 23, -1094730640)
      a = md5hh(a, b, c, d, x[i + 13], 4, 681279174)
      d = md5hh(d, a, b, c, x[i], 11, -358537222)
      c = md5hh(c, d, a, b, x[i + 3], 16, -722521979)
      b = md5hh(b, c, d, a, x[i + 6], 23, 76029189)
      a = md5hh(a, b, c, d, x[i + 9], 4, -640364487)
      d = md5hh(d, a, b, c, x[i + 12], 11, -421815835)
      c = md5hh(c, d, a, b, x[i + 15], 16, 530742520)
      b = md5hh(b, c, d, a, x[i + 2], 23, -995338651)
      a = md5ii(a, b, c, d, x[i], 6, -198630844)
      d = md5ii(d, a, b, c, x[i + 7], 10, 1126891415)
      c = md5ii(c, d, a, b, x[i + 14], 15, -1416354905)
      b = md5ii(b, c, d, a, x[i + 5], 21, -57434055)
      a = md5ii(a, b, c, d, x[i + 12], 6, 1700485571)
      d = md5ii(d, a, b, c, x[i + 3], 10, -1894986606)
      c = md5ii(c, d, a, b, x[i + 10], 15, -1051523)
      b = md5ii(b, c, d, a, x[i + 1], 21, -2054922799)
      a = md5ii(a, b, c, d, x[i + 8], 6, 1873313359)
      d = md5ii(d, a, b, c, x[i + 15], 10, -30611744)
      c = md5ii(c, d, a, b, x[i + 6], 15, -1560198380)
      b = md5ii(b, c, d, a, x[i + 13], 21, 1309151649)
      a = md5ii(a, b, c, d, x[i + 4], 6, -145523070)
      d = md5ii(d, a, b, c, x[i + 11], 10, -1120210379)
      c = md5ii(c, d, a, b, x[i + 2], 15, 718787259)
      b = md5ii(b, c, d, a, x[i + 9], 21, -343485551)
      a = safeAdd(a, olda)
      b = safeAdd(b, oldb)
      c = safeAdd(c, oldc)
      d = safeAdd(d, oldd)
    }
    return [a, b, c, d]
  }
  function binl2rstr(input) {
    var i, output = ''
    var length32 = input.length * 32
    for (i = 0; i < length32; i += 8) {
      output += String.fromCharCode((input[i >> 5] >>> i % 32) & 0xff)
    }
    return output
  }
  function rstr2binl(input) {
    var i, output = []
    output[(input.length >> 2) - 1] = undefined
    for (i = 0; i < output.length; i += 1) { output[i] = 0 }
    var length8 = input.length * 8
    for (i = 0; i < length8; i += 8) {
      output[i >> 5] |= (input.charCodeAt(i / 8) & 0xff) << i % 32
    }
    return output
  }
  function rstrMD5(s) {
    return binl2rstr(binlMD5(rstr2binl(s), s.length * 8))
  }
  function rstr2hex(input) {
    var hexTab = '0123456789abcdef'
    var output = ''
    var x, i
    for (i = 0; i < input.length; i += 1) {
      x = input.charCodeAt(i)
      output += hexTab.charAt((x >>> 4) & 0x0f) + hexTab.charAt(x & 0x0f)
    }
    return output
  }
  function str2rstrUTF8(input) {
    var res = '';
    for (var n = 0; n < input.length; n++) {
      var c = input.charCodeAt(n);
      if (c < 128) {
        res += String.fromCharCode(c);
      } else if (c > 127 && c < 2048) {
        res += String.fromCharCode((c >> 6) | 192);
        res += String.fromCharCode((c & 63) | 128);
      } else if (c >= 0xD800 && c <= 0xDBFF && n + 1 < input.length) {
        var c2 = input.charCodeAt(n + 1);
        if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
          var cp = ((c - 0xD800) * 0x400) + (c2 - 0xDC00) + 0x10000;
          res += String.fromCharCode((cp >> 18) | 240);
          res += String.fromCharCode(((cp >> 12) & 63) | 128);
          res += String.fromCharCode(((cp >> 6) & 63) | 128);
          res += String.fromCharCode((cp & 63) | 128);
          n++;
          continue;
        }
      } else {
        res += String.fromCharCode((c >> 12) | 224);
        res += String.fromCharCode(((c >> 6) & 63) | 128);
        res += String.fromCharCode((c & 63) | 128);
      }
    }
    return res;
  }
  function rawMD5(s) { return rstrMD5(str2rstrUTF8(s)) }
  function hexMD5(s) { return rstr2hex(rawMD5(s)) }
  var md5 = function(string, key, raw) {
    if (!key) {
      if (!raw) return hexMD5(string)
      return rawMD5(string)
    }
    if (!raw) return hexMD5(string)
    return rawMD5(string)
  };
  globalThis.__lx_md5__ = md5;
})();

globalThis.__lx_utils__ = {
    crypto: {
      md5: function(str) {
        if (typeof str !== 'string') throw new Error('param required a string');
        return globalThis.__lx_md5__(str);
      },
      randomBytes: function(size) {
        var byteArray = new Uint8Array(size);
        for (var i = 0; i < size; i++) {
          byteArray[i] = Math.floor(Math.random() * 256);
        }
        return byteArray;
      }
    },
    buffer: {
      from: function(input, encoding) {
        if (typeof input === 'string') {
          switch (encoding) {
            case 'base64': {
              var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
              var bytes = [];
              for (var i = 0; i < input.length; i += 4) {
                var a = chars.indexOf(input[i]);
                var b = chars.indexOf(input[i + 1] || '=');
                var c = chars.indexOf(input[i + 2] || '=');
                var d = chars.indexOf(input[i + 3] || '=');
                bytes.push((a << 2) | (b >> 4));
                if (c !== -1) bytes.push(((b & 15) << 4) | (c >> 2));
                if (d !== -1) bytes.push(((c & 3) << 6) | d);
              }
              return bytes;
            }
            case 'hex':
              var hexBytes = [];
              for (var i = 0; i < input.length; i += 2)
                hexBytes.push(parseInt(input.substring(i, i + 2), 16));
              return hexBytes;
            default:
              var utf8Bytes = [];
              for (var i = 0; i < input.length; i++) {
                var c = input.charCodeAt(i);
                if (c < 128) {
                  utf8Bytes.push(c);
                } else if (c < 2048) {
                  utf8Bytes.push((c >> 6) | 192);
                  utf8Bytes.push((c & 63) | 128);
                } else {
                  utf8Bytes.push((c >> 12) | 224);
                  utf8Bytes.push(((c >> 6) & 63) | 128);
                  utf8Bytes.push((c & 63) | 128);
                }
              }
              return utf8Bytes;
          }
        } else if (Array.isArray(input)) {
          return input;
        }
        throw new Error('Unsupported input type');
      },
      bufToString: function(buf, format) {
        if (Array.isArray(buf)) {
          switch (format) {
            case 'hex':
              var hex = '';
              for (var i = 0; i < buf.length; i++)
                hex += (buf[i] & 0xff).toString(16).padStart(2, '0');
              return hex;
            case 'base64': {
              var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
              var result = '';
              for (var i = 0; i < buf.length; i += 3) {
                var a = buf[i], b = buf[i + 1] || 0, c = buf[i + 2] || 0;
                result += chars[a >> 2] + chars[((a & 3) << 4) | (b >> 4)];
                if (i + 1 < buf.length) result += chars[((b & 15) << 2) | (c >> 6)];
                else result += '=';
                if (i + 2 < buf.length) result += chars[c & 63];
                else result += '=';
              }
              return result;
            }
            case 'utf8':
            case 'utf-8':
            default:
              var result = '';
              var i = 0;
              while (i < buf.length) {
                var byte = buf[i];
                if (byte < 128) {
                  result += String.fromCharCode(byte);
                  i++;
                } else if (byte >= 192 && byte < 224) {
                  result += String.fromCharCode(((byte & 31) << 6) | (buf[i + 1] & 63));
                  i += 2;
                } else {
                  result += String.fromCharCode(((byte & 15) << 12) | ((buf[i + 1] & 63) << 6) | (buf[i + 2] & 63));
                  i += 3;
                }
              }
              return result;
          }
        }
        throw new Error('Input is not a valid buffer');
      }
    },
    string: {
      match: function(str, pattern) {
        try {
          var re = new RegExp(pattern);
          var result = str.match(re);
          return result ? result[0] : null;
        } catch(e) {
          return null;
        }
      }
    }
  };
  if (typeof globalThis.Buffer === 'undefined') {
    globalThis.Buffer = {
      from: function(input, encoding) { return globalThis.__lx_utils__.buffer.from(input, encoding); },
      isBuffer: function(obj) { return obj instanceof Uint8Array || Array.isArray(obj); }
    };
    globalThis.Buffer.prototype = {
      toString: function(format) { return globalThis.__lx_utils__.buffer.bufToString(this, format); }
    };
  }
    ''', 'md5');

    // ===== lx 对象 =====
    evalOrThrow('''
      globalThis.lx = {
        EVENT_NAMES: {
          request: 'request',
          response: 'response',
          inited: 'inited',
          updateAlert: 'updateAlert'
        },
        version: '2.0.0',
        currentScriptInfo: {
          name: ${jsonEncode(script.name)},
          version: ${jsonEncode(script.version)},
          author: ${jsonEncode(script.author)},
          description: ${jsonEncode(script.description)},
          homepage: ${jsonEncode(script.homepage)},
          rawScript: ${jsonEncode(rawScript)}
        },
        env: '',
        utils: globalThis.__lx_utils__,
        request: function(url, options, callback) {
          if (typeof options === 'function') {
            callback = options;
            options = {};
          }
          options = options || {};
          var settled = false;
          var requestInfo = { aborted: false };
          var doRequest = function(resolve, reject) {
            globalThis.__lx_request_queue__.push({
              url: url, options: options, requestInfo: requestInfo,
              hasCallback: false,
              resolve: function(resp) {
                if (settled || requestInfo.aborted) return; settled = true;
                if (resolve) resolve(resp);
              },
              reject: function(err) {
                if (settled || requestInfo.aborted) return; settled = true;
                if (reject) reject(err);
              }
            });
          };
          if (typeof callback === 'function') {
            doRequest(function(resp) { callback(null, resp, resp ? resp.body : null); },
              function(err) { callback(err, null, null); });
            return function() {
              requestInfo.aborted = true;
            };
          }
          return new Promise(function(resolve, reject) { doRequest(resolve, reject); });
        },
        on: function(event, handler) {
          if (event !== 'request') {
            return Promise.reject(new Error('The event is not supported: ' + event));
          }
          globalThis.__lx_handlers__[event] = handler;
          return Promise.resolve();
        },
        send: function(event, data) {
          return new Promise(function(resolve, reject) {
            if (event === 'inited' || event === 'init') {
              if (globalThis.__lx_inited__) return reject(new Error('Script is inited'));
              globalThis.__lx_inited__ = true;
              try {
                globalThis.__lx_init_data__ = JSON.stringify(data);
                resolve();
              } catch (e) { reject(e); }
            } else if (event === 'updateAlert') {
              try {
                if (!data || typeof data !== 'object' || !data.log) throw new Error('log is required.');
                globalThis.__lx_update_alert__ = JSON.stringify({ log: String(data.log).substring(0, 1024), updateUrl: data.updateUrl || null });
                resolve();
              } catch (e) { reject(e); }
            } else {
              reject(new Error('The event is not supported: ' + event));
            }
          });
        }
      };
    ''', 'lx');
  }

  // ==================== HTTP 请求处理 ====================

  /// 处理队列中的 HTTP 请求
  Future<void> _processPendingRequests(
      [JavascriptRuntime? runtime, int maxIterations = 100]) async {
    final rt = runtime ?? _jsRuntime!;
    final items = <Map<String, dynamic>>[];

    // 1) 快照队列
    for (var i = 0; i < maxIterations; i++) {
      final metaResult = rt.evaluate('''
          (function() {
            var item = globalThis.__lx_request_queue__[$i];
            if (!item) return null;
            return JSON.stringify({idx: $i, url: item.url, options: item.options, aborted: item.requestInfo ? item.requestInfo.aborted : false});
          })()
        ''');
      if (metaResult.isError ||
          metaResult.stringResult == 'null' ||
          metaResult.stringResult.isEmpty) {
        break;
      }
      final requestData = jsonDecode(metaResult.stringResult);
      final url = requestData['url']?.toString() ?? '';
      final aborted = requestData['aborted'] == true;
      if (aborted) {
        LxLogger.warn('请求已取消（脚本 abort）: $url');
        rt.evaluate('''
            (function() {
              var item = globalThis.__lx_request_queue__.shift();
              if (item && item.reject) { try { item.reject(new Error('request aborted')); } catch(_) {} }
            })()
          ''');
        i--;
        continue;
      }
      final options = requestData['options'] as Map<String, dynamic>? ?? {};
      items.add({...requestData, 'options': options});
      if (items.length >= 20) break;
      if (items.length % 5 == 0) await Future.delayed(Duration.zero);
    }
    if (items.isEmpty) return;

    LxLogger.info('并行处理 ${items.length} 个请求');

    _checkPreempted();

    // 2) 并行发出
    final responses = await Future.wait(items.map((item) async {
      try {
        final resp = await _makeHttpRequest(
            item['url']?.toString() ?? '', item['options'] as Map<String, dynamic>);
        return {'item': item, 'resp': resp};
      } catch (e) {
        LxLogger.warn('请求失败: ${item['url']} - $e');
        return {'item': item, 'resp': null};
      }
    }));

    // 3) 逐个交付
    for (final r in responses) {
      final item = r['item'] as Map<String, dynamic>;
      final resp = r['resp'] as Map<String, dynamic>?;
      if (resp == null) {
        final safeErr = jsonEncode('request failed');
        rt.evaluate('globalThis.__lx_last_request_error__ = $safeErr');
        rt.evaluate('''
          (function() {
            var item = globalThis.__lx_request_queue__.shift();
            var msg = globalThis.__lx_last_request_error__;
            globalThis.__lx_last_request_error__ = null;
            if (item && item.reject) {
              try { item.reject(new Error(msg)); } catch(_) {}
            }
          })()
        ''');
        continue;
      }
      final fullResponse = {
        'statusCode': resp['statusCode'],
        'statusMessage': resp['statusMessage'],
        'headers': resp['headers'],
        'body': resp['body'],
        'ok': resp['ok'],
        'url': resp['url'],
      };
      final bodyStr = jsonEncode(resp['body']);
      LxLogger.info(
          '响应 ${resp['statusCode']}: ${_truncate(bodyStr, 200)}');

      final responseJson = jsonEncode(fullResponse);
      final safeJson = responseJson
          .codeUnits
          .map((c) => '\\u${c.toRadixString(16).padLeft(4, '0')}')
          .join('');
      rt.evaluate('globalThis.__lx_callback_response__ = "$safeJson"');
      rt.evaluate('''
          (function() {
            var item = globalThis.__lx_request_queue__.shift();
            if (!item || !item.resolve) return;
            var raw = globalThis.__lx_callback_response__;
            globalThis.__lx_callback_response__ = null;
            try {
              var resp = JSON.parse(raw);
              resp.headers = __lx_wrap_headers__(resp.headers);
              item.resolve(resp);
            } catch(e) {
              if (item.reject) { try { item.reject(new Error(e && e.message ? e.message : String(e))); } catch(_) {} }
            }
          })()
        ''');

      final errCheck = rt.evaluate('globalThis.__lx_last_error__');
      if (!errCheck.isError &&
          errCheck.stringResult != 'null' &&
          errCheck.stringResult.isNotEmpty) {
        LxLogger.error('脚本回调错误: ${errCheck.stringResult}');
        rt.evaluate('globalThis.__lx_last_error__ = null');
      }
      await Future.delayed(Duration.zero);
    }
  }

  // ==================== HTTP 请求实现（dio） ====================

  /// 对齐 lx-music-mobile request.js 的请求语义
  /// - 默认 UA / Accept，脚本显式传入优先
  /// - form → x-www-form-urlencoded
  /// - formData → multipart/form-data
  /// - body 为对象且未指定 Content-Type → JSON
  /// - 超时默认 13s，脚本传入时上限 60s
  /// - binary → body 返回字节数组
  ///
  /// 返回结构与 package:http 版本完全一致，JS 脚本无感知
  Future<Map<String, dynamic>> _makeHttpRequest(
      String url, Map<String, dynamic> options) async {
    try {
      final method = (options['method']?.toString() ?? 'GET').toUpperCase();
      final scriptHeaders = <String, String>{};
      final rawHeaders = options['headers'];
      if (rawHeaders is Map) {
        rawHeaders.forEach((k, v) {
          scriptHeaders[k.toString()] = v.toString();
        });
      }

      if (url.startsWith('/')) {
        url = 'https://flower.tempmusics.tk/v1$url';
      }

      LxLogger.info('HTTP $method $url');

      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36',
        'Accept': 'application/json',
        ...scriptHeaders,
      };

      var timeoutMs = 13000;
      final scriptTimeout = options['timeout'];
      if (scriptTimeout is num && scriptTimeout > 0) {
        timeoutMs = scriptTimeout > 60000 ? 60000 : scriptTimeout.toInt();
      }

      final form = options['form'];
      final formData = options['formData'];
      final body = options['body'];
      final binary = options['binary'] == true;

      Response<dynamic> response;
      final dioOptions = Options(
        method: method,
        responseType: binary ? ResponseType.bytes : ResponseType.plain,
        headers: headers,
        sendTimeout: Duration(milliseconds: timeoutMs),
        receiveTimeout: Duration(milliseconds: timeoutMs),
        validateStatus: (_) => true,
        followRedirects: true,
      );

      if (formData is Map && formData.isNotEmpty) {
        // multipart/form-data
        final fd = FormData();
        formData.forEach((k, v) {
          if (v is MultipartFile) {
            fd.files.add(MapEntry(k.toString(), v));
          } else {
            fd.fields.add(MapEntry(k.toString(), v?.toString() ?? ''));
          }
        });
        response = await _dio.request<dynamic>(
          url,
          data: fd,
          options: dioOptions,
        );
      } else if (form is Map && form.isNotEmpty) {
        // application/x-www-form-urlencoded（逐字段 encodeURIComponent）
        headers.putIfAbsent(
            'Content-Type', () => 'application/x-www-form-urlencoded');
        final encoded = form.entries
            .map((e) =>
                '${Uri.encodeComponent(e.key.toString())}=${Uri.encodeComponent(e.value?.toString() ?? '')}')
            .join('&');
        response = await _dio.request<dynamic>(
          url,
          data: encoded,
          options: dioOptions.copyWith(headers: headers),
        );
      } else if (body != null) {
        dynamic reqData;
        if (body is String) {
          reqData = body;
        } else if (body is List<int>) {
          reqData = Uint8List.fromList(body);
        } else {
          headers.putIfAbsent('Content-Type', () => 'application/json');
          reqData = jsonEncode(body);
        }
        response = await _dio.request<dynamic>(
          url,
          data: reqData,
          options: dioOptions.copyWith(headers: headers),
        );
      } else {
        response = await _dio.request<dynamic>(
          url,
          options: dioOptions,
        );
      }

      final statusCode = response.statusCode ?? 0;
      dynamic parsedBody;
      if (binary) {
        final d = response.data;
        if (d is List<int>) {
          parsedBody = d;
        } else if (d is Uint8List) {
          parsedBody = d.toList();
        } else {
          parsedBody = <int>[];
        }
      } else {
        final responseBody = response.data?.toString() ?? '';
        try {
          parsedBody = jsonDecode(responseBody);
        } catch (_) {
          parsedBody = responseBody;
        }
      }

      // headers 转 Map<String, String>
      final respHeaders = <String, String>{};
      response.headers.forEach((k, v) {
        respHeaders[k] = v.join(', ');
      });

      return {
        'statusCode': statusCode,
        'statusMessage': response.statusMessage ??
            (statusCode == 200 ? 'OK' : 'Error'),
        'headers': respHeaders,
        'body': parsedBody,
        'ok': statusCode >= 200 && statusCode < 300,
        'url': url,
      };
    } catch (e) {
      // 网络错误抛给脚本回调
      rethrow;
    }
  }

  // ==================== 音源注册解析 ====================

  void _parseInitData(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      if (data is Map) {
        final sourcesData = data['sources'];
        if (sourcesData is Map && sourcesData.isNotEmpty) {
          _sources = {};
          sourcesData.forEach((key, value) {
            if (value is Map) {
              _sources[key.toString()] = LxScriptSource(
                type: value['type']?.toString() ?? 'music',
                actions: List<String>.from(value['actions'] ?? const []),
                qualitys: List<String>.from(value['qualitys'] ?? const []),
              );
            }
          });
          LxLogger.info('注册音源: ${_sources.keys.join(', ')} (共 ${_sources.length} 个)');
        } else {
          LxLogger.warn('init 数据中 sources 为空或非 Map: $sourcesData');
        }
        final updateUrl = data['updateUrl'];
        if (updateUrl != null) {
          _updateUrl = updateUrl.toString();
        }
      } else {
        LxLogger.warn('init 数据顶层非 Map: ${_truncate(jsonStr, 200)}');
      }
    } catch (e) {
      LxLogger.error('解析初始化数据错误: $e');
    }
  }

  // ==================== 取播放 URL ====================

  Future<String?> getMusicUrl({
    required String apiId,
    required dynamic music,
    String quality = '320k',
  }) async {
    try {
      return await _withJsLock(
        () => _getMusicUrlLocked(apiId, music, quality),
        priority: true,
      );
    } on TimeoutException {
      LxLogger.warn('获取播放地址超时');
      return null;
    }
  }

  Future<String?> getMusicUrlParallel({
    required String apiId,
    required dynamic music,
    String quality = '320k',
  }) async {
    final script = _scripts[apiId];
    if (script == null) return null;
    if (!_scriptInitialized) return null;

    JavascriptRuntime? tempRuntime;
    try {
      return await _doGetMusicUrlParallel(script, music, quality).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          LxLogger.warn('getMusicUrlParallel 整体超时 15s');
          try {
            tempRuntime?.dispose();
          } catch (_) {}
          return null;
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _doGetMusicUrlParallel(
      LxScript script, dynamic music, String quality) async {
    JavascriptRuntime? tempRuntime;
    try {
      tempRuntime = getJavascriptRuntime();
      _setupLxApi(script, tempRuntime);
      final execResult = tempRuntime.evaluate(script.content);
      if (execResult.isError) {
        LxLogger.error('临时运行时脚本执行失败: ${execResult.stringResult}');
        return null;
      }
      final initOk = await _waitForInitOnRuntime(tempRuntime);
      if (!initOk) return null;

      final url = await _fetchUrlOnRuntime(tempRuntime, music, quality);
      return url;
    } catch (e) {
      LxLogger.warn('并行取 URL 异常: $e');
      return null;
    } finally {
      tempRuntime?.dispose();
    }
  }

  Future<bool> _waitForInitOnRuntime(JavascriptRuntime runtime) async {
    var initData = runtime.evaluate('globalThis.__lx_init_data__');
    if (!initData.isError &&
        initData.stringResult != 'null' &&
        initData.stringResult.isNotEmpty) {
      return true;
    }
    for (var i = 0; i < 40; i++) {
      await _processPendingRequests(runtime, 50);
      for (var j = 0; j < 20; j++) {
        runtime.executePendingJob();
      }
      await Future.delayed(Duration.zero);
      initData = runtime.evaluate('globalThis.__lx_init_data__');
      if (!initData.isError &&
          initData.stringResult != 'null' &&
          initData.stringResult.isNotEmpty) {
        return true;
      }
      final qLen = runtime.evaluate('globalThis.__lx_request_queue__.length');
      if (qLen.isError || qLen.stringResult == '0') break;
    }
    return false;
  }

  Future<String?> _fetchUrlOnRuntime(
      JavascriptRuntime runtime, dynamic music, String quality) async {
    final musicInfo = _buildMusicInfoMap(music);

    runtime.evaluate('globalThis.__lx_result__ = null');
    runtime.evaluate('globalThis.__lx_request_queue__ = []');

    final jsCode = _buildRequestJsCode(musicInfo, quality, music.source);

    final result = runtime.evaluate(jsCode);
    if (result.isError) return null;

    final resultStr = result.stringResult;
    if (resultStr == 'promise' || resultStr == '"promise"') {
      for (var i = 0; i < 20; i++) {
        await _processPendingRequests(runtime, 50);
        for (var j = 0; j < 20; j++) {
          runtime.executePendingJob();
        }
        await Future.delayed(Duration.zero);
        final resultData = runtime.evaluate('globalThis.__lx_result__');
        if (!resultData.isError &&
            resultData.stringResult != 'null' &&
            resultData.stringResult.isNotEmpty) {
          return _extractUrlFromResult(resultData.stringResult);
        }
        final qLen = runtime.evaluate('globalThis.__lx_request_queue__.length');
        if (qLen.isError || qLen.stringResult == '0') break;
      }
      return null;
    }
    return _extractUrlFromResult(resultStr);
  }

  Future<String?> _getMusicUrlLocked(
      String apiId, dynamic music, String quality) async {
    try {
      final script = _scripts[apiId];
      if (script == null) {
        LxLogger.error('脚本不存在: $apiId');
        return null;
      }
      if (_jsRuntime == null || _currentScript?.id != apiId) {
        await _initJsRuntime(script);
      }
      if (!_scriptInitialized) {
        await _waitForScriptInit();
      }
      if (!_scriptInitialized) {
        LxLogger.error('脚本未初始化');
        return null;
      }

      final musicInfo = _buildMusicInfoMap(music);

      _jsRuntime!.evaluate('globalThis.__lx_result__ = null');
      _jsRuntime!.evaluate('globalThis.__lx_request_queue__ = []');

      final jsCode = _buildRequestJsCode(musicInfo, quality, music.source);

      final result = _jsRuntime!.evaluate(jsCode);
      if (result.isError) {
        LxLogger.error('JS 执行错误: ${result.stringResult}');
        return null;
      }

      final resultStr = result.stringResult;
      if (resultStr == '"promise"' || resultStr == 'promise') {
        var errored = false;
        for (var i = 0; i < 30; i++) {
          await _processPendingRequests(null, 50);
          for (var j = 0; j < 20; j++) {
            _jsRuntime!.executePendingJob();
          }
          await Future.delayed(Duration.zero);
          final resultData = _jsRuntime!.evaluate('globalThis.__lx_result__');
          if (!resultData.isError &&
              resultData.stringResult != 'null' &&
              resultData.stringResult.isNotEmpty) {
            final url = _extractUrlFromResult(resultData.stringResult);
            if (url != null) {
              LxLogger.info('从用户 API 获取 URL: $url');
              return url;
            }
            errored = true;
            break;
          }
          final qLen = _jsRuntime!.evaluate('globalThis.__lx_request_queue__.length');
          if (qLen.isError || qLen.stringResult == '0') break;
        }
        if (!errored) {
          final resultData = _jsRuntime!.evaluate('globalThis.__lx_result__');
          if (!resultData.isError &&
              resultData.stringResult != 'null' &&
              resultData.stringResult.isNotEmpty) {
            final url = _extractUrlFromResult(resultData.stringResult);
            if (url != null) {
              LxLogger.info('从用户 API 获取 URL: $url');
              return url;
            }
          } else {
            LxLogger.warn('无结果数据 (stringResult=${resultData.stringResult})');
          }
        }
      } else {
        final url = _extractUrlFromResult(resultStr);
        if (url != null) {
          LxLogger.info('从用户 API 获取 URL (同步): $url');
          return url;
        }
      }
      return null;
    } catch (e) {
      LxLogger.error('获取播放地址错误: $e');
      return null;
    }
  }

  // ==================== 取歌词 ====================

  Future<Map<String, String?>?> getLyric({
    required String apiId,
    required dynamic music,
  }) async {
    try {
      return await _withJsLock(
        () => _getLyricLocked(apiId, music),
        priority: false,
      );
    } on TimeoutException {
      LxLogger.warn('获取歌词超时');
      return null;
    }
  }

  Future<Map<String, String?>?> _getLyricLocked(
      String apiId, dynamic music) async {
    try {
      final script = _scripts[apiId];
      if (script == null) {
        LxLogger.error('脚本不存在: $apiId');
        return null;
      }
      if (_jsRuntime == null || _currentScript?.id != apiId) {
        await _initJsRuntime(script);
      }
      if (!_scriptInitialized) {
        await _waitForScriptInit();
      }
      if (!_scriptInitialized) {
        LxLogger.error('脚本未初始化');
        return null;
      }

      final musicInfo = _buildMusicInfoMap(music);

      _jsRuntime!.evaluate('globalThis.__lx_result__ = null');
      _jsRuntime!.evaluate('globalThis.__lx_request_queue__ = []');

      final jsCode = '''
        (function() {
          var handler = globalThis.__lx_handlers__['request'];
          if (!handler) {
            return JSON.stringify({error: 'No handler registered'});
          }
          try {
            var __lx_info__ = {
                musicInfo: ${jsonEncode(musicInfo)}
              };
            var result = handler({
              source: ${jsonEncode(music.source ?? 'kw')},
              action: 'lyric',
              info: __lx_info__,
              params: __lx_info__
            });
            if (result && typeof result.then === 'function') {
              result.then(function(data) {
                globalThis.__lx_result__ = JSON.stringify(data === undefined ? null : data);
              }).catch(function(err) {
                globalThis.__lx_result__ = JSON.stringify({error: err.message || err.toString()});
              });
              return 'promise';
            }
            if (result && typeof result === 'object') {
              return JSON.stringify(result);
            }
            return JSON.stringify({error: 'Invalid result'});
          } catch (e) {
            return JSON.stringify({error: e.message || e.toString()});
          }
        })()
      ''';

      final result = _jsRuntime!.evaluate(jsCode);
      if (result.isError) {
        LxLogger.error('JS 执行错误: ${result.stringResult}');
        return null;
      }

      final resultStr = result.stringResult;
      if (resultStr == '"promise"' || resultStr == 'promise') {
        for (var i = 0; i < 30; i++) {
          await _processPendingRequests(null, 50);
          for (var j = 0; j < 20; j++) {
            _jsRuntime!.executePendingJob();
          }
          await Future.delayed(Duration.zero);
          final resultData = _jsRuntime!.evaluate('globalThis.__lx_result__');
          if (!resultData.isError &&
              resultData.stringResult != 'null' &&
              resultData.stringResult.isNotEmpty) {
            return _parseLyricResult(resultData.stringResult);
          }
          final qLen = _jsRuntime!.evaluate('globalThis.__lx_request_queue__.length');
          if (qLen.isError || qLen.stringResult == '0') break;
        }
      } else {
        return _parseLyricResult(resultStr);
      }
      return null;
    } catch (e) {
      LxLogger.error('获取歌词错误: $e');
      return null;
    }
  }

  Map<String, String?>? _parseLyricResult(String resultStr) {
    try {
      final decoded = jsonDecode(resultStr);
      if (decoded is Map) {
        if (decoded['error'] != null) {
          LxLogger.error('脚本错误: ${decoded['error']}');
          return null;
        }
        String? lyric;
        String? tlyric;
        if (decoded['lyric'] is String) {
          lyric = decoded['lyric'] as String;
        } else if (decoded['data'] is String) {
          lyric = decoded['data'] as String;
        } else if (decoded['data'] is Map && decoded['data']['lyric'] is String) {
          lyric = decoded['data']['lyric'] as String;
        }
        if (decoded['tlyric'] is String) {
          tlyric = decoded['tlyric'] as String;
        } else if (decoded['data'] is Map && decoded['data']['tlyric'] is String) {
          tlyric = decoded['data']['tlyric'] as String;
        }
        if (lyric != null && lyric.isNotEmpty) {
          LxLogger.info('获取歌词成功');
          return {'lyric': lyric, 'tlyric': tlyric};
        }
      } else if (decoded is String && decoded.isNotEmpty) {
        LxLogger.info('获取歌词成功（纯文本）');
        return {'lyric': decoded, 'tlyric': null};
      }
    } catch (e) {
      LxLogger.error('歌词解析错误: $e');
    }
    return null;
  }

  // ==================== 工具方法 ====================

  Map<String, dynamic> _buildMusicInfoMap(dynamic music) {
    return {
      'id': music.id,
      'name': music.name,
      'singer': music.singer,
      'album': music.album,
      'source': music.source,
      'songId': music.songId,
      'songmid': music.songmid,
      'strMediaMid': music.strMediaMid,
      'copyrightId': music.copyrightId,
      'hash': music.hash,
    };
  }

  String _buildRequestJsCode(
      Map<String, dynamic> musicInfo, String quality, String? source) {
    return '''
        (function() {
          var handler = globalThis.__lx_handlers__['request'];
          if (!handler) {
            return JSON.stringify({error: 'No handler registered'});
          }
          try {
            var called = false;
            var __lx_info__ = {
                musicInfo: ${jsonEncode(musicInfo)},
                type: ${jsonEncode(quality)}
              };
            var result = handler({
              source: ${jsonEncode(source ?? 'kw')},
              action: 'musicUrl',
              info: __lx_info__,
              params: __lx_info__
            }, function(err, data) {
              called = true;
              if (err) {
                globalThis.__lx_result__ = JSON.stringify({error: err.message || String(err)});
              } else {
                globalThis.__lx_result__ = JSON.stringify(data === undefined ? null : data);
              }
            });
            if (result && typeof result.then === 'function') {
              result.then(function(data) {
                globalThis.__lx_result__ = JSON.stringify(data === undefined ? null : data);
              }).catch(function(err) {
                globalThis.__lx_result__ = JSON.stringify({error: err.message || err.toString()});
              });
              return 'promise';
            }
            if (result && typeof result === 'object') {
              return JSON.stringify(result);
            }
            if (called) {
              return 'promise';
            }
            return JSON.stringify({error: 'Invalid result'});
          } catch (e) {
            return JSON.stringify({error: e.message || e.toString()});
          }
        })()
      ''';
  }

  String? _extractUrlFromResult(String resultStr) {
    lastScriptError = null;
    try {
      var raw = resultStr.trim();
      if (raw.startsWith('"') && raw.endsWith('"')) {
        raw = raw.substring(1, raw.length - 1);
      }
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        LxLogger.info('解析到 URL(裸串): $raw');
        return raw;
      }

      final decoded = jsonDecode(resultStr);
      if (decoded is String) {
        final url = decoded.trim();
        if (url.startsWith('http://') || url.startsWith('https://')) {
          LxLogger.info('解析到 URL: $url');
          return url;
        }
        return null;
      }
      if (decoded is Map) {
        if (decoded['error'] != null) {
          final errMsg = decoded['error'].toString();
          LxLogger.error('脚本错误: $errMsg');
          lastScriptError = errMsg;
          return null;
        }
        final candidates = [
          decoded['url'],
          decoded['data'],
          decoded['data']?['url']
        ];
        for (final c in candidates) {
          if (c is String &&
              (c.startsWith('http://') || c.startsWith('https://'))) {
            LxLogger.info('解析到 URL: $c');
            return c;
          }
          if (c is Map) {
            final nestedUrl = c['url'];
            if (nestedUrl is String &&
                (nestedUrl.startsWith('http://') ||
                    nestedUrl.startsWith('https://'))) {
              LxLogger.info('解析到嵌套 URL: $nestedUrl');
              return nestedUrl;
            }
          }
        }
        LxLogger.warn('结果中未找到有效 URL: $resultStr');
        return null;
      }
    } catch (e) {
      LxLogger.error('结果解析错误: $e');
    }
    return null;
  }

  void dispose() {
    _jsRuntime?.dispose();
    _stateController.close();
    _eventController.close();
  }
}

// ==================== 状态/事件枚举 ====================

enum LxEngineState {
  idle,
  loading,
  loaded,
  active,
  error,
}

enum LxEngineEventType {
  scriptImported,
  scriptActivated,
  scriptDeactivated,
  scriptRemoved,
  scriptError,
}

class LxEngineEvent {
  final LxEngineEventType type;
  final dynamic data;
  LxEngineEvent(this.type, [this.data]);

  static LxEngineEvent scriptImported(LxScript script) =>
      LxEngineEvent(LxEngineEventType.scriptImported, script);
  static LxEngineEvent scriptActivated(LxScript script) =>
      LxEngineEvent(LxEngineEventType.scriptActivated, script);
  static LxEngineEvent scriptDeactivated() =>
      LxEngineEvent(LxEngineEventType.scriptDeactivated);
  static LxEngineEvent scriptError(LxScript? script, String? message) =>
      LxEngineEvent(
          LxEngineEventType.scriptError, {'script': script, 'message': message});
  static LxEngineEvent scriptRemoved(String scriptId) =>
      LxEngineEvent(LxEngineEventType.scriptRemoved, scriptId);
}