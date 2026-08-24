class DanmakuApi {
  final String key;
  final String name;
  final String api;

  DanmakuApi({required this.key, required this.name, required this.api});

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'api': api,
      };

  factory DanmakuApi.fromJson(Map<String, dynamic> json) {
    return DanmakuApi(
      key: json['key'] as String,
      name: json['name'] as String,
      api: json['api'] as String,
    );
  }
}