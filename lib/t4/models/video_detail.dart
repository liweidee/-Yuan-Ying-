import 'video_item.dart';

/// 剧集项
class Episode {
  final String name;      // 如 "第1集"
  final String url;       // 播放参数，如 "vod_d_id=140998&vurl_id=3951566..."
  final String? flag;     // 线路名称（可选）

  Episode({
    required this.name,
    required this.url,
    this.flag,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      flag: json['flag']?.toString(),
    );
  }

  /// 从 "第1集$http://example.com/play.m3u8" 格式解析
  factory Episode.fromPlayUrlString(String str) {
    final parts = str.split('\$');
    if (parts.length == 2) {
      return Episode(name: parts[0], url: parts[1]);
    }
    return Episode(name: str, url: str);
  }
}

/// 播放线路
class PlaySource {
  final String name;              // 线路名称，如 "嗑瓜子1"
  final List<Episode> episodes;   // 该线路的剧集列表

  PlaySource({
    required this.name,
    required this.episodes,
  });
}

/// 视频详情模型
class VideoDetail extends VideoItem {
  final String? vodContent;
  final String? vodDirector;
  final String? vodYear;
  final String? vodArea;
  final String? vodLang;
  final String? vodPlayUrl;
  final List<PlaySource> playSources;  // 多线路

  VideoDetail({
    required super.vodId,
    required super.vodName,
    required super.vodPic,
    super.vodRemarks,
    super.vodActor,
    super.typeName,
    this.vodContent,
    this.vodDirector,
    this.vodYear,
    this.vodArea,
    this.vodLang,
    this.vodPlayUrl,
    this.playSources = const [],
  });

  /// 从 JSON 创建 VideoDetail
  factory VideoDetail.fromJson(Map<String, dynamic> json) {
    final playSources = _parsePlaySources(json);
    
    return VideoDetail(
      vodId: json['vod_id']?.toString() ?? '',
      vodName: json['vod_name']?.toString() ?? '',
      vodPic: json['vod_pic']?.toString() ?? '',
      vodRemarks: json['vod_remarks']?.toString(),
      vodActor: json['vod_actor']?.toString(),
      typeName: json['type_name']?.toString(),
      vodContent: json['vod_content']?.toString(),
      vodDirector: json['vod_director']?.toString(),
      vodYear: json['vod_year']?.toString(),
      vodArea: json['vod_area']?.toString(),
      vodLang: json['vod_lang']?.toString(),
      vodPlayUrl: json['vod_play_url']?.toString(),
      playSources: playSources,
    );
  }

  /// 解析多线路
  static List<PlaySource> _parsePlaySources(Map<String, dynamic> json) {
    final from = json['vod_play_from']?.toString() ?? '';
    final url = json['vod_play_url']?.toString() ?? '';
    
    if (from.isEmpty || url.isEmpty) return [];

    final fromList = from.split('\$\$\$');
    final urlList = url.split('\$\$\$');
    
    final sources = <PlaySource>[];
    for (int i = 0; i < fromList.length && i < urlList.length; i++) {
      final episodes = _parseEpisodes(urlList[i]);
      if (episodes.isNotEmpty) {
        sources.add(PlaySource(
          name: fromList[i],
          episodes: episodes,
        ));
      }
    }
    return sources;
  }

  /// 解析单个线路的剧集列表
  static List<Episode> _parseEpisodes(String urlStr) {
    final episodes = <Episode>[];
    for (final part in urlStr.split('#')) {
      if (part.trim().isEmpty) continue;
      final parts = part.split('\$');
      if (parts.length == 2) {
        episodes.add(Episode(
          name: parts[0],
          url: parts[1],
        ));
      }
    }
    return episodes;
  }
}