/// 洛雪自定义源脚本模型
class LxScript {
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final String homepage;
  final String content;
  final DateTime importedAt;
  final Map<String, LxScriptSource> sources;

  LxScript({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.homepage,
    required this.content,
    required this.importedAt,
    this.sources = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'author': author,
      'version': version,
      'homepage': homepage,
      'content': content,
      'importedAt': importedAt.toIso8601String(),
      'sources': sources.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  factory LxScript.fromJson(Map<String, dynamic> json) {
    Map<String, LxScriptSource> sources = {};
    final rawSources = json['sources'];
    if (rawSources is Map) {
      rawSources.forEach((k, v) {
        if (v is Map) {
          sources[k.toString()] =
              LxScriptSource.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    return LxScript(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      homepage: json['homepage']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      importedAt: DateTime.tryParse(json['importedAt']?.toString() ?? '') ??
          DateTime.now(),
      sources: sources,
    );
  }
}

/// 脚本注册的音源信息
class LxScriptSource {
  final String type;
  final List<String> actions;
  final List<String> qualitys;

  LxScriptSource({
    required this.type,
    required this.actions,
    required this.qualitys,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'actions': actions,
      'qualitys': qualitys,
    };
  }

  factory LxScriptSource.fromJson(Map<String, dynamic> json) {
    return LxScriptSource(
      type: json['type']?.toString() ?? 'music',
      actions: List<String>.from(json['actions'] ?? const []),
      qualitys: List<String>.from(json['qualitys'] ?? const []),
    );
  }
}

/// 脚本错误（含可重试判定，用于换源）
class LxMusicUrlException implements Exception {
  final String message;

  /// 是否值得换源重试：单歌转链失败可跨源恢复；全局错误跨源同样失败
  final bool retryable;

  LxMusicUrlException(this.message, {this.retryable = false});

  @override
  String toString() => message;

  static const _fatalKeywords = [
    'block ip',
    'too many requests',
    '签名',
    '鉴权',
    'forbidden',
    'limit',
  ];

  static bool isFatal(String msg) {
    final lower = msg.toLowerCase();
    return _fatalKeywords.any((k) => lower.contains(k));
  }
}