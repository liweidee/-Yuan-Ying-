/// 播放地址响应模型
class PlayUrl {
  final int parse; // 0=直链, 1=嗅探
  final int? jx; // 1=需要解析播放
  final List<PlayQuality> qualities;
  final Map<String, String>? headers;
  final String? danmaku;
  final String? script;
  final String? lrc;
  final String? audioUrl;
  final int? isDash;   // 1=DASH流 0=非DASH null=未指定

  PlayUrl({
    required this.parse,
    this.jx,
    required this.qualities,
    this.headers,
    this.danmaku,
    this.script,
    this.lrc,
    this.audioUrl,
    this.isDash,
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

    final qualities = _parseQualities(json['url'] ?? json['urls']);

    return PlayUrl(
      parse: json['parse'] ?? 0,
      jx: json['jx']?.toInt(),
      qualities: qualities,
      headers: headers,
      danmaku: json['danmaku']?.toString(),
      script: json['script']?.toString(),
      lrc: json['lrc']?.toString(),
      audioUrl: (json['audioUrl'] ?? json['audio_url'])?.toString(),
      isDash: _parseIsDash(json),
    );
  }

  /// 兼容 int(1/0) / bool(true/false) / String("1"/"0"/"true"/"false")
  /// 兼容 key: isDash / is_dash / dash
  static int? _parseIsDash(Map<String, dynamic> json) {
    final raw = json['isDash'] ?? json['is_dash'] ?? json['dash'];
    if (raw == null) return null;
    if (raw is int) return raw == 1 ? 1 : (raw == 0 ? 0 : null);
    if (raw is bool) return raw ? 1 : 0;
    final s = raw.toString().trim().toLowerCase();
    if (s == '1' || s == 'true') return 1;
    if (s == '0' || s == 'false') return 0;
    return null;
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