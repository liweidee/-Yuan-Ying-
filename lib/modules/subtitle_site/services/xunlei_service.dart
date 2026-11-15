import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:enough_convert/enough_convert.dart';

import '../models/subtitle_file.dart';
import '../models/subtitle_search_result.dart';
import '../models/subtitle_site_type.dart';
import 'subtitle_site_service.dart';

/// 迅雷看看字幕服务
///
/// 特点：
/// - 无需认证、无额度限制、无 Cookie 门控
/// - 单次 GET 返回 JSON，下载为 CDN 直链
/// - 中文资源最丰富，番号内容独家支持
///
/// 关键词策略（必须）：
/// - 剧集：`片名 S01E12` 或 `片名 第1季第12集`
/// - 电影：`片名 年份`
/// - 番号：直接输入 `ADN-773`
/// 只给片名往往搜不到，接口需要"完整定位到一集/一部片"的关键词。
class XunleiService implements SubtitleSiteService {
  static const _apiBase = 'https://api-shoulei-ssl.xunlei.com';
  static const _cdnTemplate =
      'https://subtitle.v.geilijiasu.com/{aa}/{bb}/{cid}.{ext}';

  /// 只支持文本字幕格式，其它（sup/idx 等图形字幕）不参与搜索
  static const _textExts = <String>{
    'srt', 'ass', 'ssa', 'smi', 'vtt', 'txt',
  };

  final Dio _dio;

  XunleiService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/122.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
          },
        ));

  @override
  SubtitleSiteType get type => SubtitleSiteType.xunlei;

  @override
  bool get isConfigured => true;

  // ============================================================
  // 搜索
  // ============================================================

  @override
  Future<List<SubtitleSearchResult>> search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.length < 2) {
      throw SubtitleSiteException('迅雷看看需要至少 2 个字符的关键词');
    }

    final resp = await _dio.get<dynamic>(
      '$_apiBase/oracle/subtitle',
      queryParameters: {'name': trimmed},
    );

    final data = resp.data;
    final list = (data is Map ? data['data'] as List? : null) ?? const [];
    return list
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .map(_toResult)
        .whereType<SubtitleSearchResult>()
        .toList();
  }

  SubtitleSearchResult? _toResult(Map<String, dynamic> raw) {
    final cid = _safeStr(raw['cid']);
    if (cid.isEmpty) return null;

    final ext = _safeStr(raw['ext']).toLowerCase();
    if (!_textExts.contains(ext)) return null;

    final name = _safeStr(raw['name']);
    final simpleName = _safeStr(raw['simple_name']);
    final parsed = _parseSimpleName(simpleName);

    final title = parsed.title != null && parsed.title!.isNotEmpty
        ? parsed.title!
        : _stripExtFromName(name);

    final languages = (raw['languages'] as List?)
        ?.map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();

    final language = _mapLanguage(languages, parsed.language);

    return SubtitleSearchResult(
      site: type,
      id: cid,
      title: title.isEmpty ? '未知' : title,
      subtitle: name.isEmpty ? null : name,
      language: language,
      format: ext.toUpperCase(),
      raw: {
        'cid': cid,
        'ext': ext,
        'url': _safeStr(raw['url']),
        'name': name,
        'simple_name': simpleName,
        'duration': raw['duration'],
        'languages': languages ?? const [],
      },
    );
  }

  /// 解析 simple_name：`中文[SRT]越狱S01E12` → {title: '越狱', language: '中文', format: 'SRT'}
  ({String? title, String? language, String? format}) _parseSimpleName(
    String simpleName,
  ) {
    if (simpleName.isEmpty ||
        simpleName == 'undefined' ||
        simpleName == 'null') {
      return (title: null, language: null, format: null);
    }

    final match =
        RegExp(r'^(.*?)\[([A-Za-z0-9]{1,6})\](.*)$').firstMatch(simpleName);
    if (match == null) {
      return (
        title: simpleName.replaceAll(RegExp(r'\(\d{4}\)\s*$'), '').trim(),
        language: null,
        format: null,
      );
    }

    final lang = match.group(1)?.trim();
    final fmt = match.group(2)?.toUpperCase();
    final rest = match.group(3)?.trim() ?? '';

    final title = rest
        .replaceAll(
          RegExp(r'\bS\d{1,2}[\s.\-_]*E\d{1,3}\b', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'第\s*[\d零一二两三四五六七八九十]{1,3}\s*[集话話期]'),
          '',
        )
        .replaceAll(RegExp(r'\(\d{4}\)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return (
      title: title.isEmpty ? null : title,
      language: (lang == null || lang.isEmpty) ? null : lang,
      format: fmt,
    );
  }

  /// 语言识别：优先 languages 数组，其次 simple_name 前缀
  String? _mapLanguage(List<String>? languages, String? simpleNameLang) {
    final first = languages?.isNotEmpty == true ? languages!.first : null;
    return _normalizeLang(first) ?? _normalizeLang(simpleNameLang);
  }

  String? _normalizeLang(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final s = raw.toLowerCase();
    if (s.contains('双语') || s.contains('雙語') || s.contains('中英')) {
      return '中英双语';
    }
    if (s.contains('简') || s.contains('chs') || s.contains('gb')) {
      return '简体中文';
    }
    if (s.contains('繁') || s.contains('cht') || s.contains('big5')) {
      return '繁体中文';
    }
    if (s.contains('英') || s.contains('eng')) return '英语';
    if (s.contains('日') || s.contains('jpn')) return '日语';
    if (s.contains('韩') || s.contains('韓') || s.contains('kor')) return '韩语';
    return raw;
  }

  String _stripExtFromName(String name) {
    return name
        .replaceAll(
          RegExp(
            r'\.(srt|ass|ssa|smi|vtt|txt|sub|idx)$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  // ============================================================
  // 下载
  // ============================================================

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult item) async {
    final cid = item.id;
    final ext = (item.raw['ext']?.toString() ?? 'srt').toLowerCase();

    // 优先用搜索结果里带的 url，缓存过期或缺失时按 CDN 模板拼
    String url = _safeStr(item.raw['url']);
    if (url.isEmpty) {
      url = _cdnTemplate
          .replaceAll('{aa}', cid.length >= 2 ? cid.substring(0, 2) : '')
          .replaceAll('{bb}', cid.length >= 4 ? cid.substring(2, 4) : '')
          .replaceAll('{cid}', cid)
          .replaceAll('{ext}', ext);
    }

    final resp = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = resp.data ?? const [];
    if (bytes.isEmpty) {
      throw SubtitleSiteException('迅雷看看返回空文件');
    }

    // SMI 是特殊格式（SAMI），播放器/字幕挂载不支持，转成 SRT
    if (ext == 'smi') {
      final text = _decodeText(bytes);
      final srt = _smiToSrt(text);
      if (srt.trim().isEmpty) {
        throw SubtitleSiteException('SMI 字幕解析失败（内容为空）');
      }
      return SubtitleDownloadResult(files: [
        SubtitleFile(
          name: '$cid.srt',
          bytes: utf8.encode(srt),
          ext: 'srt',
        ),
      ]);
    }

    // SSA 与 ASS 内容结构一致，保留原扩展名（mdk/mpv 都能识别）
    return SubtitleDownloadResult(files: [
      SubtitleFile(name: '$cid.$ext', bytes: bytes, ext: ext),
    ]);
  }

  // ============================================================
  // 编码解码（UTF-8 优先，GBK 兜底）
  // ============================================================

  String _decodeText(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {}
    try {
      return gbk.decode(bytes);
    } catch (_) {}
    return latin1.decode(bytes);
  }

  // ============================================================
  // SMI → SRT 转换
  // ============================================================

  String _smiToSrt(String smi) {
    // SMI 结构：<SYNC Start=毫秒> + 一段 HTML 文本，一直显示到下一个 SYNC
    final regex = RegExp(
      r'<sync[^>]*\bstart\s*=\s*"?(\d+)"?[^>]*>([\s\S]*?)(?=<sync|<\/body|$)',
      caseSensitive: false,
    );
    final syncs = <({int start, String body})>[];
    for (final m in regex.allMatches(smi)) {
      final start = int.tryParse(m.group(1) ?? '');
      if (start == null) continue;
      syncs.add((start: start, body: m.group(2) ?? ''));
    }
    if (syncs.isEmpty) return '';

    final buffer = StringBuffer();
    int idx = 0;
    for (int i = 0; i < syncs.length; i++) {
      final content = _stripHtml(syncs[i].body);
      if (content.trim().isEmpty) continue;

      final start = syncs[i].start;
      final end = i < syncs.length - 1
          ? syncs[i + 1].start
          : syncs[i].start + 2000;
      idx++;

      buffer.writeln('$idx');
      buffer.writeln('${_formatSrtTime(start)} --> ${_formatSrtTime(end)}');
      buffer.writeln(content);
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _stripHtml(String text) {
    return text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  String _formatSrtTime(int ms) {
    final total = ms < 0 ? 0 : ms;
    final h = total ~/ 3600000;
    final m = (total % 3600000) ~/ 60000;
    final s = (total % 60000) ~/ 1000;
    final frac = total % 1000;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')},'
        '${frac.toString().padLeft(3, '0')}';
  }

  // ============================================================
  // 工具
  // ============================================================

  String _safeStr(dynamic value) {
    if (value == null) return '';
    final s = value.toString().trim();
    if (s == 'undefined' || s == 'null') return '';
    return s;
  }

  @override
  void dispose() {
    _dio.close(force: true);
  }
}