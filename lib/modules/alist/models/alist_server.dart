class AlistServer {
  final String id;
  final String name;
  final String serverUrl; // 形如 http://host:5244/
  final String? username;
  final String? password;
  final bool guest;
  final bool ignoreSSLError;
  bool isDefault;

  AlistServer({
    required this.id,
    required this.name,
    required this.serverUrl,
    this.username,
    this.password,
    this.guest = false,
    this.ignoreSSLError = false,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'guest': guest,
        'ignoreSSLError': ignoreSSLError,
        'isDefault': isDefault,
      };

  factory AlistServer.fromJson(Map<String, dynamic> json) => AlistServer(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'AList',
        serverUrl: json['serverUrl'] as String? ?? '',
        username: json['username'] as String?,
        password: json['password'] as String?,
        guest: json['guest'] as bool? ?? false,
        ignoreSSLError: json['ignoreSSLError'] as bool? ?? false,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  AlistServer copyWith({
    String? name,
    String? serverUrl,
    String? username,
    String? password,
    bool? guest,
    bool? ignoreSSLError,
    bool? isDefault,
  }) =>
      AlistServer(
        id: id,
        name: name ?? this.name,
        serverUrl: serverUrl ?? this.serverUrl,
        username: username ?? this.username,
        password: password ?? this.password,
        guest: guest ?? this.guest,
        ignoreSSLError: ignoreSSLError ?? this.ignoreSSLError,
        isDefault: isDefault ?? this.isDefault,
      );
}