import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:yuanying/http/init.dart';
import '../models/jellyfin_media_item.dart';
import '../models/jellyfin_playback_info.dart';

class JellyfinApiService {
  static const String _clientName = 'YuanYing';
  static const String _deviceName = 'Flutter';
  static const String _deviceId = 'yuanying_jellyfin_flutter_001';
  static const String _version = '1.0.0';

  static String _mediaBrowserHeader({String? token}) {
    final base = 'MediaBrowser Client="$_clientName", '
        'Device="$_deviceName", '
        'DeviceId="$_deviceId", '
        'Version="$_version"';
    if (token != null && token.isNotEmpty) {
      return '$base, Token="$token"';
    }
    return base;
  }

  Dio get _dio => HttpClientFactory.dio;

  // ------------------------------------------------------------
  // 公开信息
  // ------------------------------------------------------------
  Future<Map<String, dynamic>> getPublicInfo(String baseUrl) async {
    final response = await _dio.get('$baseUrl/System/Info/Public');
    return response.data as Map<String, dynamic>;
  }

  // ------------------------------------------------------------
  // 登录
  // ------------------------------------------------------------
  Future<Map<String, dynamic>> authenticateByName({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final response = await _dio.post(
      '$baseUrl/Users/AuthenticateByName',
      options: Options(headers: {
        'Authorization': _mediaBrowserHeader(),
        'Content-Type': 'application/json',
        'Accept': 'application/json',
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
        'Authorization': _mediaBrowserHeader(token: token),
        'Accept': 'application/json',
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
        'Authorization': _mediaBrowserHeader(token: token),
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }),
      queryParameters: query,
      data: data,
    );
    return response.data;
  }

  /// DELETE 请求（取消收藏 / 移除历史）
  Future<dynamic> _delete(
    String url,
    String token, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _dio.delete(
      url,
      options: Options(headers: {
        'Authorization': _mediaBrowserHeader(token: token),
        'Accept': 'application/json',
      }),
      queryParameters: query,
    );
    return response.data;
  }

  // ============================================================
  // 媒体库列表
  // ============================================================
  Future<List<JellyfinMediaItem>> getUserViews(
    String userId,
    String token,
    String baseUrl,
  ) async {
    final data = await _get(
      '$baseUrl/UserViews',
      token,
      query: {'userId': userId},
    );
    final items = (data['Items'] as List?) ?? [];
    return items
        .map((e) => JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // 继续观看
  // ============================================================
  Future<List<JellyfinMediaItem>> getResumeItems(
    String userId,
    String token,
    String baseUrl,
  ) async {
    final data = await _get(
      '$baseUrl/UserItems/Resume',
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
        .map((e) => JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // 最新内容（按库）
  // ============================================================
  Future<List<JellyfinMediaItem>> getLatestItems(
    String userId,
    String token,
    String baseUrl,
    String parentId, {
    int limit = 16,
  }) async {
    final response = await _get(
      '$baseUrl/Items/Latest',
      token,
      query: {
        'userId': userId,
        'ParentId': parentId,
        'Limit': limit,
        'Fields': 'Overview,UserData',
      },
    );
    if (response is List) {
      return response
          .map((e) => JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (response is Map && response['Items'] is List) {
      return (response['Items'] as List)
          .map((e) => JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // ============================================================
  // 全库最近添加
  // ============================================================
  Future<List<JellyfinMediaItem>> getRecentItems(
    String userId,
    String token,
    String baseUrl, {
    int limit = 20,
  }) async {
    final data = await _get(
      '$baseUrl/Items/Latest',
      token,
      query: {
        'userId': userId,
        'Limit': limit,
        'Fields': 'Overview,UserData',
      },
    );
    if (data is List) {
      return data
          .map((e) => JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data is Map && data['Items'] is List) {
      return (data['Items'] as List)
          .map((e) => JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // ============================================================
  // 季列表
  // ============================================================
  Future<List<JellyfinMediaItem>> getSeasons(
    String userId,
    String token,
    String baseUrl,
    String seriesId,
  ) async {
    final data = await _get(
      '$baseUrl/Shows/$seriesId/Seasons',
      token,
      query: {
        'userId': userId,
        'Fields': 'Overview,Genres,People',
      },
    );
    final items = (data['Items'] as List?) ?? [];
    return items
        .map((e) => JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // 剧集列表
  // ============================================================
  Future<List<JellyfinMediaItem>> getEpisodes(
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
        'userId': userId,
        'SeasonId': seasonId,
        'Fields': 'Overview,UserData,MediaSources,SeriesId,SeasonId',
      },
    );
    final items = (data['Items'] as List?) ?? [];
    return items
        .map((e) => JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ============================================================
  // 专辑曲目列表
  // ============================================================
  Future<List<JellyfinMediaItem>> getAlbumTracks(
    String userId,
    String token,
    String baseUrl,
    String albumId,
  ) async {
    final data = await _get(
      '$baseUrl/Items',
      token,
      query: {
        'userId': userId,
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
        .map((e) => JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
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
      'userId': userId,
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
    final data = await _get('$baseUrl/Items', token, query: query);
    return data as Map<String, dynamic>;
  }

  // ============================================================
  // 收藏列表
  // ============================================================
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
      'userId': userId,
      'Filters': 'IsFavorite',
      'StartIndex': startIndex,
      'Limit': limit,
      'Fields': 'Overview,UserData,MediaSources',
      'IncludeItemTypes': includeItemTypes,
      'Recursive': true,
      'SortBy': sortBy,
      'SortOrder': sortOrder,
    };
    final data = await _get('$baseUrl/Items', token, query: query);
    return data as Map<String, dynamic>;
  }

  // ============================================================
  // 播放历史
  // ============================================================
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
      'userId': userId,
      // 改用 IsPlayed + IsResumable：
      //   - IsPlayed：看完的
      //   - IsResumable：看了一半的
      //   两者合并 = "所有播放过的"
      'Filters': 'IsPlayed,IsResumable',
      'StartIndex': startIndex,
      'Limit': limit,
      'Fields': 'Overview,UserData,MediaSources,SeriesId,SeasonId,AlbumId',
      'IncludeItemTypes': includeItemTypes,
      'Recursive': true,
      'SortBy': 'DatePlayed',
      'SortOrder': sortOrder,
    };
    final data = await _get('$baseUrl/Items', token, query: query);
    return data as Map<String, dynamic>;
  }

  // ============================================================
  // 收藏 / 取消收藏
  // ============================================================
  /// 添加收藏（端点与 Jellyfin 相同，MediaBrowser 协议标准）
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
  // ============================================================
  Future<JellyfinMediaItem> getItemInfo(
    String userId,
    String token,
    String baseUrl,
    String itemId,
  ) async {
    final data = await _get(
      '$baseUrl/Items/$itemId',
      token,
      query: {
        'userId': userId,
        'Fields':
            'Overview,Genres,People,MediaSources,MediaStreams,MediaType,Container,Album,AlbumArtist,Artists,AlbumId,SeriesId,SeasonId,UserData',
      },
    );
    return JellyfinMediaItem.fromJson(data as Map<String, dynamic>);
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
      query: {'userId': userId},
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
        '&ApiKey=$token';
  }

  static String hlsStreamUrl(
    String baseUrl,
    String itemId,
    String mediaSourceId,
    String token,
  ) {
    return '$baseUrl/Videos/$itemId/master.m3u8'
        '?MediaSourceId=$mediaSourceId'
        '&ApiKey=$token'
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
        '&ApiKey=$token';
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
        '&ApiKey=$token'
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

  // ============================================================
  // 根据 item 类型返回合适的封面图 URL
  //
  // 规则：
  // - Episode → 用 Series 的海报（Jellyfin 网页端行为）
  // - Audio   → 用 Album 的封面
  // - 其他    → 用自己的 Primary
  // ============================================================
  static String displayPoster(
    String baseUrl,
    JellyfinMediaItem item, {
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

  static String backdropImage(
    String baseUrl,
    String itemId, {
    int maxWidth = 1280,
  }) {
    return '$baseUrl/Items/$itemId/Images/Backdrop/0?maxWidth=$maxWidth';
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
    JellyfinMediaItem item, {
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

  static String albumCoverImage(
    String baseUrl,
    String itemId, {
    int maxWidth = 300,
  }) {
    return '$baseUrl/Items/$itemId/Images/Primary?maxWidth=$maxWidth';
  }

  // ============================================================
  // 文件下载 URL
  // ============================================================
  static String getFileStreamUrl(
    String baseUrl,
    String itemId,
    String token,
  ) {
    return '$baseUrl/Items/$itemId/File?ApiKey=$token&Static=true';
  }

  // ============================================================
  // 播放状态上报（Jellyfin）
  // ============================================================

  /// 上报播放开始
  Future<void> reportPlaybackStart({
    required String userId,
    required String token,
    required String baseUrl,
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    String playMethod = 'DirectPlay',
  }) async {
    try {
      await _post(
        '$baseUrl/Sessions/Playing',
        token,
        query: {'userId': userId},
        data: {
          'ItemId': itemId,
          'MediaSourceId': mediaSourceId,
          'PlaySessionId': playSessionId,
          'PlayMethod': playMethod,
          'PlaylistItemId': 'playlistItem0',
          'CanSeek': true,
          'IsPaused': false,
          'IsMuted': false,
          'PlaybackRate': 1,
          'VolumeLevel': 100,
          'RepeatMode': 'RepeatNone',
          'ShuffleMode': 'Sorted',
          'MaxStreamingBitrate': 140000000,
        },
      );
    } catch (_) {}
  }

  /// 上报播放进度
  Future<void> reportPlaybackProgress({
    required String userId,
    required String token,
    required String baseUrl,
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required Duration position,
    bool isPaused = false,
  }) async {
    try {
      await _post(
        '$baseUrl/Sessions/Playing/Progress',
        token,
        query: {'userId': userId},
        data: {
          'ItemId': itemId,
          'MediaSourceId': mediaSourceId,
          'PlaySessionId': playSessionId,
          'PlaylistItemId': 'playlistItem0',
          'PositionTicks': position.inMicroseconds * 10,
          'IsPaused': isPaused,
          'CanSeek': true,
          'IsMuted': false,
          'PlaybackRate': 1,
          'VolumeLevel': 100,
          'RepeatMode': 'RepeatNone',
          'ShuffleMode': 'Sorted',
          'MaxStreamingBitrate': 140000000,
          'PlayMethod': 'DirectPlay',
          'EventName': 'timeupdate',
        },
      );
    } catch (_) {}
  }

  /// 上报播放停止
  Future<void> reportPlaybackStopped({
    required String userId,
    required String token,
    required String baseUrl,
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required Duration position,
  }) async {
    try {
      await _post(
        '$baseUrl/Sessions/Playing/Stopped',
        token,
        query: {'userId': userId},
        data: {
          'ItemId': itemId,
          'MediaSourceId': mediaSourceId,
          'PlaySessionId': playSessionId,
          'PlaylistItemId': 'playlistItem0',
          'PositionTicks': position.inMicroseconds * 10,
          'IsPaused': true,
          'CanSeek': true,
          'IsMuted': false,
          'PlaybackRate': 1,
          'VolumeLevel': 100,
          'RepeatMode': 'RepeatNone',
          'ShuffleMode': 'Sorted',
          'MaxStreamingBitrate': 140000000,
          'PlayMethod': 'DirectPlay',
          'NowPlayingQueue': [
            {'Id': itemId, 'PlaylistItemId': 'playlistItem0'},
          ],
        },
      );
    } catch (_) {}
  }

  /// 显式标记为已播放
  Future<void> markPlayed({
    required String userId,
    required String token,
    required String baseUrl,
    required String itemId,
  }) async {
    try {
      await _post('$baseUrl/Users/$userId/PlayedItems/$itemId', token);
    } catch (_) {}
  }
}