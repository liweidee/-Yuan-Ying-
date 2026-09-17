/// 飞牛影视服务器配置模型
class FnosServer {
  final String id;
  final String name;
  final String baseUrl;
  final String? userId;
  final String? username;
  bool isDefault;

  FnosServer({
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

  factory FnosServer.fromJson(Map<String, dynamic> json) => FnosServer(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        userId: json['userId'] as String?,
        username: json['username'] as String?,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  FnosServer copyWith({
    String? userId,
    String? username,
    bool? isDefault,
  }) =>
      FnosServer(
        id: id,
        name: name,
        baseUrl: baseUrl,
        userId: userId ?? this.userId,
        username: username ?? this.username,
        isDefault: isDefault ?? this.isDefault,
      );
}