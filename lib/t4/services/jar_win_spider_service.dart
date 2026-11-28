import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/http/init.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/jar_class_profile.dart';
import 'package:yuanying/t4/services/i_jar_spider_service.dart';
import 'package:yuanying/utils/business_exception.dart';

/// Windows JAR runtime backed by jar-win's bundled JRE and SpiderHost.
class JarWinSpiderService implements IJarSpiderService {
  String? _currentKey;
  String? _api;
  dynamic _ext;
  String _jarSource = '';
  String _configBaseUrl = '';
  String? _readyKey;
  _JarWinHostClient? _client;
  bool _needShellPayloadCheck = false;
  bool _usingNativeExtraction = false;
  bool _usingEmbeddedNativeRuntime = false;
  bool _preferGuardRetry = false;
  bool _guardRuntimeHint = false;

  @override
  String? get currentKey => _currentKey;

  @override
  void setBaseUrl(String url) {
    _api = url;
  }

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    _api = apiUrl;
    _currentKey = siteKey;
    _ext = ext;
    _readyKey = null;
    _needShellPayloadCheck = false;
    _usingNativeExtraction = false;
    _usingEmbeddedNativeRuntime = false;
    _preferGuardRetry = false;
    _guardRuntimeHint = false;
  }

  @override
  void configureJarSource(String source, {String configBaseUrl = ''}) {
    final next = source.trim();
    if (_jarSource != next || _configBaseUrl != configBaseUrl) {
      _readyKey = null;
      _client = null;
      _needShellPayloadCheck = false;
      _usingNativeExtraction = false;
      _usingEmbeddedNativeRuntime = false;
      _preferGuardRetry = false;
      _guardRuntimeHint = false;
    }
    _jarSource = next;
    _configBaseUrl = configBaseUrl;
  }

  @override
  Future<void> ensureReady({bool forceGuardRetry = false}) async {
    final guardPlugin = InstallManager.instance.findInstalled('jar-guard');
    final plugin = _requireEnabledPlugin();
    final sourceJarPath = await _resolveJarPath();
    final sourceStat = File(sourceJarPath).statSync();
    final guardState = guardPlugin == null
        ? 'none'
        : '${guardPlugin.version}|${guardPlugin.enabled}|'
              '${guardPlugin.installPath}';
    final expectedKey =
        '${plugin.version}|${plugin.installPath}|$sourceJarPath|'
        '${sourceStat.size}|${sourceStat.modified.millisecondsSinceEpoch}|'
        '${_currentKey ?? ''}|${_api ?? ''}|${_extText(_ext)}|'
        '$guardState|$forceGuardRetry';
    if (!_needShellPayloadCheck &&
        _readyKey == expectedKey &&
        _client?.isAlive == true &&
        File(_client!.jarPath).existsSync()) {
      return;
    }

    final preparedJar = await _JarWinPreprocessor.instance.prepare(
      plugin: plugin,
      sourceJarPath: sourceJarPath,
      api: _api ?? '',
      allowGuardExtraction: forceGuardRetry,
    );
    final needsGuardRuntime = preparedJar.isShell && !preparedJar.useShellShim;
    if (needsGuardRuntime && guardPlugin?.enabled != true) {
      _preferGuardRetry = false;
      throw _GuardUnavailableException(_guardRetryHint(guardPlugin));
    }
    if (needsGuardRuntime) _preferGuardRetry = true;
    _guardRuntimeHint = preparedJar.requiresGuardRuntime;
    _needShellPayloadCheck = preparedJar.isShell && !preparedJar.useShellShim;
    _usingNativeExtraction = _needShellPayloadCheck;
    _usingEmbeddedNativeRuntime =
        _usingNativeExtraction && preparedJar.usesEmbeddedNativeRuntime;
    _client = await _JarWinHostPool.instance.acquire(plugin, preparedJar);
    _readyKey = expectedKey;
  }

  @override
  Future<void> release() async {
    _readyKey = null;
    _client = null;
    _needShellPayloadCheck = false;
    _usingNativeExtraction = false;
    _usingEmbeddedNativeRuntime = false;
    _preferGuardRetry = false;
    _guardRuntimeHint = false;
  }

  static Future<void> shutdownAll() => _JarWinHostPool.instance.shutdownAll();

  InstalledPlugin _requireEnabledPlugin() {
    final plugin = InstallManager.instance.findInstalled('jar-win');
    if (plugin == null) {
      throw const BusinessException('请先在插件中心安装 Windows JAR 爬虫运行时');
    }
    if (!plugin.enabled) {
      throw const BusinessException('Windows JAR 爬虫运行时已关闭');
    }
    return plugin;
  }

  /// JAR 运行采用 fail-open 策略：首次请求始终使用普通模式。只有普通模式
  /// 真实失败后才尝试 guard 模式，避免仅凭类名或包内资源误判。
  Future<dynamic> _call(
    String method,
    List<String> args, {
    bool allowShellRetry = true,
  }) async {
    try {
      return await _callWithCurrentRuntime(
        method,
        args,
        allowShellRetry: allowShellRetry,
      );
    } on _GuardUnavailableException {
      rethrow;
    } catch (normalError, normalStack) {
      if (_preferGuardRetry) {
        Error.throwWithStackTrace(normalError, normalStack);
      }
      final guardPlugin = InstallManager.instance.findInstalled('jar-guard');
      if (_guardRuntimeHint && guardPlugin?.enabled != true) {
        throw BusinessException(
          '${_guardRetryHint(guardPlugin)}\n原始错误：$normalError',
        );
      }

      _preferGuardRetry = true;
      _needShellPayloadCheck = false;
      _client = null;
      _readyKey = null;

      try {
        return await _callWithCurrentRuntime(
          method,
          args,
          allowShellRetry: true,
        );
      } catch (guardError) {
        if (!_preferGuardRetry) {
          final guardPlugin = InstallManager.instance.findInstalled(
            'jar-guard',
          );
          throw BusinessException(
            '${_guardRetryHint(guardPlugin)}\n原始错误：$normalError',
          );
        }
        _preferGuardRetry = false;
        throw BusinessException(
          '普通模式运行失败：$normalError\n'
          'jar-guard 模式重试失败：$guardError',
        );
      }
    }
  }

  String _guardRetryHint(InstalledPlugin? guardPlugin) {
    final action = guardPlugin == null
        ? '安装「JAR 加固壳支持（Windows）」'
        : '开启「JAR 加固壳支持（Windows）」';
    return '普通模式运行失败。可$action后再次尝试。';
  }

  Future<dynamic> _callWithCurrentRuntime(
    String method,
    List<String> args, {
    required bool allowShellRetry,
  }) async {
    await ensureReady(forceGuardRetry: _preferGuardRetry);
    final wasNativeExtraction = _usingNativeExtraction;
    final client = _client;
    if (client == null || !client.isAlive) {
      throw const BusinessException('SpiderHost 尚未启动');
    }
    final api = (_api ?? '').split('?').first;
    if (!api.startsWith('csp_')) {
      throw BusinessException('不支持的 JAR 接口标识：$api');
    }
    final className = 'com.github.catvod.spider.${api.substring(4)}';
    final startupDeadline = DateTime.now().add(const Duration(seconds: 90));
    var nativePendingLogged = false;
    while (true) {
      _JarWinResponse response;
      try {
        response = await client.request(
          className: className,
          method: method,
          args: [_extText(_ext), ...args],
        );
      } catch (e) {
        if (wasNativeExtraction && allowShellRetry) {
          _needShellPayloadCheck = true;
          try {
            if (await _tryPromoteRuntimePayload(
              className: className,
              outerJarPath: client.jarPath,
            )) {
              return _call(method, args, allowShellRetry: false);
            }
          } catch (_) {}
        }
        rethrow;
      }

      if (!response.ok) {
        if (wasNativeExtraction) {
          try {
            if (await _tryPromoteRuntimePayload(
              className: className,
              outerJarPath: client.jarPath,
            )) {
              return _call(method, args, allowShellRetry: false);
            }
          } catch (_) {}
        }
        throw BusinessException(
          response.data.isEmpty ? 'SpiderHost 请求失败' : response.data,
        );
      }
      if (response.data.isEmpty) {
        throw Exception('JAR 爬虫 $method 返回空数据');
      }

      final decoded = jsonDecode(response.data);
      final pending =
          decoded is Map && decoded.toString().contains('__host_pending__');
      if (!pending) return decoded;

      _needShellPayloadCheck = true;
      if (!wasNativeExtraction) {
        throw const BusinessException('JAR 返回了需要加固解包的状态');
      }
      if (!allowShellRetry) {
        throw const BusinessException('加固运行环境尚未初始化完成');
      }

      if (await _tryPromoteRuntimePayload(
        className: className,
        outerJarPath: client.jarPath,
      )) {
        return _call(method, args, allowShellRetry: false);
      }

      if (!_usingEmbeddedNativeRuntime) {
        final payloadReady = await _waitForRuntimePayload(
          className: className,
          outerJarPath: client.jarPath,
        );
        if (payloadReady) {
          return _call(method, args, allowShellRetry: false);
        }
        throw const BusinessException('加固解包仍在进行，请稍后再次请求');
      }

      // 内嵌 ARM SO 的 JAR 在 shell emulator 内完成初始化，不会产出
      // runtime_dex/*.r2.jar。复用同一个 SpiderHost 重试当前请求，避免把
      // 首次 native 初始化误判成需要用户手动再次点击的解包失败。
      if (!_preferGuardRetry) {
        throw const BusinessException('JAR 返回了需要加固解包的状态');
      }
      if (!DateTime.now().isBefore(startupDeadline)) {
        throw const BusinessException('加固运行环境初始化超时，请稍后重试');
      }

      if (!nativePendingLogged) {
        nativePendingLogged = true;
        debugPrint('[jar-win] native runtime initializing: $className');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<bool> _waitForRuntimePayload({
    required String className,
    required String outerJarPath,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      if (!_preferGuardRetry) return false;
      if (await _tryPromoteRuntimePayload(
        className: className,
        outerJarPath: outerJarPath,
      )) {
        debugPrint('[jar-win] payload ready: $className');
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  Future<bool> _tryPromoteRuntimePayload({
    required String className,
    required String outerJarPath,
  }) async {
    final exists = await _JarWinPreprocessor.instance.hasRuntimePayload(
      className: className,
      outerJarPath: outerJarPath,
    );
    if (!exists) return false;

    _needShellPayloadCheck = true;
    await ensureReady(forceGuardRetry: true);
    return !_usingNativeExtraction;
  }

  Map<String, dynamic> _asMap(dynamic value, String method) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw Exception('JAR 爬虫 $method 返回的数据不是对象');
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    return _asMap(await _call('homeContent', const []), 'homeContent');
  }

  @override
  Future<Map<String, dynamic>> fetchCate(
    String cateId,
    int page, {
    String? ext,
  }) async {
    return _asMap(
      await _call('categoryContent', [
        cateId,
        '$page',
        _categoryFilterText(ext),
      ]),
      'categoryContent',
    );
  }

  @override
  Future<Map<String, dynamic>> search(
    String wd,
    int page, {
    int quick = 0,
  }) async {
    return _asMap(
      await _call('searchContent', [wd, '$page']),
      'searchContent',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    return _asMap(await _call('detailContent', [ids]), 'detailContent');
  }

  @override
  Future<VideoDetail?> getDetail({
    required String vodId,
    required String pwd,
  }) async {
    final map = await fetchDetail(vodId);
    final list = map['list'];
    if (list is! List || list.isEmpty || list.first is! Map) return null;
    return VideoDetail.fromJson(Map<String, dynamic>.from(list.first as Map));
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(
    String play, {
    String? flag,
  }) async {
    return _asMap(
      await _call('playerContent', [flag ?? '', play]),
      'playerContent',
    );
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    return PlayUrl.fromJson(
      await fetchPlayUrl(playParams, flag: flag),
    );
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

  String _extText(dynamic ext) {
    if (ext == null) return '';
    if (ext is String) return ext;
    try {
      return jsonEncode(ext);
    } catch (_) {
      return ext.toString();
    }
  }

  String _categoryFilterText(String? ext) {
    if (ext == null || ext.isEmpty) return '';
    dynamic value;
    try {
      value = jsonDecode(ext);
    } catch (_) {
      try {
        value = jsonDecode(utf8.decode(base64Decode(ext)));
      } catch (_) {
        return '';
      }
    }
    if (value is! Map || value.isEmpty) return '';
    return value.entries
        .where((entry) => entry.value != null)
        .map((entry) {
          final key = Uri.encodeQueryComponent(entry.key.toString());
          final item = Uri.encodeQueryComponent(entry.value.toString());
          return '$key=$item';
        })
        .join('&');
  }

  Future<String> _resolveJarPath() async {
    if (_jarSource.isEmpty) {
      throw const BusinessException('当前接口配置缺少顶层 spider JAR 地址');
    }
    final spec = _JarSourceSpec.parse(_jarSource);
    final source = spec.source;
    final sourceUri = Uri.tryParse(source);
    if (sourceUri != null &&
        (sourceUri.scheme == 'http' || sourceUri.scheme == 'https')) {
      return _downloadJar(sourceUri, spec.md5);
    }
    if (sourceUri != null && sourceUri.scheme == 'file') {
      final file = File(sourceUri.toFilePath());
      if (!file.existsSync()) {
        throw BusinessException('本地 spider JAR 不存在：${file.path}');
      }
      await _verifyMd5(file, spec.md5);
      return file.path;
    }
    if (p.isAbsolute(source)) {
      final file = File(source);
      if (!file.existsSync()) {
        throw BusinessException('本地 spider JAR 不存在：$source');
      }
      await _verifyMd5(file, spec.md5);
      return file.path;
    }
    if (_configBaseUrl.startsWith('http://') ||
        _configBaseUrl.startsWith('https://')) {
      return _downloadJar(
        Uri.parse(_configBaseUrl).resolveUri(sourceUri!),
        spec.md5,
      );
    }
    if (_configBaseUrl.isNotEmpty) {
      final file = File(p.join(p.dirname(_configBaseUrl), source));
      if (!file.existsSync()) {
        throw BusinessException('本地 spider JAR 不存在：${file.path}');
      }
      await _verifyMd5(file, spec.md5);
      return file.path;
    }
    throw BusinessException('无法解析 spider JAR 地址：$_jarSource');
  }

  Future<String> _downloadJar(Uri source, String? expectedMd5) async {
    final dataRoot = await PluginPaths.dataRoot();
    final cacheDir = Directory(p.join(dataRoot.path, 'jar_cache'));
    await cacheDir.create(recursive: true);
    final cacheKey = sha256.convert(utf8.encode(source.toString())).toString();
    final cacheFile = File(p.join(cacheDir.path, '$cacheKey.jar'));
    if (cacheFile.existsSync()) {
      if (expectedMd5 == null) return cacheFile.path;
      try {
        await _verifyMd5(cacheFile, expectedMd5);
        return cacheFile.path;
      } on BusinessException {
        await cacheFile.delete();
      }
    }

    final partFile = File('${cacheFile.path}.part');
    try {
      final response = await HttpClientFactory.dio.get<List<int>>(
        source.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('JAR 下载结果为空');
      }
      await partFile.writeAsBytes(bytes, flush: true);
      await _verifyMd5(partFile, expectedMd5);
      if (cacheFile.existsSync()) await cacheFile.delete();
      await partFile.rename(cacheFile.path);
      return cacheFile.path;
    } catch (e) {
      if (partFile.existsSync()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      if (e is BusinessException) rethrow;
      throw Exception('spider JAR 下载失败：$e');
    }
  }

  Future<void> _verifyMd5(File file, String? expected) async {
    if (expected == null || expected.isEmpty) return;
    final actual = (await md5.bind(file.openRead()).first).toString();
    if (actual.toLowerCase() != expected.toLowerCase()) {
      throw BusinessException(
        'spider JAR 校验失败：期望 $expected，实际 $actual',
      );
    }
  }
}

class _JarSourceSpec {
  final String source;
  final String? md5;

  const _JarSourceSpec(this.source, this.md5);

  factory _JarSourceSpec.parse(String raw) {
    final parts = raw.split(';');
    String? digest;
    for (var i = 1; i + 1 < parts.length; i++) {
      if (parts[i].trim().toLowerCase() == 'md5') {
        digest = parts[i + 1].trim();
        break;
      }
    }
    return _JarSourceSpec(parts.first.trim(), digest);
  }
}

class _PreparedJar {
  final String path;
  final bool needsNoVerify;
  final bool hasOwnProxy;
  final bool isShell;
  final bool requiresGuardRuntime;
  final bool usesEmbeddedNativeRuntime;
  final bool useShellShim;
  final bool isAowu;
  final String? shellClasses;

  const _PreparedJar({
    required this.path,
    required this.needsNoVerify,
    required this.hasOwnProxy,
    this.isShell = false,
    this.requiresGuardRuntime = false,
    this.usesEmbeddedNativeRuntime = false,
    this.useShellShim = false,
    this.isAowu = false,
    this.shellClasses,
  });

  String get runtimeKey =>
      '$path|$isShell|$requiresGuardRuntime|$usesEmbeddedNativeRuntime|'
      '$useShellShim|'
      '$isAowu|${shellClasses ?? ''}';
}

/// jar-win 的运行时约定是 Java JAR，而 TVBox 网络源通常是仅含
/// classes.dex 的 APK/JAR 容器。SpiderHost 本身不会做转换，因此这里
/// 按插件约定完成 dex2jar -> DexJarRepair -> 原资源合并。
class _JarWinPreprocessor {
  _JarWinPreprocessor._();
  static final instance = _JarWinPreprocessor._();

  static const _ownProxyEntry = 'com/github/catvod/spider/Proxy.class';
  static const _cacheVersion = 'v1';

  final Map<String, Future<_PreparedJar>> _pending = {};
  final Map<String, Future<JarClassProfile>> _profiles = {};

  Future<_PreparedJar> prepare({
    required InstalledPlugin plugin,
    required String sourceJarPath,
    required String api,

    /// 仅在普通模式失败后的 guard 重试中启用。
    bool allowGuardExtraction = false,
  }) async {
    final source = File(sourceJarPath);
    if (!source.existsSync()) {
      throw BusinessException('spider JAR 不存在：$sourceJarPath');
    }

    final sourceArchive = await _decodeJar(source);
    final hasDex = _hasDex(sourceArchive);
    final sourceHasOwnProxy = _hasEntry(sourceArchive, _ownProxyEntry);
    final hasEmbeddedNativeLibrary = _hasEmbeddedNativeLibrary(sourceArchive);
    final className = _classNameOf(api);
    final isAowu = _isAowuClass(className);

    if (!hasDex) {
      return _withShellMode(
        plugin: plugin,
        path: source.path,
        needsNoVerify: false,
        hasOwnProxy: sourceHasOwnProxy,
        hasEmbeddedNativeLibrary: hasEmbeddedNativeLibrary,
        isAowu: isAowu,
        className: className,
        allowGuardExtraction: allowGuardExtraction,
      );
    }

    final sourceDigest = (await sha256.bind(source.openRead()).first)
        .toString();
    final identity = '$_cacheVersion|${plugin.version}|$sourceDigest';
    final cacheKey = sha256.convert(utf8.encode(identity)).toString();
    final dataRoot = await PluginPaths.dataRoot();
    final cacheDir = Directory(
      p.join(dataRoot.path, 'jar-win', 'dex-cache'),
    );
    final output = File(p.join(cacheDir.path, '$cacheKey.jar'));
    if (output.existsSync() && output.lengthSync() > 0) {
      final cachedArchive = await _decodeJar(output);
      return _withShellMode(
        plugin: plugin,
        path: output.path,
        needsNoVerify: true,
        hasOwnProxy: _hasEntry(cachedArchive, _ownProxyEntry),
        hasEmbeddedNativeLibrary: _hasEmbeddedNativeLibrary(cachedArchive),
        isAowu: isAowu,
        className: className,
        allowGuardExtraction: allowGuardExtraction,
      );
    }

    final pendingKey = '$cacheKey|$className|$isAowu|$allowGuardExtraction';
    final running = _pending[pendingKey];
    if (running != null) return running;

    final future = _prepareDexJar(
      plugin: plugin,
      source: source,
      sourceArchive: sourceArchive,
      output: output,
      sourceHasOwnProxy: sourceHasOwnProxy,
      hasEmbeddedNativeLibrary: hasEmbeddedNativeLibrary,
      isAowu: isAowu,
      className: className,
      allowGuardExtraction: allowGuardExtraction,
    );
    _pending[pendingKey] = future;
    try {
      return await future;
    } finally {
      _pending.remove(pendingKey);
    }
  }

  Future<_PreparedJar> _withShellMode({
    required InstalledPlugin plugin,
    required String path,
    required bool needsNoVerify,
    required bool hasOwnProxy,
    required bool hasEmbeddedNativeLibrary,
    required bool isAowu,
    required String className,
    required bool allowGuardExtraction,
  }) async {
    final profile = await _profileFor(File(path));
    final requiresGuardRuntime =
        profile.bootstrapUsesNative || profile.entryUsesNative(className);
    final payload = await _findRuntimePayload(className, path);
    if (payload != null) {
      debugPrint('[jar-win] runtime payload found: $className');
      final shim = await _payloadShim(payload, excludeAowuCrypto: isAowu);
      return _PreparedJar(
        path: path,
        needsNoVerify: needsNoVerify,
        hasOwnProxy: hasOwnProxy,
        isShell: true,
        requiresGuardRuntime: requiresGuardRuntime,
        usesEmbeddedNativeRuntime: hasEmbeddedNativeLibrary,
        useShellShim: true,
        isAowu: isAowu,
        shellClasses: await _shellSpecWithProxyBridge(shim.path, plugin),
      );
    }

    if (!allowGuardExtraction) {
      return _PreparedJar(
        path: path,
        needsNoVerify: needsNoVerify,
        hasOwnProxy: hasOwnProxy,
        requiresGuardRuntime: requiresGuardRuntime,
        isShell: requiresGuardRuntime,
        usesEmbeddedNativeRuntime: hasEmbeddedNativeLibrary,
      );
    }

    return _PreparedJar(
      path: path,
      needsNoVerify: needsNoVerify,
      hasOwnProxy: hasOwnProxy,
      isShell: true,
      requiresGuardRuntime: requiresGuardRuntime,
      usesEmbeddedNativeRuntime: hasEmbeddedNativeLibrary,
      isAowu: isAowu,
    );
  }

  String _classNameOf(String api) {
    final value = api.split('?').first.trim();
    if (value.startsWith('csp_')) {
      return 'com.github.catvod.spider.${value.substring(4)}';
    }
    if (value.contains('.')) return value;
    return value.isEmpty ? '' : 'com.github.catvod.spider.$value';
  }

  Future<JarClassProfile> _profileFor(File file) {
    final key =
        '${file.path}|${file.lengthSync()}|'
        '${file.lastModifiedSync().millisecondsSinceEpoch}';
    return _profiles.putIfAbsent(key, () async {
      try {
        return JarClassProfile.fromArchive(await _decodeJar(file));
      } catch (_) {
        _profiles.remove(key);
        rethrow;
      } finally {
        _profiles.removeWhere((cachedKey, _) => cachedKey != key);
      }
    });
  }

  bool _isAowuClass(String className) {
    final simple = className.split('.').last.toLowerCase();
    return simple.endsWith('amns') || simple.contains('aowu');
  }

  List<String> _payloadClassEntries(String className) {
    if (className.isEmpty) return const [];
    final simple = className.split('.').last;
    final base = simple.endsWith('Guard')
        ? simple.substring(0, simple.length - 'Guard'.length)
        : simple.endsWith('Amns')
        ? simple.substring(0, simple.length - 'Amns'.length)
        : simple.endsWith('CAT') && simple.length > 'CAT'.length
        ? simple.substring(0, simple.length - 'CAT'.length)
        : simple.endsWith('DexNative')
        ? simple.substring(
            0,
            simple.length - 'DexNative'.length,
          )
        : '';
    final names = <String>[className];
    if (base.isNotEmpty) {
      names.add(
        '${className.substring(0, className.length - simple.length)}$base',
      );
    }
    return names.map((e) => '${e.replaceAll('.', '/')}.class').toList();
  }

  Future<File?> _findRuntimePayload(String className, String outerJar) async {
    final wanted = _payloadClassEntries(className);
    if (wanted.isEmpty) return null;
    final dataRoot = await PluginPaths.dataRoot();
    final runtimeDir = Directory(
      p.join(
        dataRoot.path,
        'jar-win',
        'native',
        _nativeScopeName(outerJar),
        'runtime_dex',
      ),
    );
    if (!runtimeDir.existsSync()) return null;
    final candidates =
        runtimeDir
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.toLowerCase().endsWith('.r2.jar') &&
                  file.lengthSync() > 1024,
            )
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
    for (final candidate in candidates) {
      try {
        final entries = (await _decodeJar(
          candidate,
        )).files.where((file) => file.isFile).map((file) => file.name).toSet();
        if (wanted.any(entries.contains)) return candidate;
      } catch (_) {}
    }
    return null;
  }

  Future<File> _payloadShim(
    File payload, {
    required bool excludeAowuCrypto,
  }) async {
    final output = File(
      '${payload.path}${excludeAowuCrypto ? '.aowu' : '.shim'}.jar',
    );
    if (output.existsSync() &&
        output.lastModifiedSync().isAfter(payload.lastModifiedSync())) {
      return output;
    }

    final archive = await _decodeJar(payload);
    final patchedDir = Directory('${payload.path}.patched');
    final patched = <String, Uint8List>{};
    if (patchedDir.existsSync()) {
      for (final file
          in patchedDir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.toLowerCase().endsWith('.class')) continue;
        final name = p
            .relative(file.path, from: patchedDir.path)
            .replaceAll('\\', '/');
        patched[name] = await file.readAsBytes();
      }
    }

    final merged = Archive();
    const myCrypto = 'com/github/catvod/spider/MyCrypto.class';
    final existing = <String>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (excludeAowuCrypto && file.name == myCrypto) continue;
      final data = patched[file.name] ?? file.content;
      merged.addFile(ArchiveFile.bytes(file.name, data));
      existing.add(file.name);
    }
    for (final entry in patched.entries) {
      if (excludeAowuCrypto && entry.key == myCrypto) continue;
      if (!existing.add(entry.key)) continue;
      merged.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }

    final part = File('${output.path}.part');
    await part.writeAsBytes(ZipEncoder().encode(merged), flush: true);
    if (output.existsSync()) await output.delete();
    await part.rename(output.path);
    return output;
  }

  Future<String> _shellSpecWithProxyBridge(
    String shellClasses,
    InstalledPlugin plugin,
  ) async {
    final first = File(shellClasses.split(';').first);
    if (!first.existsSync()) return shellClasses;
    final names = (await _decodeJar(
      first,
    )).files.where((file) => file.isFile).map((file) => file.name).toSet();
    if (names.contains(_ownProxyEntry)) return shellClasses;
    if (!names.contains('com/github/catvod/spider/ProxyOrigin.class')) {
      return shellClasses;
    }
    final bridge = File(
      p.join(plugin.installPath, 'shims', 'proxy-bridge.jar'),
    );
    return bridge.existsSync() ? '${bridge.path};$shellClasses' : shellClasses;
  }

  String _nativeScopeName(String outerJar) {
    return sha256.convert(utf8.encode(outerJar)).toString();
  }

  Future<bool> hasRuntimePayload({
    required String className,
    required String outerJarPath,
  }) async {
    return await _findRuntimePayload(className, outerJarPath) != null;
  }

  Future<_PreparedJar> _prepareDexJar({
    required InstalledPlugin plugin,
    required File source,
    required Archive sourceArchive,
    required File output,
    required bool sourceHasOwnProxy,
    required bool hasEmbeddedNativeLibrary,
    required bool isAowu,
    required String className,
    required bool allowGuardExtraction,
  }) async {
    final root = plugin.installPath;
    final javaExe = _JarWinHostClient._findJava(root);
    await output.parent.create(recursive: true);
    final tempDir = await Directory.systemTemp.createTemp(
      'yuanying-jar-win-',
    );
    final converted = File(p.join(tempDir.path, 'converted.jar'));
    try {
      final d2jClasspath = _classpathIn(p.join(root, 'd2j'));
      final dex2jar = await Process.run(
        javaExe,
        [
          '-cp',
          d2jClasspath,
          'com.googlecode.dex2jar.tools.Dex2jarCmd',
          '-f',
          '-o',
          converted.path,
          source.path,
        ],
        workingDirectory: root,
      ).timeout(const Duration(minutes: 3));
      if (dex2jar.exitCode != 0 || !converted.existsSync()) {
        final detail = '${dex2jar.stdout}\n${dex2jar.stderr}'.trim();
        throw BusinessException(
          'dex2jar 转换失败'
          '${detail.isEmpty ? '' : '：$detail'}',
        );
      }

      await _repairDexJar(
        root: root,
        javaExe: javaExe,
        source: source,
        converted: converted,
      );

      final convertedArchive = await _decodeJar(converted);
      final merged = _mergeArchives(sourceArchive, convertedArchive);
      final encoded = ZipEncoder().encode(merged);
      final hasOwnProxy =
          sourceHasOwnProxy || _hasEntry(convertedArchive, _ownProxyEntry);

      final part = File('${output.path}.part');
      await part.writeAsBytes(encoded, flush: true);
      if (output.existsSync()) await output.delete();
      await part.rename(output.path);
      return _withShellMode(
        plugin: plugin,
        path: output.path,
        needsNoVerify: true,
        hasOwnProxy: hasOwnProxy,
        hasEmbeddedNativeLibrary: hasEmbeddedNativeLibrary,
        isAowu: isAowu,
        className: className,
        allowGuardExtraction: allowGuardExtraction,
      );
    } on TimeoutException {
      throw const BusinessException('dex2jar 转换超时');
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _repairDexJar({
    required String root,
    required String javaExe,
    required File source,
    required File converted,
  }) async {
    final repairJar = p.join(root, 'shims', 'native-bridge.jar');
    final d2jFiles = _JarWinHostClient._jarFilesIn(
      p.join(root, 'd2j'),
    ).toList();
    if (!File(repairJar).existsSync() || d2jFiles.isEmpty) return;

    final repairClasspath = [repairJar, ...d2jFiles].join(';');
    final childClasspath = d2jFiles.join(';');
    try {
      final result = await Process.run(
        javaExe,
        [
          '-cp',
          repairClasspath,
          'com.winbox.nativebridge.DexJarRepair',
          source.path,
          converted.path,
          javaExe,
          childClasspath,
        ],
        workingDirectory: root,
      ).timeout(const Duration(minutes: 1));
      final output = '${result.stdout}\n${result.stderr}'.trim();
      if (result.exitCode != 0 ||
          output.contains('fixed sites = -1') ||
          output.contains('baksmali failed')) {
        debugPrint('[jar-win] DexJarRepair skipped: $output');
      }
    } catch (e) {
      debugPrint('[jar-win] DexJarRepair skipped: $e');
    }
  }

  Future<Archive> _decodeJar(File file) async {
    try {
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      return archive;
    } catch (e) {
      throw BusinessException('spider JAR 无法解包：$e');
    }
  }

  bool _hasDex(Archive archive) {
    return archive.files.any(
      (file) => file.isFile && RegExp(r'classes\d*\.dex$').hasMatch(file.name),
    );
  }

  bool _hasEmbeddedNativeLibrary(Archive archive) {
    for (final file in archive.files) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.so')) {
        continue;
      }
      final content = file.content;
      if (content.length >= 4 &&
          content[0] == 0x7f &&
          content[1] == 0x45 &&
          content[2] == 0x4c &&
          content[3] == 0x46) {
        return true;
      }
    }
    return false;
  }

  bool _hasEntry(Archive archive, String name) {
    return archive.files.any((file) => file.isFile && file.name == name);
  }

  Archive _mergeArchives(Archive source, Archive converted) {
    final entries = <String, Uint8List>{};

    for (final file in source.files) {
      if (!file.isFile || !_keepSourceFile(file.name)) continue;
      entries[file.name] = file.content;
    }
    for (final file in converted.files) {
      if (!file.isFile || !_isSafeEntry(file.name)) continue;
      if (file.name.startsWith('META-INF/')) continue;
      entries[file.name] = file.content;
    }

    final merged = Archive();
    for (final entry in entries.entries) {
      merged.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    return merged;
  }

  bool _keepSourceFile(String name) {
    if (!_isSafeEntry(name)) return false;
    if (name.startsWith('META-INF/')) return false;
    if (name == 'AndroidManifest.xml' ||
        name == 'resources.arsc' ||
        name.startsWith('kotlin/')) {
      return false;
    }
    if (RegExp(r'classes\d*\.dex$').hasMatch(name)) return false;
    return true;
  }

  bool _isSafeEntry(String name) {
    if (name.isEmpty || name.startsWith('/') || name.contains('\\')) {
      return false;
    }
    return !name.split('/').contains('..');
  }

  String _classpathIn(String directory) {
    final files = _JarWinHostClient._jarFilesIn(directory).toList();
    if (files.isEmpty) {
      throw BusinessException('jar-win 缺少运行时组件目录：$directory');
    }
    return files.join(';');
  }
}

class _JarWinHostPool {
  _JarWinHostPool._();
  static final instance = _JarWinHostPool._();

  final Map<String, _JarWinHostClient> _clients = {};
  final Map<String, Future<_JarWinHostClient>> _starting = {};

  Future<_JarWinHostClient> acquire(
    InstalledPlugin plugin,
    _PreparedJar jar,
  ) async {
    final guardPlugin = jar.isShell
        ? InstallManager.instance.findInstalled('jar-guard')
        : null;
    final guardRuntimeKey = jar.isShell
        ? '${guardPlugin?.version ?? ''}|${guardPlugin?.enabled ?? false}|'
              '${guardPlugin?.installPath ?? ''}'
        : 'normal';
    final key =
        '${plugin.version}|${plugin.installPath}|${jar.runtimeKey}|'
        '$guardRuntimeKey';
    final existing = _clients[key];
    if (existing != null && existing.isAlive) return existing;
    final pending = _starting[key];
    if (pending != null) return pending;

    final future = _start(key, plugin, jar);
    _starting[key] = future;
    try {
      return await future;
    } finally {
      _starting.remove(key);
    }
  }

  Future<_JarWinHostClient> _start(
    String key,
    InstalledPlugin plugin,
    _PreparedJar jar,
  ) async {
    final client = await _JarWinHostClient.start(
      plugin: plugin,
      jar: jar,
      onIdle: () {
        _clients.remove(key);
      },
    );
    _clients[key] = client;
    return client;
  }

  Future<void> shutdownAll() async {
    final clients = _clients.values.toList();
    _clients.clear();
    await Future.wait(clients.map((client) => client.stop()));
  }
}

class _JarWinResponse {
  final bool ok;
  final String data;
  final int? proxyPort;

  const _JarWinResponse({
    required this.ok,
    required this.data,
    this.proxyPort,
  });
}

class _JarWinHostClient {
  _JarWinHostClient._({
    required this.process,
    required this.jarPath,
    required this.requestTimeout,
  });

  final Process process;
  final String jarPath;
  final Duration requestTimeout;
  final Map<String, Completer<_JarWinResponse>> _pending = {};
  Future<void> _writeTail = Future.value();
  Timer? _idleTimer;
  int _nextId = 0;
  bool _alive = true;
  bool _stopping = false;
  VoidCallback? _onIdle;

  bool get isAlive => _alive;

  static Future<_JarWinHostClient> start({
    required InstalledPlugin plugin,
    required _PreparedJar jar,
    required void Function() onIdle,
  }) async {
    if (!Platform.isWindows) {
      throw const BusinessException('jar-win 仅支持 Windows');
    }
    final root = plugin.installPath;
    final javaExe = _findJava(root);
    final hostJar = File(p.join(root, 'shims', 'spider-host.jar'));
    if (!hostJar.existsSync()) {
      throw const BusinessException('jar-win 插件缺少 SpiderHost');
    }
    final dataRoot = await PluginPaths.dataRoot();
    final cacheDir = Directory(p.join(dataRoot.path, 'jar-win', 'cache'));
    final nativeDir = Directory(p.join(dataRoot.path, 'jar-win', 'native'));
    final nativeScope = Directory(
      p.join(
        nativeDir.path,
        _JarWinPreprocessor.instance._nativeScopeName(jar.path),
      ),
    );
    final nativeWork = Directory(p.join(nativeScope.path, 'work'));
    final nativePatch = Directory(p.join(nativeScope.path, 'patch'));
    final runtimeDex = Directory(p.join(nativeScope.path, 'runtime_dex'));
    await cacheDir.create(recursive: true);
    await nativeDir.create(recursive: true);
    if (jar.isShell) {
      await nativeWork.create(recursive: true);
      await nativePatch.create(recursive: true);
      await runtimeDex.create(recursive: true);
    }

    final classpathEntries = <String>[];
    for (final file
        in Directory(p.join(root, 'shims')).listSync().whereType<File>().where(
          (file) => file.path.toLowerCase().endsWith('.jar'),
        )) {
      final name = p.basename(file.path).toLowerCase();
      if (name == 'shell-shim.jar' && !jar.useShellShim) continue;
      if (name == 'aowu-shim.jar' && !(jar.useShellShim && jar.isAowu)) {
        continue;
      }
      if (name == 'native-bridge.jar' && !jar.isShell) continue;
      if (name == 'proxy-bridge.jar' && (jar.isShell || jar.hasOwnProxy)) {
        continue;
      }
      classpathEntries.add(file.path);
    }
    classpathEntries
      ..addAll(_jarFilesIn(p.join(root, 'libs')))
      ..addAll(_jarFilesIn(p.join(root, 'd2j')));
    final d2jClasspath = _jarFilesIn(p.join(root, 'd2j')).join(';');
    final jarGuard = InstallManager.instance.findInstalled('jar-guard');
    if (jar.isShell &&
        jarGuard != null &&
        jarGuard.enabled &&
        Directory(jarGuard.installPath).existsSync()) {
      classpathEntries
        ..addAll(_jarFilesIn(jarGuard.installPath))
        ..add(p.join(jarGuard.installPath, 'assets'));
    }
    final classpath = classpathEntries.join(Platform.isWindows ? ';' : ':');
    final nativeProperties = jar.isShell
        ? [
            '-Dtvbox.native.backend=dynarmic',
            '-Dtvbox.native.work=${nativeWork.path}',
            '-Dtvbox.native.patch=${nativePatch.path}',
            '-Dtvbox.d2j.java=$javaExe',
            '-Dtvbox.d2j.cp=$d2jClasspath',
            '-Dtvbox.d2j.cache=${runtimeDex.path}',
            if (jar.shellClasses != null)
              '-Dtvbox.shellShimClasses=${jar.shellClasses}',
          ]
        : const <String>[];
    final process = await Process.start(
      javaExe,
      [
        if (jar.needsNoVerify) '-noverify',
        if (jar.isShell) ...[
          '-Xmx768m',
          '-XX:+UseSerialGC',
        ],
        '-Dfile.encoding=UTF-8',
        '-Dsun.stdout.encoding=UTF-8',
        '-Dsun.stderr.encoding=UTF-8',
        '--add-opens=java.base/java.lang=ALL-UNNAMED',
        '--add-opens=java.base/java.lang.reflect=ALL-UNNAMED',
        '--add-opens=java.base/java.lang.invoke=ALL-UNNAMED',
        '--add-opens=java.base/java.util=ALL-UNNAMED',
        '--add-opens=java.base/java.util.concurrent=ALL-UNNAMED',
        '--add-opens=java.base/java.io=ALL-UNNAMED',
        '--add-opens=java.base/java.net=ALL-UNNAMED',
        '--add-opens=java.base/java.nio=ALL-UNNAMED',
        '--add-opens=java.base/java.security=ALL-UNNAMED',
        '--add-opens=java.base/java.text=ALL-UNNAMED',
        '--add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED',
        '-Dtvbox.spiderCacheDir=${cacheDir.path}',
        ...nativeProperties,
        '-cp',
        classpath,
        'SpiderHost',
        '--serve',
        jar.path,
      ],
      workingDirectory: root,
      runInShell: false,
    );

    final client = _JarWinHostClient._(
      process: process,
      jarPath: jar.path,
      requestTimeout: jar.isShell && !jar.useShellShim
          ? const Duration(minutes: 4)
          : const Duration(seconds: 90),
    );
    client
      .._onIdle = onIdle
      .._listenOutput();
    try {
      await client._ping();
    } catch (_) {
      await client.stop();
      rethrow;
    }
    client._scheduleIdle();
    return client;
  }

  static String _findJava(String root) {
    final candidates = [
      p.join(root, 'bin', 'jre', 'bin', 'java.exe'),
      p.join(root, 'jre', 'bin', 'java.exe'),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    throw const BusinessException('jar-win 插件缺少内置 java.exe');
  }

  static Iterable<String> _jarFilesIn(String directory) sync* {
    final dir = Directory(directory);
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>()) {
      if (file.path.toLowerCase().endsWith('.jar')) yield file.path;
    }
  }

  void _listenOutput() {
    process.stdout
        .transform(const Utf8Codec(allowMalformed: true).decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
    process.stderr
        .transform(const Utf8Codec(allowMalformed: true).decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isNotEmpty) {
            debugPrint('[jar-win] $line');
          }
        });
    process.exitCode.then((code) {
      _alive = false;
      _idleTimer?.cancel();
      final error = BusinessException('SpiderHost 已退出（$code）');
      for (final pending in _pending.values) {
        if (!pending.isCompleted) pending.completeError(error);
      }
      _pending.clear();
      _onIdle?.call();
    });
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final raw = jsonDecode(line);
      if (raw is! Map) return;
      final id = raw['id']?.toString() ?? '';
      final pending = _pending.remove(id);
      if (pending == null || pending.isCompleted) return;
      pending.complete(
        _JarWinResponse(
          ok: raw['ok'] == true,
          data: raw['data']?.toString() ?? '',
          proxyPort: raw['pp'] is num ? (raw['pp'] as num).toInt() : null,
        ),
      );
    } catch (e) {
      debugPrint('[jar-win] invalid protocol line: $e');
    }
  }

  Future<void> _ping() async {
    final response = await request(
      className: '__ping__',
      method: '__ping__',
      args: const [],
      timeout: const Duration(seconds: 30),
    );
    if (!response.ok) {
      await stop();
      throw BusinessException(
        response.data.isEmpty ? 'SpiderHost 启动失败' : response.data,
      );
    }
  }

  Future<_JarWinResponse> request({
    required String className,
    required String method,
    required List<String> args,
    Duration? timeout,
  }) async {
    if (!_alive || _stopping) {
      throw const BusinessException('SpiderHost 未运行');
    }
    _idleTimer?.cancel();
    final id = '${++_nextId}';
    final completer = Completer<_JarWinResponse>();
    _pending[id] = completer;
    try {
      await _writeLine(
        jsonEncode({
          'id': id,
          'className': className,
          'method': method,
          'args': args,
        }),
      );
      return await completer.future.timeout(timeout ?? requestTimeout);
    } finally {
      _pending.remove(id);
      _scheduleIdle();
    }
  }

  Future<void> _writeLine(String line) {
    final completer = Completer<void>();
    _writeTail = _writeTail
        .then((_) async {
          process.stdin.writeln(line);
          await process.stdin.flush();
        })
        .then(
          (_) {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (Object error, StackTrace stack) {
            if (!completer.isCompleted) {
              completer.completeError(error, stack);
            }
          },
        );
    return completer.future;
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    if (!_alive || _stopping) return;
    _idleTimer = Timer(const Duration(seconds: 45), () {
      stop().catchError((_) {});
    });
  }

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    _alive = false;
    _idleTimer?.cancel();
    try {
      process.stdin.writeln('quit');
      await process.stdin.flush();
      await process.stdin.close();
    } catch (_) {}
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      try {
        process.kill();
      } catch (_) {}
    }
    _onIdle?.call();
  }
}

class _GuardUnavailableException extends BusinessException {
  const _GuardUnavailableException(super.message);
}
