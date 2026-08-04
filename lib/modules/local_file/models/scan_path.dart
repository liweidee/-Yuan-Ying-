import 'package:hive_ce/hive_ce.dart';

@HiveType(typeId: 10)
class ScanPath {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String path;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final bool enabled;

  @HiveField(4)
  final DateTime? lastScanTime;

  @HiveField(5)
  final int videoCount;

  @HiveField(6)
  final int totalSize;

  ScanPath({
    required this.id,
    required this.path,
    required this.name,
    this.enabled = true,
    this.lastScanTime,
    this.videoCount = 0,
    this.totalSize = 0,
  });

  ScanPath copyWith({
    String? id,
    String? path,
    String? name,
    bool? enabled,
    DateTime? lastScanTime,
    int? videoCount,
    int? totalSize,
  }) {
    return ScanPath(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      lastScanTime: lastScanTime ?? this.lastScanTime,
      videoCount: videoCount ?? this.videoCount,
      totalSize: totalSize ?? this.totalSize,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'enabled': enabled,
        'lastScanTime': lastScanTime?.millisecondsSinceEpoch,
        'videoCount': videoCount,
        'totalSize': totalSize,
      };

  factory ScanPath.fromJson(Map<String, dynamic> json) => ScanPath(
        id: json['id'],
        path: json['path'],
        name: json['name'],
        enabled: json['enabled'] ?? true,
        lastScanTime: json['lastScanTime'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['lastScanTime'])
            : null,
        videoCount: json['videoCount'] ?? 0,
        totalSize: json['totalSize'] ?? 0,
      );
}