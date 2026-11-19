import 'package:yuanying/modules/action/models/action_config.dart';
import 'package:yuanying/modules/action/utils/action_parser.dart';

class VideoItem {
  final String vodId;
  final String vodName;
  final String vodPic;
  final String? vodRemarks;
  final String? vodActor;
  final String? typeName;
  final String? vodTag;
  final String? vodSource;
  final String? episodeUrl;
  final String? episodeName;
  final int? episodeIndex;
  final String? episodeSourceName;

  bool get isAction => vodTag == 'action';

  /// 解析 Action 配置
  ActionConfig? get actionConfig {
    if (!isAction) return null;
    return ActionParser.parse(vodId);
  }

  VideoItem({
    required this.vodId,
    required this.vodName,
    required this.vodPic,
    this.vodRemarks,
    this.vodActor,
    this.typeName,
    this.vodTag,
    this.vodSource,
    this.episodeUrl,
    this.episodeName,
    this.episodeIndex,
    this.episodeSourceName,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      vodId: json['vod_id']?.toString() ?? '',
      vodName: json['vod_name']?.toString() ?? '',
      vodPic: json['vod_pic']?.toString() ?? '',
      vodRemarks: json['vod_remarks']?.toString(),
      vodActor: json['vod_actor']?.toString(),
      typeName: json['type_name']?.toString(),
      vodTag: json['vod_tag']?.toString(),
      vodSource: json['vod_source']?.toString(),
      episodeUrl: json['episode_url']?.toString(),
      episodeName: json['episode_name']?.toString(),
      episodeIndex: json['episode_index'] is num
          ? (json['episode_index'] as num).toInt()
          : int.tryParse(json['episode_index']?.toString() ?? ''),
      episodeSourceName: json['episode_source_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vod_id': vodId,
      'vod_name': vodName,
      'vod_pic': vodPic,
      if (vodRemarks != null) 'vod_remarks': vodRemarks,
      if (vodActor != null) 'vod_actor': vodActor,
      if (typeName != null) 'type_name': typeName,
      if (vodTag != null) 'vod_tag': vodTag,
      if (vodSource != null) 'vod_source': vodSource,
      if (episodeUrl != null) 'episode_url': episodeUrl,
      if (episodeName != null) 'episode_name': episodeName,
      if (episodeIndex != null) 'episode_index': episodeIndex,
      if (episodeSourceName != null)
        'episode_source_name': episodeSourceName,
    };
  }
}
