// ad_block_proxy.dart
//
// M3U8 去广告代理服务（独立可移植版）
//
// 设计原则：
//   1. 只处理 M3U8，其他类型一律透传
//   2. 宁漏杀不误杀，7 层串联防护
//   3. 零项目耦合，只依赖 dio
//
// 使用方式：
//   final proxy = AdBlockProxy();
//   await proxy.start();
//   final url = proxy.wrap(videoUrl, referer: 'https://xxx.com');
//   // 交给播放器播放
//   await proxy.stop();

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

// ============================================================
// 对外配置
// ============================================================

/// 去广告配置
///
/// 默认值偏保守（宁漏杀不误杀）。
class AdBlockConfig {
  /// 广告关键词黑名单
  final Set<String> adKeywords;

  /// 白名单关键词（命中直接放行）
  final Set<String> whitelistKeywords;

  /// 广告最大占比，超过则放弃过滤
  final double maxAdRatio;

  /// 最少有效切片数，低于此值不检测
  final int minSegments;

  /// 广告必须连续的最少切片数
  final int minContinuousAdSegments;

  /// 广告必须连续的最大切片数
  final int maxContinuousAdSegments;

  /// 前缀相似度阈值，低于此值视为结构突变
  final double prefixSimilarityThreshold;

  /// 域名稀有度阈值
  final double rareDomainThreshold;

  /// 路径相似度阈值
  final double pathSimilarityThreshold;

  /// 最大采样数量
  final int maxSampleSize;

  /// 缓存 TTL（秒）
  final int cacheTtlSeconds;

  /// 缓存最大条目数
  final int cacheMaxEntries;

  const AdBlockConfig({
    this.adKeywords = const {
      'ads', 'union', 'click', 'p2p', 'pop', 'advert', 'adv.', 'guanggao',
      'miaopai', 'banner', 'promo', 'sponsor', 'preroll', 'midroll',
    },
    this.whitelistKeywords = const {
      '/video/', '/hls/', '_1080', '_720', '_480', '1080p', '720p', '480p',
    },
    this.maxAdRatio = 0.25,
    this.minSegments = 8,
    this.minContinuousAdSegments = 2,
    this.maxContinuousAdSegments = 10,
    this.prefixSimilarityThreshold = 0.55,
    this.rareDomainThreshold = 0.15,
    this.pathSimilarityThreshold = 0.30,
    this.maxSampleSize = 100,
    this.cacheTtlSeconds = 300,
    this.cacheMaxEntries = 50,
  });

  /// 生产环境推荐（更保守）
  static const AdBlockConfig conservative = AdBlockConfig(
    maxAdRatio: 0.20,
    minSegments: 10,
    minContinuousAdSegments: 3,
    prefixSimilarityThreshold: 0.60,
    rareDomainThreshold: 0.20,
    pathSimilarityThreshold: 0.35,
  );

  /// 激进配置（调试用）
  static const AdBlockConfig aggressive = AdBlockConfig(
    maxAdRatio: 0.35,
    minSegments: 5,
    minContinuousAdSegments: 1,
    prefixSimilarityThreshold: 0.45,
    rareDomainThreshold: 0.10,
    pathSimilarityThreshold: 0.20,
  );
}

// ============================================================
// 对外服务
// ============================================================

/// M3U8 去广告代理服务
class AdBlockProxy {
  final AdBlockConfig config;
  final void Function(String message)? onLog;

  HttpServer? _server;
  int? _port;

  final Dio _dio;
  final Map<String, _CacheEntry> _cache = {};

  AdBlockProxy({
    AdBlockConfig? config,
    this.onLog,
  })  : config = config ?? const AdBlockConfig(),
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (status) => status != null && status < 500,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
          },
        ));

  int? get port => _port;
  bool get isRunning => _server != null;

  // ----------------------------------------------------------
  // 生命周期
  // ----------------------------------------------------------

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _log('代理已启动，端口 $_port');
    _server!.listen(_handleRequest, onError: (e) => _log('Server error: $e'));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _cache.clear();
    _log('代理已停止');
  }

  // ----------------------------------------------------------
  // 对外 API
  // ----------------------------------------------------------

  /// 判断 URL 是否需要走代理
  ///
  /// 只有 M3U8 才需要，直播/MP4/其他一律返回 false
  bool shouldProxy(String url) {
    final lower = url.toLowerCase();

    // 明确的 M3U8 优先判定（避免被 .ts 等参数误伤）
    if (lower.contains('.m3u8')) return true;

    // 明确的非 M3U8 扩展名（不含 .ts，.ts 是切片扩展名，可能出现在 M3U8 URL 参数里）
    const nonM3u8Exts = [
      '.mp4', '.flv', '.mkv', '.avi', '.mov', '.webm',
    ];
    if (nonM3u8Exts.any(lower.contains)) return false;

    // 直播流特征路径
    if (RegExp(r'/(live|stream|hls/live)/', caseSensitive: false).hasMatch(lower)) {
      return false;
    }

    return false;
  }

  /// 包装 URL
  ///
  /// 如果是 M3U8 且代理已启动，返回代理 URL；否则返回原始 URL。
  String wrap(String url, {String? referer}) {
    if (_port == null || !shouldProxy(url)) return url;

    final encodedUrl = base64Url.encode(utf8.encode(url));
    var result = 'http://127.0.0.1:$_port/proxy?url=$encodedUrl';

    if (referer != null && referer.isNotEmpty) {
      final encodedReferer = base64Url.encode(utf8.encode(referer));
      result += '&referer=$encodedReferer';
    }

    return result;
  }

  // ----------------------------------------------------------
  // HTTP 处理
  // ----------------------------------------------------------

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path != '/proxy') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final encodedUrl = request.uri.queryParameters['url'];
      final encodedReferer = request.uri.queryParameters['referer'];

      if (encodedUrl == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final originalUrl = utf8.decode(base64Url.decode(encodedUrl));
      final referer = encodedReferer != null
          ? utf8.decode(base64Url.decode(encodedReferer))
          : null;

      await _proxy(request, originalUrl, referer);
    } catch (e) {
      _log('请求失败: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _proxy(
    HttpRequest request,
    String url,
    String? referer,
  ) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            if (referer != null && referer.isNotEmpty) 'Referer': referer,
          },
        ),
      );

      final bytes = response.data ?? [];
      request.response.statusCode = response.statusCode ?? HttpStatus.ok;

      // 透传源站 headers
      response.headers.forEach((name, values) {
        const excluded = {
          'content-length', 'transfer-encoding', 'content-encoding', 'connection',
        };
        if (!excluded.contains(name.toLowerCase())) {
          for (final v in values) {
            request.response.headers.add(name, v);
          }
        }
      });

      if (bytes.isEmpty) {
        await request.response.close();
        return;
      }

      final content = utf8.decode(bytes, allowMalformed: true);
      final isM3u8 = content.trimLeft().startsWith('#EXTM3U');

      if (!isM3u8) {
        // 非 M3U8 透传
        request.response.add(bytes);
        return;
      }

      // M3U8 处理
      request.response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
      request.response.headers.add('Access-Control-Allow-Origin', '*');

      final processed = await _processM3u8(content, url, referer);
      request.response.write(processed);
    } catch (e) {
      _log('代理失败: ${_shortUrl(url)} | $e');
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  // ----------------------------------------------------------
  // M3U8 处理主流程
  // ----------------------------------------------------------

  Future<String> _processM3u8(
    String content,
    String url,
    String? referer,
  ) async {
    final cacheKey = '$url|${referer ?? ''}';
    final cached = _getCache(cacheKey);
    if (cached != null) {
      _log('缓存命中: ${_shortUrl(url)}');
      return cached;
    }

    try {
      final parsed = _parse(content, url);

      if (!parsed.isValid) {
        _log('无效 M3U8: ${_shortUrl(url)}');
        return content;
      }

      // 加密 HLS：不处理，避免删切片后 KEY 对不上
      if (parsed.lines.any((l) => l.startsWith('#EXT-X-KEY'))) {
        _log('加密 HLS，跳过过滤: ${_shortUrl(url)}');
        final result = _rewrite(parsed.lines, parsed.segments, {});
        _setCache(cacheKey, result);
        return result;
      }

      // Master Playlist：递归代理
      if (parsed.isMaster) {
        final result = _proxyMaster(parsed.lines, url, referer);
        _setCache(cacheKey, result);
        return result;
      }

      // Media Playlist：去广告
      final detection = _detectAds(parsed.segments);

      if (detection.aborted) {
        _log('放弃过滤: ${detection.reason}');
        final result = _rewrite(parsed.lines, parsed.segments, {});
        _setCache(cacheKey, result);
        return result;
      }

      if (detection.adIndices.isEmpty) {
        _log('无广告: ${_shortUrl(url)}');
        final result = _rewrite(parsed.lines, parsed.segments, {});
        _setCache(cacheKey, result);
        return result;
      }

      final result = _rewrite(parsed.lines, parsed.segments, detection.adIndices);
      _log('去广告完成: ${_shortUrl(url)} | 移除 ${detection.adIndices.length}/${parsed.segments.length}');
      _setCache(cacheKey, result);
      return result;
    } catch (e) {
      _log('M3U8 处理失败: ${_shortUrl(url)} | $e');
      return content;
    }
  }

  String _proxyMaster(List<String> lines, String baseUrl, String? referer) {
    final baseUri = Uri.parse(baseUrl);
    final result = <String>[];

    for (final line in lines) {
      if (line.startsWith('#')) {
        result.add(line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) {
          final abs = _resolve(baseUri, m.group(1)!);
          return 'URI="${wrap(abs, referer: referer)}"';
        }));
      } else {
        final abs = _resolve(baseUri, line);
        result.add(wrap(abs, referer: referer));
      }
    }
    return result.join('\n');
  }

  // ----------------------------------------------------------
  // 解析
  // ----------------------------------------------------------

  _ParseResult _parse(String content, String baseUrl) {
    final baseUri = Uri.parse(baseUrl);
    final trimmed = content.trim();

    if (!trimmed.startsWith('#EXTM3U')) {
      return _ParseResult.invalid(trimmed.split('\n'));
    }

    final rawLines = trimmed
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // 相对路径转绝对
    final lines = rawLines.map((line) {
      if (line.startsWith('#')) {
        return line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) {
          return 'URI="${_resolve(baseUri, m.group(1)!)}"';
        });
      }
      return _resolve(baseUri, line);
    }).toList();

    final isMaster = lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'));
    if (isMaster) {
      return _ParseResult(lines: lines, segments: [], isMaster: true, isValid: true);
    }

    final segments = _parseSegments(lines);
    return _ParseResult(lines: lines, segments: segments, isMaster: false, isValid: true);
  }

  List<_Segment> _parseSegments(List<String> lines) {
    final segments = <_Segment>[];
    int? start;
    List<String>? buffer;
    double duration = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('#EXTINF:')) {
        start = i;
        buffer = [line];
        duration = _parseDuration(line);
      } else if (start != null && !line.startsWith('#')) {
        buffer!.add(line);
        segments.add(_Segment(
          start: start,
          end: i,
          lines: List.from(buffer),
          url: line,
          duration: duration,
          isWhitelisted: _isWhitelisted(line),
          hasAdKeyword: _hasAdKeyword(line),
        ));
        start = null;
        buffer = null;
      } else if (start != null) {
        buffer?.add(line);
      }
    }
    return segments;
  }

  double _parseDuration(String extinf) {
    final m = RegExp(r'#EXTINF:\s*([\d.]+)').firstMatch(extinf);
    return m != null ? (double.tryParse(m.group(1)!) ?? 0) : 0;
  }

  bool _isWhitelisted(String url) {
    final lower = url.toLowerCase();
    return config.whitelistKeywords.any((kw) => lower.contains(kw.toLowerCase()));
  }

  bool _hasAdKeyword(String url) {
    final lower = url.toLowerCase();
    return config.adKeywords.any((kw) => lower.contains(kw.toLowerCase()));
  }

  // ----------------------------------------------------------
  // 广告检测（核心）
  // ----------------------------------------------------------

  _DetectionResult _detectAds(List<_Segment> segments) {
    // 第 0 层：样本量
    if (segments.length < config.minSegments) {
      return _DetectionResult.abort('样本不足 ${segments.length}<${config.minSegments}');
    }

    // 第 1 层：建立基准
    final baseline = _buildBaseline(segments);
    if (baseline == null) {
      return _DetectionResult.abort('无法建立基准模式');
    }

    _log('基准: 主域名=${baseline.mainDomain}, 平均时长=${baseline.avgDuration.toStringAsFixed(2)}s, 样本=${baseline.sampleSize}');

    // 第 2 层：逐 segment 打分
    final scoreMap = <int, _ScoreResult>{};
    for (int i = 0; i < segments.length; i++) {
      final r = _scoreWithSignals(segments[i], baseline, segments);
      if (r.score >= 0.7) {
        scoreMap[i] = r;
      }
    }

    if (scoreMap.isEmpty) return _DetectionResult.none();

    // 打印每个候选
    _log('候选切片 (${scoreMap.length} 个):');
    // scoreMap.forEach((idx, r) {
    //   _log('  #$idx $r → ${_shortUrl(segments[idx].url)}');
    // });
    scoreMap.forEach((idx, r) {
      _log('  #$idx $r → ${segments[idx].url}');   // 完整 URL
    });

    final candidates = scoreMap.keys.toSet();

    // 第 3 层：连续性校验
    final valid = <int>{};
    final rejectedGroups = <List<int>>[];
    for (final group in _continuousGroups(candidates)) {
      if (group.length < config.minContinuousAdSegments) {
        rejectedGroups.add(group);
        continue;
      }
      if (group.length > config.maxContinuousAdSegments) {
        rejectedGroups.add(group);
        continue;
      }
      valid.addAll(group);
    }

    // 打印连续性淘汰
    if (rejectedGroups.isNotEmpty) {
      _log('连续性校验淘汰:');
      for (final g in rejectedGroups) {
        _log('  组 $g (长度 ${g.length})');
      }
    }

    if (valid.isEmpty) return _DetectionResult.none();

    // 第 4 层：白名单
    final whitelistRemoved = <int>[];
    valid.removeWhere((i) {
      if (segments[i].isWhitelisted) {
        whitelistRemoved.add(i);
        return true;
      }
      return false;
    });
    if (whitelistRemoved.isNotEmpty) {
      _log('白名单放行: $whitelistRemoved');
    }
    if (valid.isEmpty) return _DetectionResult.none();

    // 第 5 层：占比安全阀
    final ratio = valid.length / segments.length;
    if (ratio > config.maxAdRatio) {
      return _DetectionResult.abort(
        '广告占比 ${(ratio * 100).toStringAsFixed(1)}%>${(config.maxAdRatio * 100)}%',
      );
    }

    // 第 6 层：边缘保护（首尾各 1 个不删）
    final edgeProtected = <int>[];
    if (valid.remove(0)) edgeProtected.add(0);
    if (valid.remove(segments.length - 1)) edgeProtected.add(segments.length - 1);
    if (edgeProtected.isNotEmpty) {
      _log('边缘保护保留: $edgeProtected');
    }

    // 打印最终被删切片
    if (valid.isNotEmpty) {
      _log('最终被删切片 (${valid.length} 个):');
      final sorted = valid.toList()..sort();
      for (final idx in sorted) {
        final r = scoreMap[idx];
        _log('  #$idx ${r ?? ""} → ${segments[idx].url}');   // 完整 URL
      }
    }

    return valid.isEmpty ? _DetectionResult.none() : _DetectionResult(adIndices: valid);
  }

  _Baseline? _buildBaseline(List<_Segment> segments) {
    final sample = segments.length > config.maxSampleSize
        ? segments.sublist(0, config.maxSampleSize)
        : segments;

    // 域名统计
    final domainCount = <String, int>{};
    for (final s in sample) {
      final d = _rootDomain(s.url);
      if (d.isEmpty) continue;
      domainCount[d] = (domainCount[d] ?? 0) + 1;
    }
    if (domainCount.isEmpty) return null;

    // 主域名
    String? mainDomain;
    int maxCount = 0;
    domainCount.forEach((d, c) {
      if (c > maxCount) {
        maxCount = c;
        mainDomain = d;
      }
    });
    if (mainDomain == null) return null;

    // 用 ! 断言（上面已判空），避免闭包导致的类型提升失效
    final String mainDomainValue = mainDomain!;

    // 主域名占比必须 ≥ 50%
    if (maxCount / sample.length < 0.5) return null;

    // 主域名下的最长公共前缀
    final mainSegments = sample
        .where((s) => _rootDomain(s.url) == mainDomainValue)
        .toList();
    if (mainSegments.isEmpty) return null;

    var prefix = mainSegments.first.url;
    for (final s in mainSegments) {
      prefix = _commonPrefix(prefix, s.url);
      if (prefix.length < 20) return null;
    }
    if (prefix.length < 20) return null;

    // 平均时长
    final durations = mainSegments
        .map((s) => s.duration)
        .where((d) => d > 0)
        .toList();
    final avgDuration = durations.isEmpty
        ? 0.0
        : durations.reduce((a, b) => a + b) / durations.length;

    return _Baseline(
      mainDomain: mainDomainValue,
      mainPrefix: prefix,
      avgDuration: avgDuration,
      sampleSize: sample.length,
      domainCount: domainCount,
    );
  }

  /// 返回打分结果（含命中的信号名）
  _ScoreResult _scoreWithSignals(_Segment seg, _Baseline baseline, List<_Segment> all) {
    if (seg.isWhitelisted) {
      return _ScoreResult(0, []);
    }

    double score = 0;
    final signals = <String>[];

    // 信号 1：域名（0.4）
    if (seg.rootDomain != baseline.mainDomain) {
      final ratio = baseline.domainCount[seg.rootDomain] != null
          ? baseline.domainCount[seg.rootDomain]! / baseline.sampleSize
          : 0.0;
      score += (ratio < config.rareDomainThreshold ? 1.0 : 0.5) * 0.4;
      signals.add('域名');
    }

    // 信号 2：前缀（0.4）
    final prefixSim = baseline.mainPrefix.isEmpty
        ? 1.0
        : _commonPrefix(seg.url, baseline.mainPrefix).length / baseline.mainPrefix.length;
    if (prefixSim < config.prefixSimilarityThreshold) {
      score += (1 - prefixSim) * 0.4;
      signals.add('前缀');
    }

    // 信号 3：关键词（0.2）
    if (seg.hasAdKeyword) {
      score += 0.2;
      signals.add('关键词');
    }

    // 信号 4：时长异常（0.3）
    if (baseline.avgDuration > 0 && seg.duration > 0) {
      final r = seg.duration / baseline.avgDuration;
      if (r < 0.3 || r > 3.0) {
        score += 0.3;
        signals.add('时长');
      }
    }

    // 信号 5：命名异常（0.2）
    if (RegExp(r'[_\-/](ad|ads|banner|promo|sponsor)\d*[_\-.$]',
        caseSensitive: false).hasMatch(seg.url)) {
      score += 0.2;
      signals.add('命名');
    }

    // 投票：至少 2 个信号
    if (signals.length < 2) {
      return _ScoreResult(0, []);
    }
    return _ScoreResult(score.clamp(0.0, 1.0), signals);
  }

  /// 兼容旧调用（只返回分数）
  double _score(_Segment seg, _Baseline baseline, List<_Segment> all) {
    return _scoreWithSignals(seg, baseline, all).score;
  }

  List<List<int>> _continuousGroups(Set<int> indices) {
    if (indices.isEmpty) return [];
    final sorted = indices.toList()..sort();
    final groups = <List<int>>[];
    var current = <int>[sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] == sorted[i - 1] + 1) {
        current.add(sorted[i]);
      } else {
        groups.add(current);
        current = [sorted[i]];
      }
    }
    groups.add(current);
    return groups;
  }

  // ----------------------------------------------------------
  // 重写
  // ----------------------------------------------------------

  String _rewrite(List<String> lines, List<_Segment> segments, Set<int> adIndices) {
    if (adIndices.isEmpty) return _sanitize(lines).join('\n');

    final removed = <int>{};
    for (final idx in adIndices) {
      if (idx < 0 || idx >= segments.length) continue;
      for (int i = segments[idx].start; i <= segments[idx].end; i++) {
        removed.add(i);
      }
    }

    // 计算头部被删掉的切片数（用于修正 EXT-X-MEDIA-SEQUENCE）
    int headRemovedCount = 0;
    for (int i = 0; i < segments.length; i++) {
      if (!adIndices.contains(i)) break;
      headRemovedCount++;
    }

    final result = <String>[];
    for (int i = 0; i < lines.length; i++) {
      if (removed.contains(i)) continue;

      // 修正 EXT-X-MEDIA-SEQUENCE
      if (headRemovedCount > 0 && lines[i].startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        final oldSeq = int.tryParse(
          lines[i].substring('#EXT-X-MEDIA-SEQUENCE:'.length).trim(),
        );
        if (oldSeq != null) {
          result.add('#EXT-X-MEDIA-SEQUENCE:${oldSeq + headRemovedCount}');
          continue;
        }
      }

      result.add(lines[i]);
    }
    return _sanitize(result).join('\n');
  }

  List<String> _sanitize(List<String> lines) {
    final clean = <String>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXT-X-DISCONTINUITY')) {
        if (i == lines.length - 1) continue;
        if (clean.isNotEmpty && clean.last.startsWith('#EXT-X-DISCONTINUITY')) continue;
        // 后续无 segment 则丢弃
        bool hasNext = false;
        for (int j = i + 1; j < lines.length; j++) {
          if (!lines[j].startsWith('#')) {
            hasNext = true;
            break;
          }
        }
        if (!hasNext) continue;
      }
      clean.add(line);
    }
    return clean;
  }

  // ----------------------------------------------------------
  // 工具
  // ----------------------------------------------------------

  String _resolve(Uri base, String path) {
    try {
      return base.resolve(path).toString();
    } catch (_) {
      return path;
    }
  }

  String _commonPrefix(String a, String b) {
    final len = a.length < b.length ? a.length : b.length;
    int i = 0;
    while (i < len && a[i] == b[i]) i++;
    return a.substring(0, i);
  }

  String _rootDomain(String url) {
    try {
      final host = Uri.parse(url).host;
      if (host.isEmpty) return '';
      final parts = host.split('.');
      return parts.length < 2 ? host : parts.sublist(parts.length - 2).join('.');
    } catch (_) {
      return '';
    }
  }

  /// 截断 URL，日志里只显示尾部关键部分
  String _shortUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isEmpty) return url;
      if (segments.length <= 2) return segments.join('/');
      return '.../${segments.sublist(segments.length - 2).join('/')}';
    } catch (_) {
      return url.length > 60 ? '...${url.substring(url.length - 60)}' : url;
    }
  }

  // ----------------------------------------------------------
  // 缓存
  // ----------------------------------------------------------

  String? _getCache(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expireAt)) {
      _cache.remove(key);
      return null;
    }
    return entry.content;
  }

  void _setCache(String key, String content) {
    if (_cache.length >= config.cacheMaxEntries) {
      String? oldestKey;
      DateTime? oldestTime;
      _cache.forEach((k, v) {
        if (oldestTime == null || v.expireAt.isBefore(oldestTime!)) {
          oldestTime = v.expireAt;
          oldestKey = k;
        }
      });
      if (oldestKey != null) _cache.remove(oldestKey);
    }
    _cache[key] = _CacheEntry(
      content: content,
      expireAt: DateTime.now().add(Duration(seconds: config.cacheTtlSeconds)),
    );
  }

  void _log(String msg) => onLog?.call('[AdBlock] $msg');
}

// ============================================================
// 内部数据结构（全部私有）
// ============================================================

class _ParseResult {
  final List<String> lines;
  final List<_Segment> segments;
  final bool isMaster;
  final bool isValid;

  _ParseResult({
    required this.lines,
    required this.segments,
    required this.isMaster,
    required this.isValid,
  });

  factory _ParseResult.invalid(List<String> lines) =>
      _ParseResult(lines: lines, segments: [], isMaster: false, isValid: false);
}

class _Segment {
  final int start;
  final int end;
  final List<String> lines;
  final String url;
  final double duration;
  final bool isWhitelisted;
  final bool hasAdKeyword;

  _Segment({
    required this.start,
    required this.end,
    required this.lines,
    required this.url,
    required this.duration,
    required this.isWhitelisted,
    required this.hasAdKeyword,
  });

  String get rootDomain {
    try {
      final host = Uri.parse(url).host;
      if (host.isEmpty) return '';
      final parts = host.split('.');
      return parts.length < 2 ? host : parts.sublist(parts.length - 2).join('.');
    } catch (_) {
      return '';
    }
  }
}

class _Baseline {
  final String mainDomain;
  final String mainPrefix;
  final double avgDuration;
  final int sampleSize;
  final Map<String, int> domainCount;

  _Baseline({
    required this.mainDomain,
    required this.mainPrefix,
    required this.avgDuration,
    required this.sampleSize,
    required this.domainCount,
  });
}

/// 单个切片的打分结果
class _ScoreResult {
  final double score;
  final List<String> signals;   // 命中的信号名，便于排查

  _ScoreResult(this.score, this.signals);

  @override
  String toString() =>
      'score=${score.toStringAsFixed(2)}, 信号: ${signals.isEmpty ? "无" : signals.join("/")}';
}

class _DetectionResult {
  final Set<int> adIndices;
  final bool aborted;
  final String? reason;

  _DetectionResult({required this.adIndices, this.aborted = false, this.reason});

  factory _DetectionResult.abort(String reason) =>
      _DetectionResult(adIndices: {}, aborted: true, reason: reason);

  factory _DetectionResult.none() => _DetectionResult(adIndices: {});
}

class _CacheEntry {
  final String content;
  final DateTime expireAt;
  _CacheEntry({required this.content, required this.expireAt});
}