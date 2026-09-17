class JellyfinServer {
  final String id;
  final String name;
  final String baseUrl;
  final String? userId;
  final String? username;
  bool isDefault;  // 改为可变

  JellyfinServer({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.userId,
    this.username,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'userId': userId,
    'username': username,
    'isDefault': isDefault,
  };

  factory JellyfinServer.fromJson(Map<String, dynamic> json) => JellyfinServer(
    id: json['id'] as String,
    name: json['name'] as String,
    baseUrl: json['baseUrl'] as String,
    userId: json['userId'] as String?,
    username: json['username'] as String?,
    isDefault: json['isDefault'] as bool? ?? false,
  );

  JellyfinServer copyWith({String? userId, String? username, bool? isDefault}) => JellyfinServer(
    id: id,
    name: name,
    baseUrl: baseUrl,
    userId: userId ?? this.userId,
    username: username ?? this.username,
    isDefault: isDefault ?? this.isDefault,
  );
}