import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:yuanying/http/init.dart';
import '../models/fnos_media_item.dart';
import 'fnos_auth_utils.dart';

class FnosApiService {
  /// 复用项目全局 Dio（含 HTTP2、代理等设置）
  Dio get _dio => HttpClientFactory.dio;

  /// 通用请求头
  Map<String, String> _headers({
    required String path,
    String? token,
    String? cookie,
    String? bodyStr,
    Map<String, dynamic>? query,
    bool isImage = false,
  }) {
    final h = <String, String>{
      'Authx': FnosAuthUtils.genAuthx(path, bodyStr, query: query),
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/143.0.0.0 Safari/537.36',
      // 飞牛服务端靠这两个头识别"新版 web 客户端"，
      // 缺失会导致媒体库列表不完整 / 直播库隐藏
      'x-trim-client': 'web',
      'x-trim-client-version': '616',
      'Cookie':
          (cookie != null && cookie.isNotEmpty) ? cookie : 'mode=relay',
    };
    if (!isImage) {
      h['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = token;
    }
    return h;
  }

  // ============================================================
  // 登录
  // ============================================================
  Future<Map<String, dynamic>> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    const path = '/v/api/v1/login';
    final body = <String, dynamic>{
      'app_name': 'trimemedia-web',
      'username': username,
      'password': password,
      'nonce': FnosAuthUtils.generateNonce(),
    };
    final bodyStr = jsonEncode(body);
    final resp = await _dio.post(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, bodyStr: bodyStr),
      ),
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }

  // ============================================================
  // 用户信息（校验 token）
  // ============================================================
  Future<Map<String, dynamic>> getUserInfo({
    required String baseUrl,
    required String token,
  }) async {
    const path = '/v/api/v1/user/info';
    final resp = await _dio.get(
      '$baseUrl$path',
      options: Options(headers: _headers(path: path, token: token)),
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }

  // ============================================================
  // 媒体库列表
  // ============================================================
  Future<List<FnosMediaDbItem>> getMediaDbList({
    required String baseUrl,
    required String token,
  }) async {
    const path = '/v/api/v1/mediadb/list';
    final resp = await _dio.get(
      '$baseUrl$path',
      options: Options(headers: _headers(path: path, token: token)),
    );
    final data = resp.data['data'];
    if (data is! List) return [];
    return data
        .map((e) => FnosMediaDbItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ============================================================
  // 条目列表（分页）
  // ============================================================
  Future<List<FnosPlayListItem>> getItemList({
    required String baseUrl,
    required String token,
    required String ancestorGuid,
    int page = 1,
    int pageSize = 40,
    String sortType = 'DESC',
    String sortColumn = 'create_time',
    List<String> types = const ['Movie', 'TV', 'Directory', 'Video', 'LiveChannel'],
    String? keyword,
  }) async {
    const path = '/v/api/v1/item/list';
    final body = <String, dynamic>{
      'ancestor_guid': ancestorGuid,
      'tags': {'type': types},
      'exclude_grouped_video': 1,
      'sort_type': sortType,
      'sort_column': sortColumn,
      'page': page,
      'page_size': pageSize,
    };
    if (keyword != null && keyword.isNotEmpty) {
      body['keyword'] = keyword;
    }
    final bodyStr = jsonEncode(body);
    final resp = await _dio.post(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, token: token, bodyStr: bodyStr),
      ),
    );
    final data = resp.data['data'];
    if (data is! Map) return [];
    final list = data['list'];
    if (list is! List) return [];
    return list
        .map((e) =>
            FnosPlayListItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ============================================================
  // 播放信息
  // ============================================================
  Future<FnosPlayInfoResponse> getPlayInfo({
    required String baseUrl,
    required String token,
    required String itemGuid,
  }) async {
    const path = '/v/api/v1/play/info';
    final body = <String, dynamic>{'item_guid': itemGuid};
    final bodyStr = jsonEncode(body);
    final resp = await _dio.post(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, token: token, bodyStr: bodyStr),
      ),
    );
    if (resp.data['code'] != 0 || resp.data['data'] == null) {
      throw Exception('play/info 失败: ${resp.data['msg']}');
    }
    return FnosPlayInfoResponse.fromJson(
      Map<String, dynamic>.from(resp.data['data'] as Map),
    );
  }

  // ============================================================
  // 条目详情
  // ============================================================
  Future<Map<String, dynamic>> getItemDetail({
    required String baseUrl,
    required String token,
    required String guid,
  }) async {
    final path = '/v/api/v1/item/$guid';
    final resp = await _dio.get(
      '$baseUrl$path',
      options: Options(headers: _headers(path: path, token: token)),
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }

  // ============================================================
  // 演职员
  // ============================================================
  Future<List<Map<String, dynamic>>> getPersonList({
    required String baseUrl,
    required String token,
    required String itemGuid,
  }) async {
    final path = '/v/api/v1/person/list/$itemGuid';
    final body = <String, dynamic>{'page': 1, 'page_size': 200};
    final bodyStr = jsonEncode(body);
    final resp = await _dio.post(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, token: token, bodyStr: bodyStr),
      ),
    );
    final data = resp.data['data'];
    if (data is! Map) return [];
    final list = data['list'];
    if (list is! List) return [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ============================================================
  // 季列表 / 集列表
  // ============================================================
  Future<List<FnosPlayListItem>> getSeasonList({
    required String baseUrl,
    required String token,
    required String tvGuid,
  }) async {
    final path = '/v/api/v1/season/list/$tvGuid';
    final resp = await _dio.get(
      '$baseUrl$path',
      options: Options(headers: _headers(path: path, token: token)),
    );
    final data = resp.data['data'];
    if (data is! List) return [];
    return data
        .map((e) =>
            FnosPlayListItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<FnosPlayListItem>> getEpisodeList({
    required String baseUrl,
    required String token,
    required String seasonGuid,
  }) async {
    final path = '/v/api/v1/episode/list/$seasonGuid';
    final resp = await _dio.get(
      '$baseUrl$path',
      options: Options(headers: _headers(path: path, token: token)),
    );
    final data = resp.data['data'];
    if (data is! List) return [];
    return data
        .map((e) =>
            FnosPlayListItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ============================================================
  // 继续观看（服务端播放记录）
  // ============================================================
  Future<List<FnosPlayListItem>> getPlayList({
    required String baseUrl,
    required String token,
  }) async {
    const path = '/v/api/v1/play/list';
    final resp = await _dio.get(
      '$baseUrl$path',
      options: Options(headers: _headers(path: path, token: token)),
    );
    final data = resp.data['data'];
    if (data is! List) return [];
    return data
        .map((e) =>
            FnosPlayListItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ============================================================
  // 图片 URL 与请求头
  // ============================================================
  static String imageUrl(String baseUrl, String path, {int width = 400}) {
    if (path.isEmpty) return '';
    final p = path.startsWith('/') ? path : '/$path';
    return '$baseUrl/v/api/v1/sys/img$p?w=$width';
  }

  /// 图片请求头（CachedNetworkImage / Image.network 用）
  Map<String, String> imageHeaders({String? token}) {
    final h = <String, String>{
      'Authx': FnosAuthUtils.genAuthx('/v/api/v1/sys/img', null),
      'Cookie': 'mode=relay',
    };
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = token;
    }
    return h;
  }

  // ============================================================
  // 播放流程：stream + play/play
  // ============================================================

  /// 获取媒体流信息（video_stream / audio_streams / subtitle_streams）
  ///
  /// 必须在 play/info 之后调用，用 play/info 返回的 media_guid
  Future<FnosStreamResponse> getStreamInfo({
    required String baseUrl,
    required String token,
    required String mediaGuid,
    required String accountMd5,
  }) async {
    const path = '/v/api/v1/stream';
    final body = <String, dynamic>{
      'header': {
        'User-Agent': [
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/143.0.0.0 Safari/537.36',
        ],
      },
      'level': 1,
      'media_guid': mediaGuid,
      'ip': accountMd5,
      'nonce':
          (100000 + DateTime.now().millisecondsSinceEpoch % 900000)
              .toString(),
    };
    final bodyStr = jsonEncode(body);
    final resp = await _dio.post(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, token: token, bodyStr: bodyStr),
      ),
    );
    if (resp.data['code'] != 0) {
      throw Exception('stream 失败: ${resp.data['msg']}');
    }
    return FnosStreamResponse.fromJson(
      Map<String, dynamic>.from(resp.data['data'] as Map),
    );
  }

  /// 解析最终播放链接（play/play）
  ///
  /// 服务端根据客户端能力决定返回直链还是 HLS，
  /// 返回的 play_link 自带签名，可直接给播放器使用。
  Future<String> resolvePlayLink({
    required String baseUrl,
    required String token,
    required String mediaGuid,
    required String videoGuid,
    required String audioGuid,
    required String videoEncoder,
    required String resolution,
    required int bitrate,
    required int startTimestamp,
    required String subtitleGuid,
    int channels = 2,
    int forcedSdr = 0,
  }) async {
    const path = '/v/api/v1/play/play';
    final body = <String, dynamic>{
      'media_guid': mediaGuid,
      'video_guid': videoGuid,
      'video_encoder': videoEncoder,
      'resolution': resolution,
      'bitrate': bitrate,
      'startTimestamp': startTimestamp,
      'audio_encoder': 'aac',
      'audio_guid': audioGuid,
      'subtitle_guid': subtitleGuid,
      'channels': channels,
      'forced_sdr': forcedSdr,
    };
    final bodyStr = jsonEncode(body);

    final resp = await _dio.post(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, token: token, bodyStr: bodyStr),
      ),
    );

    if (resp.data['code'] != 0 || resp.data['data'] == null) {
      throw Exception(
        'play/play 失败: code=${resp.data['code']} msg=${resp.data['msg']}',
      );
    }
    final playLink = resp.data['data']['play_link']?.toString();
    if (playLink == null || playLink.isEmpty) {
      throw Exception('play/play 未返回 play_link');
    }
    return playLink;
  }

  // ============================================================
  // 播放 URL（供通用播放页使用）
  // ============================================================
  /// 飞牛媒体流地址
  ///
  /// 飞牛服务端通过 `Authorization` 头鉴权。因为项目通用播放页
  /// 通过 URL 传递播放地址（参考 Emby 的 `?api_key=`），这里把 token
  /// 拼在 query 中；若服务端不支持 query token，需要在通用播放页
  /// 增加 header 支持，或改用 `directUrl` + `http_headers` 方式。
  static String streamUrl({
    required String baseUrl,
    required String mediaGuid,
    required String token,
  }) {
    return '$baseUrl/v/api/v1/media/range/$mediaGuid?Authorization=$token';
  }

  // ============================================================
  // 收藏列表
  // ============================================================

  /// 收藏列表（POST /v/api/v1/item/favorite/list）
  ///
  /// [types] 是当前 Tab 对应的条目类型列表，例如 `['Movie']`
  Future<List<FnosPlayListItem>> getFavoriteList({
    required String baseUrl,
    required String token,
    required List<String> types,
    int page = 1,
    int pageSize = 40,
  }) async {
    const path = '/v/api/v1/favorite/list';
    final body = <String, dynamic>{
      'tags': {'type': types},
      'page': page,
      'page_size': pageSize,
      'sort_column': 'create_time',
      'sort_type': 'DESC',
    };
    final bodyStr = jsonEncode(body);

    final resp = await _dio.post(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, token: token, bodyStr: bodyStr),
      ),
    );

    // ignore: avoid_print
    print('=== favorite/list response ===');
    // ignore: avoid_print
    print('  statusCode=${resp.statusCode}');

    if (resp.data['code'] != 0) {
      throw Exception('favorite/list 失败: ${resp.data['msg']}');
    }

    final data = resp.data['data'];
    if (data is! Map) return [];
    final list = (data['list'] as List?) ?? [];
    return list
        .map((e) =>
            FnosPlayListItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ============================================================
  // 收藏 / 已看
  // ============================================================

  Future<bool> addFavorite({
    required String baseUrl,
    required String token,
    required String itemGuid,
  }) async {
    const path = '/v/api/v1/item/favorite';
    final body = <String, dynamic>{'item_guid': itemGuid};
    final bodyStr = jsonEncode(body);

    final resp = await _dio.put(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, token: token, bodyStr: bodyStr),
      ),
    );

    return _isSuccessResponse(resp);
  }

  Future<bool> removeFavorite({
    required String baseUrl,
    required String token,
    required String itemGuid,
  }) async {
    const path = '/v/api/v1/item/favorite';
    final body = <String, dynamic>{'item_guid': itemGuid};
    final bodyStr = jsonEncode(body);

    final resp = await _dio.delete(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, token: token, bodyStr: bodyStr),
      ),
    );

    return _isSuccessResponse(resp);
  }

  Future<bool> markWatched({
    required String baseUrl,
    required String token,
    required String itemGuid,
  }) async {
    const path = '/v/api/v1/watched';
    final body = <String, dynamic>{'item_guid': itemGuid};
    final bodyStr = jsonEncode(body);

    final resp = await _dio.post(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, token: token, bodyStr: bodyStr),
      ),
    );

    return _isSuccessResponse(resp);
  }

  Future<bool> markUnwatched({
    required String baseUrl,
    required String token,
    required String itemGuid,
  }) async {
    const path = '/v/api/v1/watched';
    final body = <String, dynamic>{'item_guid': itemGuid};
    final bodyStr = jsonEncode(body);

    final resp = await _dio.delete(
      '$baseUrl$path',
      data: body,
      options: Options(
        headers: _headers(path: path, token: token, bodyStr: bodyStr),
      ),
    );

    return _isSuccessResponse(resp);
  }

  /// 宽容的成功判断
  ///
  /// 服务端可能返回多种格式：
  /// - `null`（纯 200）
  /// - `true`
  /// - `{code: 0, msg: ""}`
  /// - `{code: 0, data: true}`
  /// - `{success: true}`
  bool _isSuccessResponse(Response resp) {
    final status = resp.statusCode ?? 0;
    if (status != 200 && status != 204) return false;

    final data = resp.data;
    if (data == null) return true; // 空 body 视为成功
    if (data is bool) return data;
    if (data is Map) {
      // 有 code 字段：必须以 0 为准
      if (data.containsKey('code')) {
        return data['code'] == 0;
      }
      // 有 success 字段
      if (data.containsKey('success')) {
        return data['success'] == true;
      }
      // 有 data 字段
      if (data.containsKey('data') && data['data'] is bool) {
        return data['data'] == true;
      }
      // 其他情况：无 code 字段、无 success、无 data → 视为成功
      return true;
    }
    return false;
  }

  // ============================================================
  // 搜索
  // ============================================================

  /// 全局搜索（GET /v/api/v1/search/list?q=关键词）
  ///
  /// 返回结果包含各种类型（Movie / TV / Person / LiveChannel 等）
  Future<List<FnosPlayListItem>> search({
    required String baseUrl,
    required String token,
    required String keyword,
  }) async {
    const path = '/v/api/v1/search/list';
    final query = <String, dynamic>{'q': keyword};

    // ignore: avoid_print
    print('=== search q=$keyword ===');

    final resp = await _dio.get(
      '$baseUrl$path',
      queryParameters: query,
      options: Options(
        headers: _headers(
          path: path,
          token: token,
          query: query,
        ),
      ),
    );

    // ignore: avoid_print
    print('  status=${resp.statusCode} code=${resp.data['code']}');

    if (resp.data['code'] != 0) {
      throw Exception('search 失败: ${resp.data['msg']}');
    }
    final data = resp.data['data'];
    if (data is! List) return [];
    return data
        .map((e) =>
            FnosPlayListItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}