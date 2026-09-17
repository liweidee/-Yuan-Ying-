class AlistFileViewingRecord {
  final String id;
  final String serverId;
  final String userId;
  final String remotePath;
  final String name;
  final String path;
  final int size;
  final String? sign;
  final String? thumb;
  final int modified;
  final String provider;
  final int createTime;

  AlistFileViewingRecord({
    required this.id,
    required this.serverId,
    required this.userId,
    required this.remotePath,
    required this.name,
    required this.path,
    required this.size,
    this.sign,
    this.thumb,
    required this.modified,
    required this.provider,
    required this.createTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverId': serverId,
        'userId': userId,
        'remotePath': remotePath,
        'name': name,
        'path': path,
        'size': size,
        'sign': sign,
        'thumb': thumb,
        'modified': modified,
        'provider': provider,
        'createTime': createTime,
      };

  factory AlistFileViewingRecord.fromJson(Map<String, dynamic> json) {
    return AlistFileViewingRecord(
      id: json['id'] as String? ?? '',
      serverId: json['serverId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '',
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      sign: json['sign'] as String?,
      thumb: json['thumb'] as String?,
      modified: json['modified'] as int? ?? 0,
      provider: json['provider'] as String? ?? '',
      createTime: json['createTime'] as int? ?? 0,
    );
  }
}