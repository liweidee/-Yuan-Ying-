class AlistDownloadRecord {
  final String id;
  final String serverId;
  final String userId;
  final String remotePath;
  final String name;
  final String sign;
  final String localPath;
  final String? thumbnail;
  final String? requestHeaders; // JSON 字符串
  final int? limitFrequency;
  final int createTime;
  bool finished;

  AlistDownloadRecord({
    required this.id,
    required this.serverId,
    required this.userId,
    required this.remotePath,
    required this.name,
    required this.sign,
    required this.localPath,
    this.thumbnail,
    this.requestHeaders,
    this.limitFrequency,
    required this.createTime,
    this.finished = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverId': serverId,
        'userId': userId,
        'remotePath': remotePath,
        'name': name,
        'sign': sign,
        'localPath': localPath,
        'thumbnail': thumbnail,
        'requestHeaders': requestHeaders,
        'limitFrequency': limitFrequency,
        'createTime': createTime,
        'finished': finished,
      };

  factory AlistDownloadRecord.fromJson(Map<String, dynamic> json) {
    return AlistDownloadRecord(
      id: json['id'] as String? ?? '',
      serverId: json['serverId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sign: json['sign'] as String? ?? '',
      localPath: json['localPath'] as String? ?? '',
      thumbnail: json['thumbnail'] as String?,
      requestHeaders: json['requestHeaders'] as String?,
      limitFrequency: json['limitFrequency'] as int?,
      createTime: json['createTime'] as int? ?? 0,
      finished: json['finished'] as bool? ?? false,
    );
  }
}