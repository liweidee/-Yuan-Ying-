class Site {
  final String key;
  final String name;
  final String api;
  final int searchable;
  final int filterable;
  final int quickSearch;
  final String lang;
  final dynamic ext;
  final String? type;
  final String? author;
  final String? logo;

  // 配置来源：'remote'（远端URL）、'local'（Hive缓存）、'local_file'（本地文件路径）
  final String? source;

  // 接口配置类型
  final String configType; // 'tvbox' 或 'catvod'

  // 关联的配置包 key（仅本地缓存配置使用）
  final String? configPackageKey;

  Site({
    required this.key,
    required this.name,
    required this.api,
    required this.searchable,
    required this.filterable,
    required this.quickSearch,
    required this.lang,
    this.ext,
    this.type,
    this.author,
    this.logo,
    this.source,
    this.configPackageKey,
    this.configType = 'tvbox',  // 默认 TVBox
  });

  bool get isLocalConfig => source == 'local';
  bool get isLocalFile => source == 'local_file';
  bool get isCatVodConfig => configType == 'catvod';

  factory Site.fromJson(Map<String, dynamic> json) {
    return Site(
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      api: json['api']?.toString() ?? '',
      searchable: json['searchable'] ?? 0,
      filterable: json['filterable'] ?? 0,
      quickSearch: json['quickSearch'] ?? 0,
      lang: json['lang']?.toString() ?? 'ds',
      ext: json['ext'],
      type: json['type']?.toString(),
      author: json['author']?.toString(),
      logo: json['logo']?.toString(),
      source: json['_source']?.toString(),
      configPackageKey: json['_configKey']?.toString(),
      configType: json['configType']?.toString() ?? 'tvbox',  // 兼容旧数据
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'api': api,
      'searchable': searchable,
      'filterable': filterable,
      'quickSearch': quickSearch,
      'lang': lang,
      if (ext != null) 'ext': ext,
      if (type != null) 'type': type,
      if (author != null) 'author': author,
      if (logo != null) 'logo': logo,
      if (source != null) '_source': source,
      if (configPackageKey != null) '_configKey': configPackageKey,
      'configType': configType,
    };
  }
}