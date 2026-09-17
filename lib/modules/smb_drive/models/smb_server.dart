class SmbServer {
  final String id;
  final String name;
  final String host;
  final int port;
  final String domain;      // WORKGROUP 或 AD 域名
  final String username;
  final String password;
  final bool anonymous;     // Guest 模式

  const SmbServer({
    required this.id,
    required this.name,
    required this.host,
    this.port = 445,
    this.domain = '',
    this.username = '',
    this.password = '',
    this.anonymous = false,
  });

  /// 副标题：`host:port · domain\user`（DreamPlayer 风格）
  String get subtitle {
    final cred = anonymous
        ? 'Guest'
        : (domain.isNotEmpty ? '$domain\\$username' : username);
    return '$host:$port · $cred';
  }

  SmbServer copyWith({
    String? name,
    String? host,
    int? port,
    String? domain,
    String? username,
    String? password,
    bool? anonymous,
  }) =>
      SmbServer(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        domain: domain ?? this.domain,
        username: username ?? this.username,
        password: password ?? this.password,
        anonymous: anonymous ?? this.anonymous,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'domain': domain,
        'username': username,
        'password': password,
        'anonymous': anonymous,
      };

  factory SmbServer.fromJson(Map<String, dynamic> j) => SmbServer(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 445,
        domain: j['domain'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        anonymous: j['anonymous'] as bool? ?? false,
      );
}