import 'package:dio/dio.dart';

import '../models/subtitle_file.dart';
import '../models/subtitle_search_result.dart';
import '../models/subtitle_site_type.dart';
import '../utils/subtitle_utils.dart';
import 'subtitle_site_service.dart';

/// assrt（射手网）服务：Token 认证，官方 API api.assrt.net/v1
class AssrtService implements SubtitleSiteService {
  final String token;
  final Dio _dio;
  final _SimpleRateLimiter _limiter = _SimpleRateLimiter(maxPerMinute: 20);

  /// assrt 的语言代码 → 中文名
  /// 参考官方文档与实测：langlist 的 key 是 `langzh_chs` 这类
  static const _langMap = <String, String>{
    'langzh_chs': '简体中文',
    'langzh_cht': '繁体中文',
    'langzh': '中文',
    'langchs': '简体中文',
    'langcht': '繁体中文',
    'langeng': '英文',
    'langeng2': '英文',
    'langja': '日文',
    'langko': '韩文',
    'langfr': '法文',
    'langde': '德文',
    'langes': '西班牙文',
    'langdou': '双语',
  };

  AssrtService(this.token)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        ));

  @override
  SubtitleSiteType get type => SubtitleSiteType.assrt;

  @override
  bool get isConfigured => token.isNotEmpty;

  @override
  Future<List<SubtitleSearchResult>> search(String keyword) async {
    if (token.isEmpty) {
      throw SubtitleSiteException('assrt 未配置 Token');
    }
    await _limiter.acquire();

    final resp = await _dio.get<dynamic>(
      'https://api.assrt.net/v1/sub/search',
      queryParameters: {'token': token, 'q': keyword, 'is_file': 1},
    );

    final data = resp.data;
    final subs = (data is Map
            ? (data['sub']?['subs'] as List?)
            : null) ??
        const [];

    return subs.map<SubtitleSearchResult>((s) {
      if (s is! Map) {
        return SubtitleSearchResult(
          site: type,
          id: '',
          title: '未知',
        );
      }

      // ---- 1. 语言 ----
      final langMap = s['lang'];
      final langKeys = (langMap is Map
              ? (langMap['langlist'] as Map?)?.keys.toList()
              : null) ??
          const [];
      final langText = _formatLangs(langKeys.cast<String>());

      // ---- 2. 标题：native_name 优先，videoname 兜底 ----
      final native = s['native_name'];
      String title;
      if (native is List) {
        title = native.isNotEmpty ? '${native.first}' : '';
      } else {
        title = '${native ?? ''}';
      }
      if (title.isEmpty) {
        title = '${s['videoname'] ?? '未知'}';
      }

      // ---- 3. 副标题：videoname（如果和 title 不同） ----
      final videoname = s['videoname']?.toString();
      String? subtitle;
      if (videoname != null &&
          videoname.isNotEmpty &&
          videoname != title) {
        subtitle = videoname;
      }

      return SubtitleSearchResult(
        site: type,
        id: '${s['id']}',
        title: title,
        subtitle: subtitle,
        language: langText.isEmpty ? null : langText,
        // assrt 不返回格式，为 null
        raw: Map<String, dynamic>.from(s),
      );
    }).toList();
  }

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult item) async {
    if (token.isEmpty) {
      throw SubtitleSiteException('assrt 未配置 Token');
    }
    await _limiter.acquire();

    final detailResp = await _dio.get<dynamic>(
      'https://api.assrt.net/v1/sub/detail',
      queryParameters: {'token': token, 'id': item.id},
    );
    final detailData = detailResp.data;
    final subs = (detailData is Map
            ? (detailData['sub']?['subs'] as List?)
            : null) ??
        const [];
    if (subs.isEmpty) {
      throw SubtitleSiteException('assrt 未找到字幕详情');
    }

    final sub = subs.first;
    if (sub is! Map) {
      throw SubtitleSiteException('assrt 响应格式异常');
    }

    final files = <SubtitleFile>[];
    final fileList = (sub['filelist'] as List?) ?? const [];

    if (fileList.isNotEmpty) {
      for (final f in fileList) {
        if (f is! Map) continue;
        final url = f['url'] as String?;
        if (url == null || url.isEmpty) continue;
        final bytes = await _fetchBytes(url);
        final baseName = '${f['f'] ?? item.id}';
        files.addAll(extractSubtitleFiles(bytes, baseName));
      }
    } else {
      final url = sub['url'] as String?;
      if (url != null && url.isNotEmpty) {
        final bytes = await _fetchBytes(url);
        files.addAll(
          extractSubtitleFiles(bytes, '${sub['videoname'] ?? item.id}'),
        );
      }
    }

    if (files.isEmpty) {
      throw SubtitleSiteException('assrt 无可用下载链接');
    }
    return SubtitleDownloadResult(files: files);
  }

  Future<List<int>> _fetchBytes(String url) async {
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return resp.data ?? const [];
  }

  /// 把 langlist 的 key 转成人类可读文字，如
  /// `['langzh_chs', 'langeng']` → `简体中文/英文`
  String _formatLangs(List<String> keys) {
    final out = <String>{};
    for (final k in keys) {
      final mapped = _langMap[k];
      if (mapped != null) {
        out.add(mapped);
      } else if (k.isNotEmpty) {
        out.add(k);
      }
    }
    return out.join('/');
  }

  @override
  void dispose() {
    _dio.close(force: true);
  }
}

/// 简单的令牌桶限流器（按分钟计数）
class _SimpleRateLimiter {
  final int maxPerMinute;
  final List<DateTime> _times = [];

  _SimpleRateLimiter({required this.maxPerMinute});

  Future<void> acquire() async {
    final now = DateTime.now();
    _times.removeWhere((t) => now.difference(t).inSeconds >= 60);
    if (_times.length >= maxPerMinute) {
      final waitSeconds = 60 - now.difference(_times.first).inSeconds;
      if (waitSeconds > 0) {
        await Future<void>.delayed(Duration(seconds: waitSeconds + 1));
      }
    }
    _times.add(DateTime.now());
  }
}