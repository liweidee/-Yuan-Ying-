// lib/modules/live/models/live_channel.dart
class LiveChannel {
  final String name;
  final String url;
  final String group;
  final String? logo;
  final String? tvgId;
  final String? tvgName;

  LiveChannel({
    required this.name,
    required this.url,
    this.group = '未分组',
    this.logo,
    this.tvgId,
    this.tvgName,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'group': group,
        'logo': logo,
        'tvgId': tvgId,
        'tvgName': tvgName,
      };

  factory LiveChannel.fromJson(Map<String, dynamic> json) => LiveChannel(
        name: json['name'] as String,
        url: json['url'] as String,
        group: json['group'] as String? ?? '未分组',
        logo: json['logo'] as String?,
        tvgId: json['tvgId'] as String?,
        tvgName: json['tvgName'] as String?,
      );
}