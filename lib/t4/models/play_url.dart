/// 播放地址响应模型
class PlayUrl {
  final int parse; // 0=直链, 1=嗅探
  final int? jx; // 1=需要解析播放
  final List<PlayQuality> qualities;
  final Map<String, String>? headers;
  final String? danmaku;
  final String? script;

  PlayUrl({
    required this.parse,
    this.jx,
    required this.qualities,
    this.headers,
    this.danmaku,
    this.script,
  });

  // 是否直链
  bool get isDirect => parse == 0;
  // 是否需要嗅探
  bool get needSniff => parse == 1;
  // 是否需要解析
  bool get needParser => jx == 1;

  factory PlayUrl.fromJson(Map<String, dynamic> json) {
    Map<String, String>? headers;
    final headerData = json['header'] ?? json['headers'];
    if (headerData != null && headerData is Map) {
      headers = {};
      (headerData as Map).forEach((key, value) {
        headers![key.toString()] = value.toString();
      });
    }

    final qualities = _parseQualities(json['url']);

    return PlayUrl(
      parse: json['parse'] ?? 0,
      jx: json['jx']?.toInt(),
      qualities: qualities,
      headers: headers,
      danmaku: json['danmaku']?.toString(),
      script: json['script']?.toString(),
    );
  }

  static List<PlayQuality> _parseQualities(dynamic urlData) {
    if (urlData == null) return [];

    if (urlData is String) {
      return [PlayQuality(label: '默认', url: urlData)];
    }

    if (urlData is List && urlData.isNotEmpty) {
      final list = <PlayQuality>[];
      for (int i = 0; i < urlData.length; i += 2) {
        if (i + 1 < urlData.length) {
          final label = urlData[i].toString();
          final url = urlData[i + 1].toString();
          if (url.isNotEmpty) {
            list.add(PlayQuality(label: label, url: url));
          }
        }
      }
      return list;
    }
    return [];
  }

  String? get defaultUrl => qualities.isNotEmpty ? qualities.first.url : null;
}

class PlayQuality {
  final String label;
  final String url;

  PlayQuality({required this.label, required this.url});
}