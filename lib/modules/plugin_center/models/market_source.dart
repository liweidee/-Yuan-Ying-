// lib/modules/plugin_center/models/market_source.dart

/// 市场源
class MarketSource {
  final String id;
  final String name;
  final String url;
  final bool enabled;

  /// GitHub 加速代理前缀；空串=直连
  final String proxy;

  /// 缓存时间戳（ms）
  final int cachedAtMs;

  MarketSource({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.proxy = 'https://gh-proxy.com/',
    this.cachedAtMs = 0,
  });

  factory MarketSource.fromJson(Map<String, dynamic> json) {
    return MarketSource(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      enabled: json['enabled'] != false,
      proxy: json['proxy']?.toString() ?? '',
      cachedAtMs: (json['cachedAtMs'] is num)
          ? (json['cachedAtMs'] as num).toInt()
          : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'enabled': enabled,
        'proxy': proxy,
        'cachedAtMs': cachedAtMs,
      };

  MarketSource copyWith({
    String? name,
    String? url,
    bool? enabled,
    String? proxy,
    int? cachedAtMs,
  }) {
    return MarketSource(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
      proxy: proxy ?? this.proxy,
      cachedAtMs: cachedAtMs ?? this.cachedAtMs,
    );
  }
}