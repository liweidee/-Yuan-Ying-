class AlistFilePassword {
  final String id;
  final String serverId;
  final String userId;
  final String remotePath;
  final String password;
  final int createTime;

  AlistFilePassword({
    required this.id,
    required this.serverId,
    required this.userId,
    required this.remotePath,
    required this.password,
    required this.createTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverId': serverId,
        'userId': userId,
        'remotePath': remotePath,
        'password': password,
        'createTime': createTime,
      };

  factory AlistFilePassword.fromJson(Map<String, dynamic> json) {
    return AlistFilePassword(
      id: json['id'] as String? ?? '',
      serverId: json['serverId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '',
      password: json['password'] as String? ?? '',
      createTime: json['createTime'] as int? ?? 0,
    );
  }
}