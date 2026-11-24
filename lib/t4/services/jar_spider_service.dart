import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/http/init.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_jar_spider_service.dart';
import 'package:yuanying/utils/business_exception.dart';

/// TVBox/CatVod JAR 插件适配器。
///
/// 本阶段只实现 JAR 爬虫的 Home/Category/Search/Detail/Play，
/// Proxy/Action 仍由后续独立通道接入。
class JarSpiderService implements IJarSpiderService {
  static const _channel = MethodChannel('com.dsplayer/jar_spider');
  static String? _hostPluginKey;

  String? _currentKey;
  String? _api;
  dynamic _ext;
  String _jarSource = '';
  String _configBaseUrl = '';

  String? _readyKey;
  String? _loadedPluginKey;
  String? _loadedJarPath;
  Future<void>? _preparing;

  @override
  String? get currentKey => _currentKey;

  @override
  void setBaseUrl(String url) {
    _api = url;
  }

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    final nextKey = '$siteKey|$apiUrl|${_extText(ext)}|$_jarSource';
    if (_readyKey != null && _readyKey != nextKey) {
      _readyKey = null;
    }
    _api = apiUrl;
    _currentKey = siteKey;
    _ext = ext;
  }

  @override
  void configureJarSource(String source, {String configBaseUrl = ''}) {
    final normalized = source.trim();
    if (_jarSource != normalized || _configBaseUrl != configBaseUrl) {
      _readyKey = null;
    }
    _jarSource = normalized;
    _configBaseUrl = configBaseUrl;
  }

  @override
  Future<void> ensureReady() {
    final plugin = _requireEnabledPlugin();
    final pluginKey = '${plugin.version}|${plugin.installPath}';
    final expectedKey = _runtimeKey(pluginKey: pluginKey);
    if (_readyKey == expectedKey) return Future.value();
    return _preparing ??= _prepare().whenComplete(() => _preparing = null);
  }

  Future<void> _prepare() async {
    if (!Platform.isAndroid) {
      throw const BusinessException('JAR 爬虫插件仅支持 Android');
    }
    final plugin = _requireEnabledPlugin();
    final pluginKey = '${plugin.version}|${plugin.installPath}';
    if (_hostPluginKey != pluginKey) {
      await _invoke('release');
      await _invoke('load', {
        'dir': plugin.installPath,
        'apk': false,
      });
      _hostPluginKey = pluginKey;
    }
    if (_loadedPluginKey != pluginKey) {
      _loadedJarPath = null;
      _loadedPluginKey = pluginKey;
    }

    final jarPath = await _resolveJarPath();
    if (_loadedJarPath != jarPath) {
      await _invoke('loadJar', {'jarPath': jarPath});
      _loadedJarPath = jarPath;
    }

    await _invoke('createSpider', {
      'jarPath': jarPath,
      'siteKey': _currentKey ?? '',
      'api': _api ?? '',
      'ext': _extText(_ext),
    });
    _readyKey = _runtimeKey(pluginKey: pluginKey);
  }

  InstalledPlugin _requireEnabledPlugin() {
    final plugin = InstallManager.instance.findInstalled('jar');
    if (plugin == null) {
      throw const BusinessException('请先在插件中心安装 JAR 爬虫引擎插件');
    }
    if (!plugin.enabled) {
      throw const BusinessException('JAR 爬虫引擎插件已关闭');
    }
    return plugin;
  }

  String _runtimeKey({required String pluginKey}) {
    return [
      pluginKey,
      _currentKey ?? '',
      _api ?? '',
      _extText(_ext),
      _jarSource,
    ].join('|');
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

    final windowsAbsolute = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source);
    if (p.isAbsolute(source) || windowsAbsolute) {
      final file = File(source);
      if (!file.existsSync()) {
        throw BusinessException('本地 spider JAR 不存在：$source');
      }
      await _verifyMd5(file, spec.md5);
      return file.path;
    }

    if (_configBaseUrl.startsWith('http://') ||
        _configBaseUrl.startsWith('https://')) {
      final resolved = Uri.parse(_configBaseUrl).resolveUri(sourceUri!);
      return _downloadJar(resolved, spec.md5);
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
    final root = await PluginPaths.dataRoot();
    final cacheDir = Directory(p.join(root.path, 'jar_cache'));
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

  Future<dynamic> _call(String method, List<String> args) async {
    await ensureReady();
    final jarPath = _loadedJarPath;
    if (jarPath == null || jarPath.isEmpty) {
      throw const BusinessException('spider JAR 尚未加载');
    }
    final data = await _invoke('call', {
      'jarPath': jarPath,
      'siteKey': _currentKey ?? '',
      'method': method,
      'args': args,
    });
    if (data == null) {
      throw Exception('JAR 爬虫 $method 返回空数据');
    }
    if (data is String) {
      if (data.trim().isEmpty) {
        throw Exception('JAR 爬虫 $method 返回空字符串');
      }
      return jsonDecode(data);
    }
    return data;
  }

  Future<dynamic> _invoke(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>(method, arguments);
      final map = raw is Map ? Map<String, dynamic>.from(raw) : null;
      if (map == null) {
        throw Exception('JAR 通道返回格式错误');
      }
      if (map['ok'] != true) {
        final error = map['error']?.toString() ?? '未知错误';
        final kind = map['errorKind']?.toString();
        _invalidateRuntimeAfterProcessFailure(kind);
        throw BusinessException(
          kind == null || kind.isEmpty ? error : '$error ($kind)',
        );
      }
      return map['data'];
    } on PlatformException catch (e) {
      if (e.code == 'JAR_BRIDGE_ERR') {
        _clearRuntimeSession();
      }
      final details = e.details?.toString().trim() ?? '';
      throw Exception(
        details.isEmpty
            ? (e.message ?? e.code)
            : '${e.message ?? e.code}\n$details',
      );
    }
  }

  void _invalidateRuntimeAfterProcessFailure(String? kind) {
    if (kind != 'JAR_PROCESS_CRASHED' &&
        kind != 'JAR_PROCESS_TIMEOUT' &&
        kind != 'JAR_PROCESS_UNAVAILABLE') {
      return;
    }
    _clearRuntimeSession();
  }

  void _clearRuntimeSession() {
    _readyKey = null;
    _loadedPluginKey = null;
    _loadedJarPath = null;
    _hostPluginKey = null;
  }

  Map<String, dynamic> _asMap(dynamic value, String method) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw Exception('JAR 爬虫 $method 返回的数据不是对象');
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

  String _normalizeCategoryExt(String? ext) {
    if (ext == null || ext.isEmpty) return '{}';
    try {
      final decoded = jsonDecode(ext);
      if (decoded is Map) return jsonEncode(decoded);
    } catch (_) {
      try {
        final decoded = utf8.decode(base64Decode(ext));
        final map = jsonDecode(decoded);
        if (map is Map) return jsonEncode(map);
      } catch (_) {}
    }
    return '{}';
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    return _asMap(
      await _call('home', ['${filter == 1}']),
      'home',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchCate(
    String cateId,
    int page, {
    String? ext,
  }) async {
    final extJson = _normalizeCategoryExt(ext);
    return _asMap(
      await _call('category', [
        cateId,
        '$page',
        '${extJson != '{}'}',
        extJson,
      ]),
      'category',
    );
  }

  @override
  Future<Map<String, dynamic>> search(
    String wd,
    int page, {
    int quick = 0,
  }) async {
    return _asMap(
      await _call('search', [wd, '$page']),
      'search',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    return _asMap(await _call('detail', [ids]), 'detail');
  }

  @override
  Future<VideoDetail?> getDetail({
    required String vodId,
    required String pwd,
  }) async {
    final map = await fetchDetail(vodId);
    final list = map['list'];
    if (list is! List || list.isEmpty || list.first is! Map) return null;
    return VideoDetail.fromJson(
      Map<String, dynamic>.from(list.first as Map),
    );
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(
    String play, {
    String? flag,
  }) async {
    return _asMap(
      await _call('play', [flag ?? '', play]),
      'play',
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

  @override
  Future<void> release() async {
    _readyKey = null;
    _loadedPluginKey = null;
    _loadedJarPath = null;
    try {
      await _invoke('release');
      _hostPluginKey = null;
    } catch (_) {}
  }
}

class _JarSourceSpec {
  final String source;
  final String? md5;

  const _JarSourceSpec(this.source, this.md5);

  factory _JarSourceSpec.parse(String raw) {
    final parts = raw.split(';');
    final source = parts.isEmpty ? '' : parts.first.trim();
    String? digest;
    for (var i = 1; i + 1 < parts.length; i++) {
      if (parts[i].trim().toLowerCase() == 'md5') {
        digest = parts[i + 1].trim();
        break;
      }
    }
    return _JarSourceSpec(source, digest);
  }
}
