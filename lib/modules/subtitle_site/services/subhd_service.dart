import 'dart:io' show SocketException;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:html/parser.dart' as html_parser;

import '../models/subtitle_file.dart';
import '../models/subtitle_search_result.dart';
import '../models/subtitle_site_type.dart';
import '../utils/cookie_interceptor.dart';
import '../utils/subtitle_utils.dart';
import 'subtitle_site_service.dart';

/// SubHD 服务
///
/// 三层能力：
/// 1. search()：搜索页 /search/{keyword} → 每作品返回一条代表字幕 + groupId
/// 2. fetchGroup()：详情页 /d/{groupId} → 该作品的全部字幕
/// 3. download()：4 步 Cookie 门控流程拿到文件
class SubhdService implements SubtitleSiteService {
  static const _bases = <String>[
    'https://subhd.me',
    'https://subhd.one',
    'https://subhd.top',
    'https://subhd.cc',
    'https://subhd.tv',
  ];

  static const _knownFormats = <String>{
    'SRT', 'ASS', 'SSA', 'VTT', 'SUP', 'SUB', 'IDX',
  };

  final Dio _dio;
  final CookieJar _cookieJar = CookieJar();
  String? _lastWorkingBase;

  SubhdService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        )) {
    _dio.interceptors.add(SimpleCookieInterceptor(_cookieJar));
    _dio.options.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/126.0.0.0 Safari/537.36';
  }

  @override
  SubtitleSiteType get type => SubtitleSiteType.subhd;

  @override
  bool get isConfigured => true;

  bool _isNetworkLayerError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      case DioExceptionType.unknown:
        return e.error is SocketException;
      default:
        return false;
    }
  }

  Future<T> _withFallback<T>(Future<T> Function(String base) fn) async {
    final ordered = <String>[
      if (_lastWorkingBase != null) _lastWorkingBase!,
      ..._bases.where((b) => b != _lastWorkingBase),
    ];

    Object? lastNetworkError;
    for (final base in ordered) {
      try {
        final result = await fn(base);
        _lastWorkingBase = base;
        return result;
      } on DioException catch (e) {
        if (_isNetworkLayerError(e)) {
          debugPrint('[SubHD] $base 网络层失败: ${e.type} ${e.message}');
          lastNetworkError = e;
          continue;
        }
        final code = e.response?.statusCode;
        final body = e.response?.data;
        debugPrint('[SubHD] $base HTTP $code: $body');
        throw SubtitleSiteException(
          'SubHD 请求失败（HTTP $code）${_extractErrorMsg(body)}',
        );
      } catch (e) {
        rethrow;
      }
    }
    throw SubtitleSiteException(
      'SubHD 所有域名均不可达'
      '（${lastNetworkError?.toString().split('\n').first ?? '网络错误'}）',
    );
  }

  String _extractErrorMsg(dynamic body) {
    if (body is Map) {
      final msg = body['msg'] ?? body['error'];
      if (msg != null && msg.toString().isNotEmpty) {
        return '：$msg';
      }
    }
    return '';
  }

  Map<String, String> _jsonHeaders(String base, String refererPath) {
    return {
      'Referer': '$base$refererPath',
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'X-Requested-With': 'XMLHttpRequest',
      'Origin': base,
    };
  }

  // ============================================================
  // 搜索
  // ============================================================

  @override
  Future<List<SubtitleSearchResult>> search(String keyword) {
    return _withFallback((base) async {
      final resp = await _dio.get<String>(
        '$base/search/${Uri.encodeComponent(keyword)}',
        options: Options(
          headers: {'Referer': '$base/'},
          responseType: ResponseType.plain,
        ),
      );
      return _parseSearch(resp.data ?? '');
    });
  }

  /// 搜索页解析
  ///
  /// 每个结果块结构：
  /// - `/a/{sid}` → 字幕 ID
  /// - `/d/{groupId}` → 作品详情页 ID（本作品的全部字幕）
  List<SubtitleSearchResult> _parseSearch(String html) {
    final doc = html_parser.parse(html);
    final blocks =
        doc.querySelectorAll('div.bg-white.shadow-sm.rounded-3.mb-4');
    final results = <SubtitleSearchResult>[];

    for (final block in blocks) {
      // ---- 字幕 ID + 中文标题 ----
      final titleLink = block.querySelector('div.float-start.f16.fw-bold > a');
      String? subtitleId;
      String title = '未知';

      if (titleLink != null) {
        final href = titleLink.attributes['href'] ?? '';
        subtitleId =
            RegExp(r'/a/([0-9A-Za-z]+)').firstMatch(href)?.group(1);
        final t = titleLink.text.trim();
        if (t.isNotEmpty) title = t;
      }
      if (subtitleId == null) {
        final anyALink = block.querySelector('a[href^="/a/"]');
        if (anyALink == null) continue;
        final href = anyALink.attributes['href'] ?? '';
        subtitleId =
            RegExp(r'/a/([0-9A-Za-z]+)').firstMatch(href)?.group(1);
        if (subtitleId == null) continue;
        if (title == '未知') {
          final t = anyALink.text.trim();
          if (t.isNotEmpty) title = t;
        }
      }

      // ---- 作品分组 ID（/d/{groupId}）----
      String? groupId;
      final detailLink = block.querySelector('a[href^="/d/"]');
      if (detailLink != null) {
        groupId = RegExp(r'/d/(\d+)')
            .firstMatch(detailLink.attributes['href'] ?? '')
            ?.group(1);
      }

      // ---- 版本名 ----
      String? version;
      final versionLink =
          block.querySelector('div.view-text.text-secondary > a');
      if (versionLink != null) {
        final v = versionLink.text.trim();
        if (v.isNotEmpty && v != title) version = v;
      }

      // ---- 语言 / 格式 ----
      String? language;
      String? format;
      final tagContainer = block.querySelector('div.text-truncate.py-2.f11');
      if (tagContainer != null) {
        for (final span in tagContainer.querySelectorAll('span')) {
          final text = span.text.trim();
          if (text.isEmpty) continue;
          final style = span.attributes['style'] ?? '';
          if (style.contains('background-color')) continue;

          final classes = span.attributes['class'] ?? '';
          if (classes.contains('fw-bold') && language == null) {
            language = text;
          } else if (classes.contains('text-secondary') && format == null) {
            final upper = text.toUpperCase();
            if (_knownFormats.contains(upper)) format = upper;
          }
        }
      }

      results.add(SubtitleSearchResult(
        site: type,
        id: subtitleId,
        groupId: groupId,
        title: title,
        subtitle: version,
        language: language,
        format: format,
      ));
    }
    return results;
  }

  // ============================================================
  // 作品详情页（SubHD 独有）
  // ============================================================

  /// 访问作品详情页 /d/{groupId}，返回该作品的全部字幕列表
  ///
  /// 页面结构（与搜索页不同）：
  /// - 容器 class 是 `mb-5`（搜索页是 `mb-4`）
  /// - 每个 `div.bg-light` 是分类标题（"第X集" / "合集"）
  /// - 每个 `div.row` 是字幕条目，a[href^="/a/"] 是字幕 ID
  Future<List<SubtitleSearchResult>> fetchGroup(String groupId) {
    return _withFallback((base) async {
      final resp = await _dio.get<String>(
        '$base/d/$groupId',
        options: Options(
          headers: {'Referer': '$base/'},
          responseType: ResponseType.plain,
        ),
      );
      return _parseDetailPage(resp.data ?? '');
    });
  }

  List<SubtitleSearchResult> _parseDetailPage(String html) {
    final doc = html_parser.parse(html);
    // SubHD 详情页容器可能是 mb-5，兼容 mb-4
    final container =
        doc.querySelector('div.bg-white.shadow-sm.rounded-3.mb-5') ??
            doc.querySelector('div.bg-white.shadow-sm.rounded-3.mb-4');
    if (container == null) return const [];

    final results = <SubtitleSearchResult>[];
    String? currentCategory; // 当前分类：合集 / 第X集 / null

    for (final child in container.children) {
      if (child.localName != 'div') continue;
      final className = child.className;

      if (className.contains('bg-light')) {
        // 分类标题
        final text = child.text.trim();
        if (text.isNotEmpty) currentCategory = text;
        continue;
      }

      if (!className.contains('row')) continue;

      // ---- 字幕链接 ----
      final link = child.querySelector('a.link-dark');
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      if (!href.startsWith('/a/')) continue;
      final sid =
          RegExp(r'/a/([0-9A-Za-z]+)').firstMatch(href)?.group(1);
      if (sid == null) continue;

      final itemTitle = link.text.trim();
      final isCollection =
          currentCategory != null && currentCategory.contains('合集');

      // ---- 语言 / 格式 / 来源 ----
      String? language;
      String? format;
      final sourceTags = <String>[];
      for (final span in child.querySelectorAll('span')) {
        final text = span.text.trim();
        if (text.isEmpty) continue;
        final spanClass = span.className;

        if (spanClass.contains('rounded') &&
            spanClass.contains('text-white')) {
          // 来源标签（官方 / 原创 / AI 等）
          sourceTags.add(text);
        } else if (spanClass.contains('fw-bold') && language == null) {
          language = text;
        } else if (spanClass.contains('text-secondary') && format == null) {
          final upper = text.toUpperCase();
          if (_knownFormats.contains(upper)) format = upper;
        }
      }

      // ---- 字幕组 ----
      String? fansub;
      final fansubLink = child.querySelector('a[href^="/zu/"]') ??
          child.querySelector('a[href^="/u/"]');
      if (fansubLink != null) {
        final t = fansubLink.text.trim();
        if (t.isNotEmpty) fansub = t;
      }

      // ---- 组装副标题 ----
      final parts = <String>[];
      if (isCollection) parts.add('合集');
      if (currentCategory != null && !isCollection) parts.add(currentCategory);
      if (fansub != null) parts.add(fansub);
      parts.addAll(sourceTags);

      results.add(SubtitleSearchResult(
        site: type,
        id: sid,
        groupId: null, // 详情页返回的条目不再有 groupId，避免二次跳转
        title: itemTitle.isNotEmpty
            ? itemTitle
            : '字幕 ${results.length + 1}',
        subtitle: parts.isEmpty ? null : parts.join(' · '),
        language: language,
        format: format,
      ));
    }

    return results;
  }

  // ============================================================
  // 下载
  // ============================================================

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult item) {
    return _withFallback((base) async {
      String sid = item.id;

      // 兼容纯数字 ID（老入口或直接传详情页 ID）
      if (RegExp(r'^\d+$').hasMatch(sid)) {
        final detailResp = await _dio.get<String>(
          '$base/d/$sid',
          options: Options(
            headers: {'Referer': '$base/'},
            responseType: ResponseType.plain,
          ),
        );
        final match = RegExp(r'href="/(?:a)/([0-9A-Za-z]+)"')
            .firstMatch(detailResp.data ?? '');
        if (match == null) {
          throw SubtitleSiteException('SubHD 详情页未找到字幕条目');
        }
        sid = match.group(1)!;
      }

      debugPrint('[SubHD] 下载开始: sid=$sid, base=$base');

      // ---- 步骤 1：访问 /a/{sid} 拿初始 Cookie ----
      final aResp = await _dio.get<String>(
        '$base/a/$sid',
        options: Options(
          headers: {'Referer': '$base/'},
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      debugPrint('[SubHD] 步骤1 /a/$sid → HTTP ${aResp.statusCode}');
      if (aResp.statusCode != null && aResp.statusCode! >= 400) {
        throw SubtitleSiteException(
          'SubHD 字幕页返回 HTTP ${aResp.statusCode}',
        );
      }

      // ---- 步骤 2：prepare-download 拿临时 token ----
      final prepResp = await _dio.post<dynamic>(
        '$base/api/sub/prepare-download',
        data: {'sid': sid},
        options: Options(
          headers: _jsonHeaders(base, '/a/$sid'),
          validateStatus: (_) => true,
        ),
      );
      debugPrint(
          '[SubHD] 步骤2 prepare-download → HTTP ${prepResp.statusCode}, body=${prepResp.data}');
      if (prepResp.statusCode != null && prepResp.statusCode! >= 400) {
        throw SubtitleSiteException(
          'SubHD prepare-download 失败（HTTP ${prepResp.statusCode}）',
        );
      }
      final prepData = prepResp.data;
      if (prepData is Map && prepData['success'] == false) {
        final msg = prepData['msg'] ?? '未知';
        throw SubtitleSiteException('SubHD prepare-download 失败：$msg');
      }

      // ---- 步骤 3：访问 /down/{sid} 刷新 Cookie ----
      final downPageResp = await _dio.get<String>(
        '$base/down/$sid',
        options: Options(
          headers: {'Referer': '$base/a/$sid'},
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      debugPrint(
          '[SubHD] 步骤3 /down/$sid → HTTP ${downPageResp.statusCode}');

      // ---- 步骤 4：POST /api/sub/down 拿直链 ----
      final downResp = await _dio.post<dynamic>(
        '$base/api/sub/down',
        data: {'sid': sid},
        options: Options(
          headers: _jsonHeaders(base, '/down/$sid'),
          validateStatus: (_) => true,
        ),
      );
      debugPrint(
          '[SubHD] 步骤4 /api/sub/down → HTTP ${downResp.statusCode}, body=${downResp.data}');

      final data = downResp.data;
      if (data is! Map) {
        throw SubtitleSiteException(
          'SubHD 下载接口返回非 JSON（可能被反爬拦截或返回验证页）',
        );
      }
      if (data['success'] != true) {
        final msg = data['msg'] ?? '未知错误';
        throw SubtitleSiteException('SubHD 下载失败：$msg');
      }
      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw SubtitleSiteException('SubHD 未返回下载链接');
      }

      // ---- 步骤 5：下载文件 ----
      debugPrint('[SubHD] 步骤5 下载文件: $url');
      final fileResp = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Referer': '$base/down/$sid'},
        ),
      );
      final bytes = fileResp.data ?? const [];
      debugPrint('[SubHD] 步骤5 下载完成，${bytes.length} 字节');
      return SubtitleDownloadResult(
        files: extractSubtitleFiles(bytes, 'subhd_$sid'),
      );
    });
  }

  @override
  void dispose() {
    _dio.close(force: true);
  }
}