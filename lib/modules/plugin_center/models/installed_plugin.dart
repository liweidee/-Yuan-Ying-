// lib/modules/plugin_center/models/installed_plugin.dart

/// 本地已安装的插件登记
class InstalledPlugin {
  final String id;
  final String version;
  final String source;
  final String installPath;
  final bool enabled;
  final bool pinned;

  /// 置顶时间（毫秒时间戳）；未置顶时为 null
  final int? pinnedAtMs;

  final int installedAtMs;
  final String type;
  final String? desc;
  final String? changelog;
  final String? icon;
  final Map<String, dynamic> extras;

  InstalledPlugin({
    required this.id,
    required this.version,
    required this.source,
    required this.installPath,
    this.enabled = true,
    this.pinned = false,
    this.pinnedAtMs,
    required this.installedAtMs,
    required this.type,
    this.desc,
    this.changelog,
    this.icon,
    this.extras = const {},
  });

  factory InstalledPlugin.fromJson(Map<String, dynamic> json) {
    final rawExtras = json['extras'];
    return InstalledPlugin(
      id: json['id']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      installPath: json['installPath']?.toString() ?? '',
      enabled: json['enabled'] == true,
      pinned: json['pinned'] == true,
      pinnedAtMs: (json['pinnedAtMs'] is num)
          ? (json['pinnedAtMs'] as num).toInt()
          : null,
      installedAtMs: (json['installedAtMs'] is num)
          ? (json['installedAtMs'] as num).toInt()
          : 0,
      type: json['type']?.toString() ?? 'import',
      desc: json['desc']?.toString(),
      changelog: json['changelog']?.toString(),
      icon: json['icon']?.toString(),
      extras: rawExtras is Map
          ? Map<String, dynamic>.from(rawExtras)
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'source': source,
        'installPath': installPath,
        'enabled': enabled,
        'pinned': pinned,
        'pinnedAtMs': pinnedAtMs,
        'installedAtMs': installedAtMs,
        'type': type,
        'desc': desc,
        'changelog': changelog,
        'icon': icon,
        'extras': extras,
      };

  InstalledPlugin copyWith({
    bool? enabled,
    bool? pinned,
    int? pinnedAtMs,
    bool clearPinnedAt = false,
    String? desc,
    String? changelog,
    String? icon,
    Map<String, dynamic>? extras,
  }) {
    return InstalledPlugin(
      id: id,
      version: version,
      source: source,
      installPath: installPath,
      enabled: enabled ?? this.enabled,
      pinned: pinned ?? this.pinned,
      pinnedAtMs:
          clearPinnedAt ? null : (pinnedAtMs ?? this.pinnedAtMs),
      installedAtMs: installedAtMs,
      type: type,
      desc: desc ?? this.desc,
      changelog: changelog ?? this.changelog,
      icon: icon ?? this.icon,
      extras: extras ?? this.extras,
    );
  }
}