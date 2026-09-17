class WebDavServer {
  final String id;
  final String name;
  final String url;         // 完整地址，如 http://192.168.1.100:8080/dav
  final String username;
  final String password;    // 明文存储（源影是纯 Dart，无 native 安全存储）
  final bool allowSelfSigned;

  const WebDavServer({
    required this.id,
    required this.name,
    required this.url,
    this.username = '',
    this.password = '',
    this.allowSelfSigned = false,
  });

  /// 副标题格式：`url · username`（与 DreamPlayer 一致）
  String get subtitle {
    final auth = username.isEmpty ? 'No login' : username;
    final ssl = allowSelfSigned ? ' · self-signed OK' : '';
    return '$url · $auth$ssl';
  }

  WebDavServer copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    bool? allowSelfSigned,
  }) =>
      WebDavServer(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
        allowSelfSigned: allowSelfSigned ?? this.allowSelfSigned,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
        'password': password,
        'allowSelfSigned': allowSelfSigned,
      };

  factory WebDavServer.fromJson(Map<String, dynamic> j) => WebDavServer(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        url: j['url'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        allowSelfSigned: j['allowSelfSigned'] as bool? ?? false,
      );
}