import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:yuanying/http/init.dart';
import '../models/emby_media_item.dart';
import '../models/emby_playback_info.dart';

class EmbyApiService {
  static const String _clientInfo =
      'MediaBrowser Client="Emby Theater", Device="Flutter", DeviceId="emby_theater_flutter_001", Version="1.0.0"';

  Dio get _dio => HttpClientFactory.dio;

  // ------------------------------------------------------------
  // 公开信息（无需 Token）
  // ------------------------------------------------------------
  Future<Map<String, dynamic>> getPublicInfo(String baseUrl) async {
    final response = await _dio.get('$baseUrl/System/Info/Public');
    return response.data as Map<String, dynamic>;
  }

  // ------------------------------------------------------------
  // 登录：POST /Users/AuthenticateByName
  // ------------------------------------------------------------
  Future<Map<String, dynamic>> authenticateByName({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final response = await _dio.post(
      '$baseUrl/Users/AuthenticateByName',
      options: Options(headers: {
        'X-Emby-Authorization': _clientInfo,
        'Content-Type': 'application/json',
      }),
      data: {'Username': username, 'Pw': password},
    );
    return response.data as Map<String, dynamic>;
  }

  // ------------------------------------------------------------
  // 内部通用请求
  // ------------------------------------------------------------
  Future<dynamic> _get(
    String url,
    String token, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _dio.get(
      url,
      options: Options(headers: {
        'X-Emby-Authorization': '$_clientInfo, Token="$token"',
      }),
      queryParameters: query,
    );
    return response.data;
  }

  Future<dynamic> _post(
    String url,
    String token, {
    Map<String, dynamic>? query,
    dynamic data,
  }) async {
    final response = await _dio.post(
      url,
      options: Options(headers: {
        'X-Emby-Authorization': '$_clientInfo, Token="$token"',
        'Content-Type': 'application/json',
      }),
      queryParameters: query,
      data: data,
    );
    return response.data;
  }

  /// DELETE 请求（用于取消收藏）
  Future<dynamic> _delete(
    String url,
    String token, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _dio.delete(
      url,
      options: Options(headers: {
        'X-Emby-Authorization': '$_clientInfo, Token="$token"',
      }),
      queryParameters: query,
    );
    return response.data;
  }

  // ============================================================
  // 媒体库列表
  // ============================================================
  Future<List<EmbyMediaItem>> getUserViews(
    String userId,
    String token,
    String baseUrl,
  ) async {
    final data = await _get('$baseUrl/Users/$userId/Views', token);
    final items = (data['Items'] as List?) ?? [];
    return items
        .map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // 继续观看
  // ============================================================
  Future<List<EmbyMediaItem>> getResumeItems(
    String userId,
    String token,
    String baseUrl,
  ) async {
    final data = await _get(
      '$baseUrl/Users/$userId/Items/Resume',
      token,
      query: {
        'Limit': 20,
        'Recursive': true,
        'MediaTypes': 'Video',
        'Fields':
            'Overview,UserData,ImageTags,SeriesId,SeasonId,AlbumId,SeriesPrimaryImageTag',
        'EnableImageTypes': 'Primary,Backdrop',
        'ImageTypeLimit': 1,
      },
    );
    final items = (data['Items'] as List?) ?? [];
    return items
        .map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // 最新内容（按库）
  // ============================================================
  Future<List<EmbyMediaItem>> getLatestItems(
    String userId,
    String token,
    String baseUrl,
    String parentId, {
    int limit = 16,
  }) async {
    final response = await _get(
      '$baseUrl/Users/$userId/Items/Latest',
      token,
      query: {
        'ParentId': parentId,
        'Limit': limit,
        'Fields': 'Overview,UserData',
      },
    );

    if (response is List) {
      return response
          .map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (response is Map && response['Items'] is List) {
      return (response['Items'] as List)
          .map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // ============================================================
  // 季列表
  // ============================================================
  Future<List<EmbyMediaItem>> getSeasons(
    String userId,
    String token,
    String baseUrl,
    String seriesId,
  ) async {
    final data = await _get(
      '$baseUrl/Shows/$seriesId/Seasons',
      token,
      query: {
        'UserId': userId,
        'Fields': 'Overview,Genres,People',
      },
    );
    final items = (data['Items'] as List?) ?? [];
    return items
        .map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // 剧集列表
  // ============================================================
  Future<List<EmbyMediaItem>> getEpisodes(
    String userId,
    String token,
    String baseUrl,
    String seriesId,
    String seasonId,
  ) async {
    final data = await _get(
      '$baseUrl/Shows/$seriesId/Episodes',
      token,
      query: {
        'UserId': userId,
        'SeasonId': seasonId,
        'Fields': 'Overview,UserData,MediaSources,SeriesId,SeasonId',
      },
    );
    final items = (data['Items'] as List?) ?? [];
    return items
        .map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // 专辑曲目
  // ============================================================
  Future<List<EmbyMediaItem>> getAlbumTracks(
    String userId,
    String token,
    String baseUrl,
    String albumId,
  ) async {
    final data = await _get(
      '$baseUrl/Users/$userId/Items',
      token,
      query: {
        'ParentId': albumId,
        'IncludeItemTypes': 'Audio',
        'Recursive': true,
        'Fields': 'Overview,UserData,MediaSources,Artists,Album,AlbumArtist',
        'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
        'SortOrder': 'Ascending',
        'Limit': 500,
      },
    );
    final items = (data['Items'] as List?) ?? [];
    return items
        .map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // 库内分页列表
  // ============================================================
  Future<Map<String, dynamic>> getLibraryItems({
    required String userId,
    required String token,
    required String baseUrl,
    required String parentId,
    int startIndex = 0,
    int limit = 40,
    String? searchTerm,
    String includeItemTypes = 'Movie,Series',
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    bool recursive = true,
  }) async {
    final query = <String, dynamic>{
      'ParentId': parentId,
      'StartIndex': startIndex,
      'Limit': limit,
      'Fields': 'Overview,UserData,MediaSources',
      'IncludeItemTypes': includeItemTypes,
      'Recursive': recursive,
      'SortBy': sortBy,
      'SortOrder': sortOrder,
    };
    if (searchTerm != null && searchTerm.isNotEmpty) {
      query['SearchTerm'] = searchTerm;
    }
    final data =
        await _get('$baseUrl/Users/$userId/Items', token, query: query);
    return data as Map<String, dynamic>;
  }

  // ============================================================
  // 收藏列表
  // ============================================================
  /// 获取当前用户的收藏列表
  ///
  /// 通过 `Filters=IsFavorite` 过滤出 UserData.IsFavorite=true 的条目
  Future<Map<String, dynamic>> getFavoriteItems({
    required String userId,
    required String token,
    required String baseUrl,
    int startIndex = 0,
    int limit = 40,
    String includeItemTypes = 'Movie,Series,Episode',
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
  }) async {
    final query = <String, dynamic>{
      'Filters': 'IsFavorite',
      'StartIndex': startIndex,
      'Limit': limit,
      'Fields': 'Overview,UserData,MediaSources',
      'IncludeItemTypes': includeItemTypes,
      'Recursive': true,
      'SortBy': sortBy,
      'SortOrder': sortOrder,
    };
    final data =
        await _get('$baseUrl/Users/$userId/Items', token, query: query);
    return data as Map<String, dynamic>;
  }

  // ============================================================
  // 播放历史
  // ============================================================
  /// 获取已播放过的媒体列表，按最后播放时间倒序
  ///
  /// - `Filters=IsPlayed` 只返回已看过的
  /// - `SortBy=DatePlayed` 按播放时间排序
  /// - `IncludeItemTypes=Movie,Episode` 只返回电影/剧集（不返回 Series 层级）
  Future<Map<String, dynamic>> getPlayHistory({
    required String userId,
    required String token,
    required String baseUrl,
    int startIndex = 0,
    int limit = 40,
    String includeItemTypes = 'Movie,Episode',
    String sortOrder = 'Descending',
  }) async {
    final query = <String, dynamic>{
      'Filters': 'IsPlayed',
      'StartIndex': startIndex,
      'Limit': limit,
      'Fields': 'Overview,UserData,MediaSources,SeriesId,SeasonId,AlbumId',
      'IncludeItemTypes': includeItemTypes,
      'Recursive': true,
      'SortBy': 'DatePlayed',
      'SortOrder': sortOrder,
    };
    final data =
        await _get('$baseUrl/Users/$userId/Items', token, query: query);
    return data as Map<String, dynamic>;
  }

  // ============================================================
  // 收藏 / 取消收藏
  // ============================================================
  /// 添加收藏
  ///
  /// Emby 有两种端点：
  /// - `/Users/{userId}/FavoriteItems/{itemId}` （主流，兼容 Emby 4.6+）
  /// - `/Users/{userId}/Favorites/{itemId}`      （旧版别名）
  Future<void> markFavorite({
    required String userId,
    required String token,
    required String baseUrl,
    required String itemId,
  }) async {
    await _post('$baseUrl/Users/$userId/FavoriteItems/$itemId', token);
  }

  /// 取消收藏
  Future<void> unmarkFavorite({
    required String userId,
    required String token,
    required String baseUrl,
    required String itemId,
  }) async {
    await _delete('$baseUrl/Users/$userId/FavoriteItems/$itemId', token);
  }

  // ============================================================
  // 从播放历史中移除
  // ============================================================
  /// 移除某个条目的"已播放"标记（即从历史记录中消失）
  ///
  /// Emby 端点是 `DELETE /Users/{userId}/PlayedItems/{itemId}`。
  /// 调用后该条目下次 `Filters=IsPlayed` 查询就不会再返回。
  Future<void> removeFromHistory({
    required String userId,
    required String token,
    required String baseUrl,
    required String itemId,
  }) async {
    await _delete('$baseUrl/Users/$userId/PlayedItems/$itemId', token);
  }

  // ============================================================
  // 单个媒体详情
  // Fields 增加 UserData —— 让详情页能读到 IsFavorite 状态
  // ============================================================
  Future<EmbyMediaItem> getItemInfo(
    String userId,
    String token,
    String baseUrl,
    String itemId,
  ) async {
    final data = await _get(
      '$baseUrl/Users/$userId/Items/$itemId',
      token,
      query: {
          'Fields':
            'Overview,Genres,People,MediaSources,MediaStreams,MediaType,Container,Album,AlbumArtist,Artists,AlbumId,SeriesId,SeasonId,UserData',
      },
    );
    return EmbyMediaItem.fromJson(data as Map<String, dynamic>);
  }

  // ============================================================
  // 播放信息
  // ============================================================
  Future<Map<String, dynamic>> getPlaybackInfo({
    required String userId,
    required String token,
    required String baseUrl,
    required String itemId,
  }) async {
    final data = await _post(
      '$baseUrl/Items/$itemId/PlaybackInfo',
      token,
      query: {'UserId': userId},
      data: {
        'UserId': userId,
        'AutoOpenLiveStream': true,
        'IsPlayback': true,
        'MaxStreamingBitrate': 140000000,
      },
    );
    return data as Map<String, dynamic>;
  }

  // ============================================================
  // 播放 URL 构造
  // ============================================================
  static String directStreamUrl(
    String baseUrl,
    String itemId,
    String mediaSourceId,
    String token,
    String container,
  ) {
    return '$baseUrl/Videos/$itemId/stream.$container'
        '?MediaSourceId=$mediaSourceId'
        '&Static=true'
        '&api_key=$token';
  }

  static String hlsStreamUrl(
    String baseUrl,
    String itemId,
    String mediaSourceId,
    String token,
  ) {
    return '$baseUrl/Videos/$itemId/master.m3u8'
        '?MediaSourceId=$mediaSourceId'
        '&api_key=$token'
        '&VideoCodec=h264'
        '&AudioCodec=aac'
        '&SubtitleMethod=Hls';
  }

  static String audioDirectStreamUrl(
    String baseUrl,
    String itemId,
    String mediaSourceId,
    String token,
    String container,
  ) {
    return '$baseUrl/Audio/$itemId/stream.$container'
        '?MediaSourceId=$mediaSourceId'
        '&Static=true'
        '&api_key=$token';
  }

  static String audioUniversalStreamUrl(
    String baseUrl,
    String itemId,
    String mediaSourceId,
    String token, {
    String container = 'mp3',
  }) {
    return '$baseUrl/Audio/$itemId/universal'
        '?MediaSourceId=$mediaSourceId'
        '&api_key=$token'
        '&Container=$container'
        '&TranscodingContainer=ts'
        '&TranscodingProtocol=hls'
        '&AudioCodec=aac'
        '&EnableRedirection=true'
        '&EnableRemoteMedia=false';
  }

  // ============================================================
  // 图片 URL
  // ============================================================
  static String primaryImage(
    String baseUrl,
    String itemId, {
    int maxWidth = 300,
    String? tag,
  }) {
    final query = StringBuffer('maxWidth=$maxWidth');
    if (tag != null && tag.isNotEmpty) {
      query.write('&tag=$tag');
    }
    return '$baseUrl/Items/$itemId/Images/Primary?$query';
  }

  static String backdropImage(
    String baseUrl,
    String itemId, {
    int maxWidth = 1280,
  }) {
    return '$baseUrl/Items/$itemId/Images/Backdrop/0?maxWidth=$maxWidth';
  }

  static String albumCoverImage(
    String baseUrl,
    String itemId, {
    int maxWidth = 300,
  }) {
    return '$baseUrl/Items/$itemId/Images/Primary?maxWidth=$maxWidth';
  }

  // ============================================================
  // 根据 item 类型返回合适的背景图 URL（与详情页顶部一致）
  //
  // 规则：
  // - Episode → Series 的 Backdrop（详情页顶部同款）
  // - Audio   → Album 的 Backdrop
  // - 其他    → 自身的 Backdrop
  // ============================================================
  static String displayBackdrop(
    String baseUrl,
    EmbyMediaItem item, {
    int maxWidth = 1280,
  }) {
    // Episode → Series Backdrop
    if (item.isEpisode &&
        item.seriesId != null &&
        item.seriesId!.isNotEmpty) {
      return '$baseUrl/Items/${item.seriesId}/Images/Backdrop/0?maxWidth=$maxWidth';
    }
    // Audio → Album Backdrop
    if (item.isAudio &&
        item.albumId != null &&
        item.albumId!.isNotEmpty) {
      return '$baseUrl/Items/${item.albumId}/Images/Backdrop/0?maxWidth=$maxWidth';
    }
    // 其他 → 自身 Backdrop
    return backdropImage(baseUrl, item.id, maxWidth: maxWidth);
  }

  // ============================================================
  // 根据 item 类型返回合适的封面图 URL
  //
  // 规则：
  // - Episode → 用 Series 的海报（Emby 网页端行为）
  // - Audio   → 用 Album 的封面
  // - 其他    → 用自己的 Primary
  // ============================================================
  static String displayPoster(
    String baseUrl,
    EmbyMediaItem item, {
    int maxWidth = 300,
  }) {
    // Episode → Series 海报
    if (item.isEpisode &&
        item.seriesId != null &&
        item.seriesId!.isNotEmpty) {
      return '$baseUrl/Items/${item.seriesId}/Images/Primary?maxWidth=$maxWidth';
    }
    // Audio → Album 封面
    if (item.isAudio &&
        item.albumId != null &&
        item.albumId!.isNotEmpty) {
      return '$baseUrl/Items/${item.albumId}/Images/Primary?maxWidth=$maxWidth';
    }
    // 其他 → 自己的 Primary
    return primaryImage(baseUrl, item.id, maxWidth: maxWidth);
  }

  // ============================================================
  // 全库最近添加
  // ============================================================
  Future<List<EmbyMediaItem>> getRecentItems(
    String userId,
    String token,
    String baseUrl, {
    int limit = 20,
  }) async {
    final data = await _get(
      '$baseUrl/Users/$userId/Items/Latest',
      token,
      query: {
        'Limit': limit,
        'Fields': 'Overview,UserData',
      },
    );
    if (data is List) {
      return data
          .map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data is Map && data['Items'] is List) {
      return (data['Items'] as List)
          .map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // ============================================================
  // 文件下载 URL
  // ============================================================
  static String getFileStreamUrl(
    String baseUrl,
    String itemId,
    String token,
  ) {
    return '$baseUrl/Items/$itemId/File?api_key=$token&Static=true';
  }
}