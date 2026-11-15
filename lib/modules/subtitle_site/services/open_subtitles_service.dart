import 'package:dio/dio.dart';

import '../models/subtitle_file.dart';
import '../models/subtitle_search_result.dart';
import '../models/subtitle_site_type.dart';
import 'subtitle_site_service.dart';

/// OpenSubtitles 服务。
///
/// 认证策略：
/// - API Key 必填（应用级认证）
/// - 用户名 + 密码可选：填入后登录获取 JWT，提升下载额度
/// - 未填账号密码时降级为纯 API Key 模式（额度受限）
class OpenSubtitlesService implements SubtitleSiteService {
  final String apiKey;
  final String? username;
  final String? password;
  final Dio _dio;
  String? _jwt;
  DateTime? _jwtExpire;

  /// OpenSubtitles 的语言码 → 中文名
  /// 只列常用的，其余原样显示
  static const _langMap = <String, String>{
    'zh-cn': '简体中文',
    'zh-tw': '繁体中文',
    'zh': '中文',
    'en': '英文',
    'ja': '日文',
    'ko': '韩文',
    'fr': '法文',
    'de': '德文',
    'es': '西班牙文',
    'it': '意大利文',
    'ru': '俄文',
    'pt-br': '葡萄牙文(巴西)',
    'pt-pt': '葡萄牙文(葡萄牙)',
  };

  OpenSubtitlesService({
    required this.apiKey,
    this.username,
    this.password,
  }) : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.opensubtitles.com/api/v1',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'Api-Key': apiKey,
            'User-Agent': 'Yuanying v2.0.8',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ));

  @override
  SubtitleSiteType get type => SubtitleSiteType.openSubtitles;

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  /// 有账号密码才登录；否则返回 null（纯 API Key 模式）
  Future<String?> _ensureJwt() async {
    final user = username?.trim();
    final pwd = password?.trim();
    if (user == null || user.isEmpty || pwd == null || pwd.isEmpty) {
      return null;
    }
    if (_jwt != null &&
        _jwtExpire != null &&
        DateTime.now().isBefore(_jwtExpire!)) {
      return _jwt;
    }
    try {
      final resp = await _dio.post<dynamic>(
        '/login',
        data: {'username': user, 'password': pwd},
      );
      final data = resp.data;
      final token = data is Map ? data['token'] as String? : null;
      if (token != null && token.isNotEmpty) {
        _jwt = token;
        _jwtExpire = DateTime.now().add(const Duration(hours: 23));
        return token;
      }
    } catch (_) {
      // 登录失败静默降级
    }
    return null;
  }

  @override
  Future<List<SubtitleSearchResult>> search(String keyword) async {
    if (apiKey.isEmpty) {
      throw SubtitleSiteException('OpenSubtitles 未配置 API Key');
    }
    final jwt = await _ensureJwt();

    final resp = await _dio.get<dynamic>(
      '/subtitles',
      queryParameters: {
        'languages': 'zh-cn,en',
        'query': keyword,
      },
      options: Options(headers: {
        if (jwt != null) 'Authorization': 'Bearer $jwt',
      }),
    );

    final respData = resp.data;
    final data =
        (respData is Map ? respData['data'] as List? : null) ?? const [];

    final results = <SubtitleSearchResult>[];
    for (final item in data) {
      if (item is! Map) continue;
      final attrs = item['attributes'];
      if (attrs is! Map) continue;
      final files = (attrs['files'] as List?) ?? const [];
      if (files.isEmpty) continue;
      final file = files.first;
      if (file is! Map) continue;
      final fileId = file['file_id'];
      if (fileId == null) continue;

      final fileName = (file['file_name'] as String?)?.trim() ?? '';
      final release = (attrs['release'] as String?)?.trim();
      final langCode = (attrs['language'] as String?)?.trim();

      // 格式：从文件名扩展名提取
      String? fmt;
      if (fileName.contains('.')) {
        final ext = fileName.split('.').last.toLowerCase();
        if (['srt', 'ass', 'ssa', 'vtt', 'sub'].contains(ext)) {
          fmt = ext.toUpperCase();
        }
      }

      // 语言：code → 中文名
      final langText = (langCode != null && langCode.isNotEmpty)
          ? (_langMap[langCode] ?? langCode)
          : null;

      results.add(SubtitleSearchResult(
        site: type,
        id: '$fileId',
        title: fileName.isNotEmpty
            ? fileName
            : (release != null && release.isNotEmpty ? release : '未知'),
        subtitle: (release != null && release != fileName) ? release : null,
        language: langText,
        format: fmt,
        raw: Map<String, dynamic>.from(item),
      ));
    }
    return results;
  }

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult item) async {
    final jwt = await _ensureJwt();
    final fileId = int.tryParse(item.id);
    if (fileId == null) {
      throw SubtitleSiteException('OpenSubtitles file_id 无效');
    }

    String? link;
    Object? lastError;
    for (var i = 0; i < 3; i++) {
      try {
        final resp = await _dio.post<dynamic>(
          '/download',
          data: {'file_id': fileId},
          options: Options(headers: {
            if (jwt != null) 'Authorization': 'Bearer $jwt',
          }),
        );
        final data = resp.data;
        final url = data is Map ? data['link'] as String? : null;
        if (url != null && url.isNotEmpty) {
          link = url;
          break;
        }
        throw SubtitleSiteException('OpenSubtitles 未返回下载链接');
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode == 503 && i < 2) {
          await Future<void>.delayed(Duration(seconds: 2 << i));
          continue;
        }
        rethrow;
      }
    }

    if (link == null || link.isEmpty) {
      throw SubtitleSiteException(
        'OpenSubtitles 未返回下载链接（免费额度可能已用完，填入账号密码可提升额度）：$lastError',
      );
    }

    final fileResp = await _dio.get<List<int>>(
      link,
      options: Options(responseType: ResponseType.bytes),
    );
    return SubtitleDownloadResult(files: [
      SubtitleFile(
        name: 'opensubtitles_$fileId.srt',
        bytes: fileResp.data ?? const [],
        ext: 'srt',
      ),
    ]);
  }

  @override
  void dispose() {
    _dio.close(force: true);
  }
}