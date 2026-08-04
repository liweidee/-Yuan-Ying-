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
    };
  }
}