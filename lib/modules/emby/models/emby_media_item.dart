class EmbyMediaItem {
  final String id;
  final String name;
  final String type; // Movie, Series, Episode, Season, MusicAlbum, MusicArtist, Audio, CollectionFolder
  final String? mediaType;       // Video / Audio / Photo / Book
  final String? collectionType;  // movies / tvshows / music / books / photos
  final String? container;       // mp4 / mkv / mp3 / flac / m4a
  final String? overview;
  final int? productionYear;
  final double? communityRating;
  final int? runtimeTicks;
  final List<String> genres;
  final List<EmbyPerson> people;
  final EmbyUserData? userData;
  final String? seriesName;
  final String? seasonId;
    final String? seriesId;   // Episode 所属的 Series ID
  final int? indexNumber;
  final int? parentIndexNumber;
  final String? albumName;       // 所属专辑
  final String? albumArtist;     // 专辑艺术家
  final List<String> artists;    // 艺术家列表
  final String? albumId;         // 专辑 ID（曲目用）
  final Map<String, String> imageTags;
  final String? primaryImageItemId;
  final String? primaryImageTag;
  final List<String> backdropImageTags;

  EmbyMediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.mediaType,
    this.collectionType,
    this.container,
    this.overview,
    this.productionYear,
    this.communityRating,
    this.runtimeTicks,
    this.genres = const [],
    this.people = const [],
    this.userData,
    this.seriesName,
    this.seasonId,
    this.seriesId,
    this.indexNumber,
    this.parentIndexNumber,
    this.albumName,
    this.albumArtist,
    this.artists = const [],
    this.albumId,
    this.imageTags = const {},
    this.primaryImageItemId,
    this.primaryImageTag,
    this.backdropImageTags = const [],
  });

  factory EmbyMediaItem.fromJson(Map<String, dynamic> json) => EmbyMediaItem(
    id: json['Id'] as String,
    name: json['Name'] as String? ?? '',
    type: json['Type'] as String? ?? 'Unknown',
    mediaType: json['MediaType'] as String?,
    collectionType: json['CollectionType'] as String?,
    container: json['Container'] as String?,
    overview: json['Overview'] as String?,
    productionYear: json['ProductionYear'] as int?,
    communityRating: (json['CommunityRating'] as num?)?.toDouble(),
    runtimeTicks: json['RunTimeTicks'] as int?,
    genres: (json['Genres'] as List?)?.map((e) => e as String).toList() ?? [],
    people: (json['People'] as List?)
            ?.map((e) => EmbyPerson.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    userData: json['UserData'] != null
        ? EmbyUserData.fromJson(json['UserData'] as Map<String, dynamic>)
        : null,
    seriesName: json['SeriesName'] as String?,
    seasonId: json['SeasonId'] as String?,
    seriesId: json['SeriesId'] as String?,
    indexNumber: json['IndexNumber'] as int?,
    parentIndexNumber: json['ParentIndexNumber'] as int?,
    albumName: json['Album'] as String?,
    albumArtist: json['AlbumArtist'] as String?,
    artists: (json['Artists'] as List?)?.map((e) => e as String).toList() ??
        const [],
    albumId: json['AlbumId'] as String?,
    imageTags: (json['ImageTags'] as Map?)?.map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    ) ?? const {},
    primaryImageItemId: json['PrimaryImageItemId'] as String?,
    primaryImageTag: json['PrimaryImageTag'] as String?,
    backdropImageTags: (json['BackdropImageTags'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
  );

  // ============ 视频类 getter ============
  bool get isMovie => type == 'Movie';
  bool get isSeries => type == 'Series';
  bool get isEpisode => type == 'Episode';
  bool get isSeason => type == 'Season';

  // ============ 音乐类 getter ============
  /// 是否为音乐曲目（歌）
  bool get isAudio => type == 'Audio' || mediaType == 'Audio';

  /// 是否为音乐专辑
  bool get isMusicAlbum => type == 'MusicAlbum';

  /// 是否为音乐艺术家
  bool get isMusicArtist => type == 'MusicArtist';

  /// 是否为图片
  bool get isPhoto => mediaType == 'Photo' || type == 'Photo';

  /// 该库是否为音乐库（仅 CollectionFolder 有 collectionType）
  bool get isMusicLibrary =>
      type == 'CollectionFolder' && collectionType == 'music';

  /// 自己是否有 Primary 图
  bool get hasPrimaryImage =>
      imageTags['Primary'] != null && imageTags['Primary']!.isNotEmpty;

  /// 真正用于请求 Primary 图的 item id
  ///
  /// 规则：
  /// - 自己就有 Primary 图 → 用自己
  /// - 否则用 Emby 指派的 PrimaryImageItemId（音乐专辑常见）
  /// - 都没有 → 退回自己（会 404，但有占位兜底）
  String get effectivePrimaryImageId {
    if (hasPrimaryImage) return id;
    if (primaryImageItemId != null && primaryImageItemId!.isNotEmpty) {
      return primaryImageItemId!;
    }
    return id;
  }

  /// 真正用于请求 Primary 图的 tag
  String? get effectivePrimaryImageTag {
    if (hasPrimaryImage) return imageTags['Primary'];
    if (primaryImageTag != null && primaryImageTag!.isNotEmpty) {
      return primaryImageTag;
    }
    return null;
  }

  /// 是否有 Backdrop 图
  bool get hasBackdrop => backdropImageTags.isNotEmpty;

  /// 音频/视频 统一判断（用于播放分流）
  bool get isAudioPlayable => isAudio;

  /// 用于主项目的 VideoItem 转换
  Map<String, dynamic> toVideoItemMap() => {
        'vod_id': id,
        'vod_name': name,
        'vod_pic': '',
        'vod_remarks': isEpisode
            ? 'S${parentIndexNumber ?? 0}E${indexNumber ?? 0}'
            : (isAudio ? (albumName ?? '') : ''),
        'type_name': type,
        'vod_year': productionYear?.toString() ?? '',
        'vod_rating': communityRating?.toString() ?? '',
        'vod_actor':
            people.where((p) => p.type == 'Actor').map((p) => p.name).join(','),
      };
}

class EmbyUserData {
  final double? playedPercentage;
  final int? playbackPositionTicks;
  final bool played;
  final bool isFavorite;
  final int playCount;

  EmbyUserData({
    this.playedPercentage,
    this.playbackPositionTicks,
    this.played = false,
    this.isFavorite = false,
    this.playCount = 0,
  });

  factory EmbyUserData.fromJson(Map<String, dynamic> json) =>
      EmbyUserData(
        playedPercentage: (json['PlayedPercentage'] as num?)?.toDouble(),
        playbackPositionTicks: json['PlaybackPositionTicks'] as int?,
        played: json['Played'] as bool? ?? false,
        isFavorite: json['IsFavorite'] as bool? ?? false,
        playCount: json['PlayCount'] as int? ?? 0,
      );
}

class EmbyPerson {
  final String id;
  final String name;
  final String type;
  final String? role;

  /// Emby 返回的演员头像标识
  /// 有值 = 有头像；空/null = 无头像
  final String? primaryImageTag;

  EmbyPerson({
    required this.id,
    required this.name,
    required this.type,
    this.role,
    this.primaryImageTag,
  });

  /// 是否有可用的头像（用于跳过无意义的请求）
  bool get hasImage =>
      primaryImageTag != null && primaryImageTag!.isNotEmpty;

  factory EmbyPerson.fromJson(Map<String, dynamic> json) => EmbyPerson(
        id: json['Id'] as String,
        name: json['Name'] as String,
        type: json['Type'] as String,
        role: json['Role'] as String?,
        primaryImageTag: json['PrimaryImageTag'] as String?,
      );
}