// lib/models/live/live_config.dart
class LiveConfig {
  final String key;
  final String name;
  final String url;
  final String? ua;
  final String? epg;
  final String? logo;

  LiveConfig({
    required this.key,
    required this.name,
    required this.url,
    this.ua,
    this.epg,
    this.logo,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'url': url,
        'ua': ua,
        'epg': epg,
        'logo': logo,
      };

  factory LiveConfig.fromJson(Map<String, dynamic> json) => LiveConfig(
        key: json['key'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        ua: json['ua'] as String?,
        epg: json['epg'] as String?,
        logo: json['logo'] as String?,
      );
}