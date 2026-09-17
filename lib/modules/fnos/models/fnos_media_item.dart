/// 飞牛媒体库
class FnosMediaDbItem {
  final String guid;
  final String title;
  final String? poster;
  final List<String>? posters;
  final String? category;
  final int viewType;
  final int posterType;

  FnosMediaDbItem({
    required this.guid,
    required this.title,
    this.poster,
    this.posters,
    this.category,
    this.viewType = 0,
    this.posterType = 0,
  });

  String? get firstPoster {
    if (poster != null && poster!.isNotEmpty) return poster;
    if (posters != null && posters!.isNotEmpty) return posters!.first;
    return null;
  }

  factory FnosMediaDbItem.fromJson(Map<String, dynamic> json) {
    return FnosMediaDbItem(
      guid: json['guid']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      poster: json['poster']?.toString(),
      posters: json['posters'] != null
          ? List<String>.from(json['posters'] as List)
          : null,
      category: json['category']?.toString(),
      viewType: (json['view_type'] as num?)?.toInt() ?? 0,
      posterType: (json['poster_type'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 飞牛条目（电影 / 剧集 / 文件夹 / 视频 / 集）
class FnosPlayListItem {
  final String guid;
  final String? title;
  final String? type;
  final String? poster;
  final String? tvTitle;
  final String? parentTitle;
  final String? parentGuid;
  final String? ancestorName;
  final String? ancestorCategory;
  final int watched;
  final int ts;
  final int duration;
  final int episodeNumber;
  final int seasonNumber;
  final String? voteAverage;
  final String? overview;
  final int runtime;
  final int isFavorite;
  final String? videoGuid;
  final String? audioGuid;
  final String? subtitleGuid;
  final String? mediaGuid;
  final String? airDate;
  final int numberOfSeasons;
  final int numberOfEpisodes;

  FnosPlayListItem({
    required this.guid,
    this.title,
    this.type,
    this.poster,
    this.tvTitle,
    this.parentTitle,
    this.parentGuid,
    this.ancestorName,
    this.ancestorCategory,
    this.watched = 0,
    this.ts = 0,
    this.duration = 0,
    this.episodeNumber = 0,
    this.seasonNumber = 0,
    this.voteAverage,
    this.overview,
    this.runtime = 0,
    this.isFavorite = 0,
    this.videoGuid,
    this.audioGuid,
    this.subtitleGuid,
    this.mediaGuid,
    this.airDate,
    this.numberOfSeasons = 0,
    this.numberOfEpisodes = 0,
  });

  bool get isFolder => type == 'Directory';
  bool get isTv => type == 'TV';
  bool get isEpisode => type == 'Episode';
  bool get isMovie => type == 'Movie';
  bool get isVideo => type == 'Video';
  bool get isPlayable => isEpisode || isMovie || isVideo;

  String get categoryLabel {
    switch (type) {
      case 'TV':
        return '剧集';
      case 'Movie':
        return '电影';
      case 'Episode':
        return '剧集';
      case 'Directory':
        return '文件夹';
      case 'Video':
        return '视频';
      default:
        return type ?? '';
    }
  }

  factory FnosPlayListItem.fromJson(Map<String, dynamic> json) {
    return FnosPlayListItem(
      guid: json['guid']?.toString() ?? '',
      title: json['title']?.toString(),
      type: json['type']?.toString(),
      poster: json['poster']?.toString(),
      tvTitle: json['tv_title']?.toString(),
      parentTitle: json['parent_title']?.toString(),
      parentGuid: json['parent_guid']?.toString(),
      ancestorName: json['ancestor_name']?.toString(),
      ancestorCategory: json['ancestor_category']?.toString(),
      watched: (json['watched'] as num?)?.toInt() ?? 0,
      ts: ((json['ts'] ?? json['watched_ts']) as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      episodeNumber: (json['episode_number'] as num?)?.toInt() ?? 0,
      seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
      voteAverage: json['vote_average']?.toString(),
      overview: json['overview']?.toString(),
      runtime: (json['runtime'] as num?)?.toInt() ?? 0,
      isFavorite: (json['is_favorite'] as num?)?.toInt() ?? 0,
      videoGuid: json['video_guid']?.toString(),
      audioGuid: json['audio_guid']?.toString(),
      subtitleGuid: json['subtitle_guid']?.toString(),
      mediaGuid: json['media_guid']?.toString(),
      airDate: json['air_date']?.toString(),
      numberOfSeasons: (json['number_of_seasons'] as num?)?.toInt() ?? 0,
      numberOfEpisodes: (json['number_of_episodes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// play/info 返回的 item 详情
class FnosItemInfo {
  final String? guid;
  final String? title;
  final String? tvTitle;
  final String? parentTitle;
  final String? overview;
  final String? poster;
  final String? backdrops;
  final String? logo;
  final String? voteAverage;
  final int runtime;
  final int duration;
  final int episodeNumber;
  final int seasonNumber;
  final int numberOfEpisodes;
  final int numberOfSeasons;
  final String? airDate;
  final String? releaseDate;
  final String? status;
  final int watched;
  final int isFavorite;

  FnosItemInfo({
    this.guid,
    this.title,
    this.tvTitle,
    this.parentTitle,
    this.overview,
    this.poster,
    this.backdrops,
    this.logo,
    this.voteAverage,
    this.runtime = 0,
    this.duration = 0,
    this.episodeNumber = 0,
    this.seasonNumber = 0,
    this.numberOfEpisodes = 0,
    this.numberOfSeasons = 0,
    this.airDate,
    this.releaseDate,
    this.status,
    this.watched = 0,
    this.isFavorite = 0,
  });

  factory FnosItemInfo.fromJson(Map<String, dynamic> json) {
    return FnosItemInfo(
      guid: json['guid']?.toString(),
      title: json['title']?.toString(),
      tvTitle: json['tv_title']?.toString(),
      parentTitle: json['parent_title']?.toString(),
      overview: json['overview']?.toString(),
      poster: json['poster']?.toString(),
      backdrops: json['backdrops']?.toString(),
      logo: (json['logo'] ?? json['logos'])?.toString(),
      voteAverage: json['vote_average']?.toString(),
      runtime: (json['runtime'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      episodeNumber: (json['episode_number'] as num?)?.toInt() ?? 0,
      seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
      numberOfEpisodes: (json['number_of_episodes'] as num?)?.toInt() ?? 0,
      numberOfSeasons: (json['number_of_seasons'] as num?)?.toInt() ?? 0,
      airDate: json['air_date']?.toString(),
      releaseDate: json['release_date']?.toString(),
      status: json['status']?.toString(),
      watched: (json['watched'] as num?)?.toInt() ?? 0,
      isFavorite: (json['is_favorite'] as num?)?.toInt() ?? 0,
    );
  }
}

/// play/info 响应
class FnosPlayInfoResponse {
  final String? guid;
  final String? type;
  final String? parentGuid;
  final String? mediaGuid;
  final String? videoGuid;
  final String? audioGuid;
  final String? subtitleGuid;
  final int ts;
  final FnosItemInfo? item;
  final List<FnosLiveChannelSource> liveChannels;

  FnosPlayInfoResponse({
    this.guid,
    this.type,
    this.parentGuid,
    this.mediaGuid,
    this.videoGuid,
    this.audioGuid,
    this.subtitleGuid,
    this.ts = 0,
    this.item,
    this.liveChannels = const [],
  });

  factory FnosPlayInfoResponse.fromJson(Map<String, dynamic> json) {
    return FnosPlayInfoResponse(
      guid: json['guid']?.toString(),
      type: json['type']?.toString(),
      parentGuid: json['parent_guid']?.toString(),
      mediaGuid: json['media_guid']?.toString(),
      videoGuid: json['video_guid']?.toString(),
      audioGuid: json['audio_guid']?.toString(),
      subtitleGuid: json['subtitle_guid']?.toString(),
      ts: (json['ts'] as num?)?.toInt() ?? 0,
      item: json['item'] != null
          ? FnosItemInfo.fromJson(Map<String, dynamic>.from(json['item'] as Map))
          : null,
      liveChannels: (json['live_channels'] as List? ?? [])
          .map((e) => FnosLiveChannelSource.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

// ============================================================
// Stream 接口相关模型（用于 play/info → stream → play/play 流程）
// ============================================================

/// POST /v/api/v1/stream 的响应
class FnosStreamResponse {
  final FnosVideoStream? videoStream;
  final List<FnosAudioStream> audioStreams;
  final List<FnosSubtitleStream> subtitleStreams;
  final List<FnosDirectLinkQuality> directLinkQualities;
  final Map<String, dynamic>? header;

  FnosStreamResponse({
    this.videoStream,
    this.audioStreams = const [],
    this.subtitleStreams = const [],
    this.directLinkQualities = const [],
    this.header,
  });

  factory FnosStreamResponse.fromJson(Map<String, dynamic> json) {
    return FnosStreamResponse(
      videoStream: json['video_stream'] != null
          ? FnosVideoStream.fromJson(
              Map<String, dynamic>.from(json['video_stream'] as Map))
          : null,
      audioStreams: (json['audio_streams'] as List? ?? [])
          .map((e) =>
              FnosAudioStream.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      subtitleStreams: (json['subtitle_streams'] as List? ?? [])
          .map((e) =>
              FnosSubtitleStream.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      directLinkQualities: (json['direct_link_qualities'] as List? ?? [])
          .map((e) => FnosDirectLinkQuality.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      header: json['header'] != null
          ? Map<String, dynamic>.from(json['header'] as Map)
          : null,
    );
  }
}

class FnosVideoStream {
  final int width;
  final int height;
  final int bps;
  final int duration;
  final String? codecName;
  final String? resolutionType;

  FnosVideoStream({
    this.width = 0,
    this.height = 0,
    this.bps = 0,
    this.duration = 0,
    this.codecName,
    this.resolutionType,
  });

  factory FnosVideoStream.fromJson(Map<String, dynamic> json) =>
      FnosVideoStream(
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        bps: (json['bps'] as num?)?.toInt() ?? 0,
        duration: (json['duration'] as num?)?.toInt() ?? 0,
        codecName: json['codec_name']?.toString(),
        resolutionType: json['resolution_type']?.toString(),
      );
}

class FnosAudioStream {
  final String? guid;
  final String? title;
  final String? language;
  final String? codecName;
  final int channels;
  final int isDefault;

  FnosAudioStream({
    this.guid,
    this.title,
    this.language,
    this.codecName,
    this.channels = 0,
    this.isDefault = 0,
  });

  factory FnosAudioStream.fromJson(Map<String, dynamic> json) =>
      FnosAudioStream(
        guid: json['guid']?.toString(),
        title: json['title']?.toString(),
        language: json['language']?.toString(),
        codecName: json['codec_name']?.toString(),
        channels: (json['channels'] as num?)?.toInt() ?? 0,
        isDefault: (json['is_default'] as num?)?.toInt() ?? 0,
      );
}

class FnosSubtitleStream {
  final String? guid;
  final String? title;
  final String? language;
  final String? codecName;
  final int isDefault;
  final int isExternal;

  FnosSubtitleStream({
    this.guid,
    this.title,
    this.language,
    this.codecName,
    this.isDefault = 0,
    this.isExternal = 0,
  });

  factory FnosSubtitleStream.fromJson(Map<String, dynamic> json) =>
      FnosSubtitleStream(
        guid: json['guid']?.toString(),
        title: json['title']?.toString(),
        language: json['language']?.toString(),
        codecName: json['codec_name']?.toString(),
        isDefault: (json['is_default'] as num?)?.toInt() ?? 0,
        isExternal: (json['is_external'] as num?)?.toInt() ?? 0,
      );
}

class FnosDirectLinkQuality {
  final int bitrate;
  final String resolution;
  final String url;
  final bool progressive;

  FnosDirectLinkQuality({
    this.bitrate = 0,
    this.resolution = '',
    this.url = '',
    this.progressive = false,
  });

  factory FnosDirectLinkQuality.fromJson(Map<String, dynamic> json) =>
      FnosDirectLinkQuality(
        bitrate: (json['bitrate'] as num?)?.toInt() ?? 0,
        resolution: json['resolution']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        progressive: json['progressive'] as bool? ?? false,
      );
}

// ============================================================
// 直播频道模型
// ============================================================

class FnosLiveChannelSource {
  final String guid;
  final String path;
  final String fileName;
  final int sortNum;
  final int canPlay;
  final String? playError;

  FnosLiveChannelSource({
    required this.guid,
    required this.path,
    required this.fileName,
    this.sortNum = 0,
    this.canPlay = 1,
    this.playError,
  });

  factory FnosLiveChannelSource.fromJson(Map<String, dynamic> json) =>
      FnosLiveChannelSource(
        guid: json['guid']?.toString() ?? '',
        path: json['path']?.toString() ?? '',
        fileName: json['file_name']?.toString() ?? '',
        sortNum: (json['sort_num'] as num?)?.toInt() ?? 0,
        canPlay: (json['can_play'] as num?)?.toInt() ?? 1,
        playError: json['play_error']?.toString(),
      );
}