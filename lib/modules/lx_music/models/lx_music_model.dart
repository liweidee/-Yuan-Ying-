/// 洛雪音乐歌曲模型
///
/// 从波点音乐 MusicInfo 移植，去掉 Hive 注解（不落 Hive，仅内存传递 + JSON）。
class LxMusic {
  final String id;
  final String name;
  final String singer;
  final String album;
  final int duration; // 毫秒
  final String? source; // kw / kg / tx / wy
  final String? sourceId;
  final String? imgUrl;
  final String? songUrl;
  final String? lyric;
  final String? tlyric;
  final String? rlyric;
  final DateTime? addTime;
  final String? songId;
  final String? songmid;
  final String? strMediaMid;
  final String? copyrightId;
  final String? hash;
  final List<LxQualityType>? types;

  LxMusic({
    required this.id,
    required this.name,
    required this.singer,
    required this.album,
    required this.duration,
    this.source,
    this.sourceId,
    this.imgUrl,
    this.songUrl,
    this.lyric,
    this.tlyric,
    this.rlyric,
    this.addTime,
    this.songId,
    this.songmid,
    this.strMediaMid,
    this.copyrightId,
    this.hash,
    this.types,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'singer': singer,
      'album': album,
      'duration': duration,
      'source': source,
      'sourceId': sourceId,
      'imgUrl': imgUrl,
      'songUrl': songUrl,
      'lyric': lyric,
      'tlyric': tlyric,
      'rlyric': rlyric,
      'addTime': addTime?.toIso8601String(),
      'songId': songId,
      'songmid': songmid,
      'strMediaMid': strMediaMid,
      'copyrightId': copyrightId,
      'hash': hash,
      'types': types?.map((t) => t.toJson()).toList(),
    };
  }

  factory LxMusic.fromJson(Map<String, dynamic> json) {
    final rawDuration = json['duration'];
    final duration = rawDuration is int
        ? rawDuration
        : (rawDuration is num ? rawDuration.toInt() : 0);

    final rawAddTime = json['addTime'];
    final addTime = rawAddTime is String && rawAddTime.isNotEmpty
        ? DateTime.tryParse(rawAddTime)
        : null;

    final rawTypes = json['types'];

    return LxMusic(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      singer: json['singer']?.toString() ?? '',
      album: json['album']?.toString() ?? '',
      duration: duration,
      source: json['source']?.toString(),
      sourceId: json['sourceId']?.toString(),
      imgUrl: json['imgUrl']?.toString(),
      songUrl: json['songUrl']?.toString(),
      lyric: json['lyric']?.toString(),
      tlyric: json['tlyric']?.toString(),
      rlyric: json['rlyric']?.toString(),
      addTime: addTime,
      songId: json['songId']?.toString(),
      songmid: json['songmid']?.toString(),
      strMediaMid: json['strMediaMid']?.toString(),
      copyrightId: json['copyrightId']?.toString(),
      hash: json['hash']?.toString(),
      types: rawTypes is List
          ? rawTypes
              .map((t) => LxQualityType.fromJson(
                  t is Map ? Map<String, dynamic>.from(t) : <String, dynamic>{}))
              .toList()
          : null,
    );
  }

  LxMusic copyWith({
    String? id,
    String? name,
    String? singer,
    String? album,
    int? duration,
    String? source,
    String? sourceId,
    String? imgUrl,
    String? songUrl,
    String? lyric,
    String? tlyric,
    String? rlyric,
    DateTime? addTime,
    String? songId,
    String? songmid,
    String? strMediaMid,
    String? copyrightId,
    String? hash,
    List<LxQualityType>? types,
  }) {
    return LxMusic(
      id: id ?? this.id,
      name: name ?? this.name,
      singer: singer ?? this.singer,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      imgUrl: imgUrl ?? this.imgUrl,
      songUrl: songUrl ?? this.songUrl,
      lyric: lyric ?? this.lyric,
      tlyric: tlyric ?? this.tlyric,
      rlyric: rlyric ?? this.rlyric,
      addTime: addTime ?? this.addTime,
      songId: songId ?? this.songId,
      songmid: songmid ?? this.songmid,
      strMediaMid: strMediaMid ?? this.strMediaMid,
      copyrightId: copyrightId ?? this.copyrightId,
      hash: hash ?? this.hash,
      types: types ?? this.types,
    );
  }
}

/// 音质类型
class LxQualityType {
  final String type;
  final String size;
  final String? hash;

  LxQualityType({
    required this.type,
    required this.size,
    this.hash,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'size': size,
      'hash': hash,
    };
  }

  factory LxQualityType.fromJson(Map<String, dynamic> json) {
    return LxQualityType(
      type: json['type']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      hash: json['hash']?.toString(),
    );
  }
}