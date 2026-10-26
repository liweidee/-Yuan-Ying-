// lib/modules/plugin_center/services/market_manager.dart

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import 'package:yuanying/core/constants/plugin_storage_keys.dart';
import 'package:yuanying/http/init.dart';
import 'package:yuanying/modules/plugin_center/models/market_entry.dart';
import 'package:yuanying/modules/plugin_center/models/market_source.dart';

/// 市场管理：拉取 / 缓存 / 代理拼接 / 归并 / 过滤
class MarketManager {
  MarketManager._();
  static final MarketManager instance = MarketManager._();

  static const String _officialMarketId = 'official';
  static const String _officialMarketName = 'DsPlayer 官方市场';
  static const String _officialMarketUrl =
      'https://raw.githubusercontent.com/liweidee/dsplayer-plugin/main/market.json';

  /// 缓存有效期：1 小时
  static const int _cacheTtlMs = 60 * 60 * 1000;

  Box get _box => Hive.box(PluginStorageKeys.marketBox);

  // ============================================================
  // 市场源 CRUD
  // ============================================================

  List<MarketSource> getSources() {
    final raw = _box.get(PluginStorageKeys.marketSources);
    if (raw is! List || raw.isEmpty) {
      return [_defaultOfficialSource()];
    }
    return raw
        .map((e) => MarketSource.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  MarketSource _defaultOfficialSource() => MarketSource(
        id: _officialMarketId,
        name: _officialMarketName,
        url: _officialMarketUrl,
        enabled: true,
        proxy: 'https://gh-proxy.com/',
      );

  Future<void> saveSources(List<MarketSource> sources) async {
    await _box.put(
      PluginStorageKeys.marketSources,
      sources.map((e) => e.toJson()).toList(),
    );
  }

  /// 确保至少有一个默认市场源
  Future<void> ensureDefaultSource() async {
    final existing = _box.get(PluginStorageKeys.marketSources);
    if (existing == null || (existing is List && existing.isEmpty)) {
      await saveSources([_defaultOfficialSource()]);
    }
  }

  // ============================================================
  // 索引拉取
  // ============================================================

  /// 拉取单个市场源的最新索引
  /// [forceRefresh] true=强制跳过缓存
  Future<List<MarketEntry>> fetchIndex(
    MarketSource source, {
    bool forceRefresh = false,
  }) async {
    if (!source.enabled) return [];

    // 1. 缓存命中检查
    if (!forceRefresh) {
      final cached = _readCache(source);
      if (cached != null) return cached;
    }

    // 2. 拉取
    try {
      final fullUrl = _applyProxy(source.url, source.proxy);
      debugPrint('[MarketManager] fetch: $fullUrl');
      final resp = await HttpClientFactory.dio.get(
        fullUrl,
        options: Options(responseType: ResponseType.plain),
      );
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final rawText = resp.data.toString();
      final decoded = jsonDecode(rawText) as Map<String, dynamic>;
      final plugins = decoded['plugins'];
      if (plugins is! List) {
        throw Exception('market.json 缺少 plugins 数组');
      }
      final entries = plugins
          .map((e) => MarketEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      // 3. 写缓存
      await _writeCache(source, entries);
      return entries;
    } catch (e) {
      debugPrint('[MarketManager] fetch failed: $e');
      // 拉取失败时，退化到缓存
      final cached = _readCache(source, ignoreTtl: true);
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// 拉取所有启用的市场源，按 id 归并（同名按 updatedAt 取新，这里简化为后写覆盖）
  Future<List<MarketEntry>> fetchAll({bool forceRefresh = false}) async {
    final sources = getSources().where((s) => s.enabled).toList();
    final Map<String, MarketEntry> merged = {};
    for (final source in sources) {
      try {
        final entries = await fetchIndex(source, forceRefresh: forceRefresh);
        for (final e in entries) {
          merged[e.id] = e;
        }
      } catch (e) {
        debugPrint('[MarketManager] source ${source.id} failed: $e');
      }
    }
    return merged.values.toList();
  }

  // ============================================================
  // 代理拼接
  // ============================================================

  /// 对 GitHub 域自动套加速代理；其他域原样返回
  static String _applyProxy(String url, String proxy) {
    if (proxy.isEmpty) return url;
    if (!url.contains('github.com') &&
        !url.contains('raw.githubusercontent.com')) {
      return url;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      // 已是完整 URL，直接前缀
      return '$proxy$url';
    }
    return url;
  }

  /// 公开给安装层复用：解析相对 url
  static String resolveUrl(String url, String indexBaseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    // 相对本索引路径：取 index 的目录部分拼接
    final idx = indexBaseUrl.lastIndexOf('/');
    if (idx < 0) return url;
    return '${indexBaseUrl.substring(0, idx + 1)}$url';
  }

  // ============================================================
  // 缓存读写
  // ============================================================

  List<MarketEntry>? _readCache(MarketSource source, {bool ignoreTtl = false}) {
    final raw = _box.get('${PluginStorageKeys.marketIndexCachePrefix}${source.id}');
    if (raw is! Map) return null;
    final cachedAtMs = (raw['cachedAtMs'] is num)
        ? (raw['cachedAtMs'] as num).toInt()
        : 0;
    if (!ignoreTtl && DateTime.now().millisecondsSinceEpoch - cachedAtMs > _cacheTtlMs) {
      return null;
    }
    final list = raw['entries'];
    if (list is! List) return null;
    return list
        .map((e) => MarketEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _writeCache(MarketSource source, List<MarketEntry> entries) async {
    // 缓存时保存 url，供后续 resolveUrl 使用
    await _box.put(
      '${PluginStorageKeys.marketIndexCachePrefix}${source.id}',
      {
        'cachedAtMs': DateTime.now().millisecondsSinceEpoch,
        'indexBaseUrl': source.url,
        'entries': entries.map(_entryToJson).toList(),
      },
    );
  }

  Map<String, dynamic> _entryToJson(MarketEntry e) => {
        'id': e.id,
        'name': e.name,
        'version': e.version,
        'url': e.url,
        'size': e.sizeBytes,
        'type': e.type,
        'category': e.category,
        'icon': e.icon,
        'author': e.author,
        'desc': e.desc,
        'tags': e.tags,
        'changelog': e.changelog,
        'md5': e.md5,
        'minApp': e.minApp,
        'pkg': e.pkg,
        'platforms': e.platforms,
        'abis': e.abis,
      };

  /// 读取缓存里的 indexBaseUrl（供下载时拼相对 url）
  String getCachedIndexBaseUrl(String sourceId) {
    final raw = _box.get('${PluginStorageKeys.marketIndexCachePrefix}$sourceId');
    if (raw is Map) {
      return raw['indexBaseUrl']?.toString() ?? '';
    }
    return '';
  }
}