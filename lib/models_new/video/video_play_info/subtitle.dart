// lib/models_new/video/video_play_info/subtitle.dart

class Subtitle {
  late String lan;
  String? lanDoc;
  String? subtitleUrl;
  String? subtitleUrlV2;
  bool isAi = false;

  Subtitle({
    required this.lan,
    this.lanDoc,
  });

  Subtitle.fromJson(Map<String, dynamic> json) {
    lan = json["lan"];
    isAi = json["type"] == 1;
    lanDoc = '${json["lan_doc"]}${isAi ? '（AI）' : ''}';
    subtitleUrl = json["subtitle_url"];
    subtitleUrlV2 = json["subtitle_url_v2"];
  }

  Map<String, dynamic> toJson() {
    return {
      'lan': lan,
      'lan_doc': lanDoc,
      'subtitle_url': subtitleUrl,
      'subtitle_url_v2': subtitleUrlV2,
      'type': isAi ? 1 : 0,
    };
  }
}