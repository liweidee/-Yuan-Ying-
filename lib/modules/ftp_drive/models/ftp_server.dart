class FtpServer {
  final String id;
  final String name;
  final String host;
  final int port;
  final String protocol;   // 'ftp' | 'sftp'
  final String username;
  final String password;
  final String initialPath; // 初始目录，默认 '/'

  const FtpServer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.protocol,
    this.username = '',
    this.password = '',
    this.initialPath = '/',
  });

  bool get isSftp => protocol == 'sftp';

  String get protocolLabel => isSftp ? 'SFTP' : 'FTP';

  /// 副标题：`FTP · host:port · username`（DreamPlayer 风格）
  String get subtitle {
    final auth = username.isEmpty ? 'No login' : username;
    return '$protocolLabel · $host:$port · $auth';
  }

  FtpServer copyWith({
    String? name,
    String? host,
    int? port,
    String? protocol,
    String? username,
    String? password,
    String? initialPath,
  }) =>
      FtpServer(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        protocol: protocol ?? this.protocol,
        username: username ?? this.username,
        password: password ?? this.password,
        initialPath: initialPath ?? this.initialPath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'protocol': protocol,
        'username': username,
        'password': password,
        'initialPath': initialPath,
      };

  factory FtpServer.fromJson(Map<String, dynamic> j) => FtpServer(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 21,
        protocol: j['protocol'] as String? ?? 'ftp',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        initialPath: j['initialPath'] as String? ?? '/',
      );
}