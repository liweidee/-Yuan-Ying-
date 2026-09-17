import 'backup_category.dart';

/// manifest.json 中单个 Box 的元信息
class BackupBoxInfo {
  final String name;
  final BackupCategory category;
  final int count;
  final int bytes;

  const BackupBoxInfo({
    required this.name,
    required this.category,
    required this.count,
    required this.bytes,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'category': category.name,
    'count': count,
    'bytes': bytes,
  };

  static BackupBoxInfo? fromJson(Map<String, dynamic> json) {
    final category =
        BackupCategory.fromName(json['category']?.toString() ?? '');
    if (category == null) return null;
    return BackupBoxInfo(
      name: json['name']?.toString() ?? '',
      category: category,
      count: (json['count'] as num?)?.toInt() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// manifest.json 完整结构
class BackupManifest {
  static const String format = 'yuanying-backup';
  static const int currentFormatVersion = 1;

  final String formatName;
  final int formatVersion;
  final String appVersion;
  final int appVersionCode;
  final String platform;
  final DateTime exportedAt;
  final List<BackupBoxInfo> boxes;

  const BackupManifest({
    required this.formatName,
    required this.formatVersion,
    required this.appVersion,
    required this.appVersionCode,
    required this.platform,
    required this.exportedAt,
    required this.boxes,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': formatName,
    'formatVersion': formatVersion,
    'appVersion': appVersion,
    'appVersionCode': appVersionCode,
    'platform': platform,
    'exportedAt': exportedAt.toIso8601String(),
    'boxes': boxes.map((b) => b.toJson()).toList(),
  };

  static BackupManifest fromJson(Map<String, dynamic> json) {
    final rawBoxes = json['boxes'];
    final boxes = <BackupBoxInfo>[];
    if (rawBoxes is List) {
      for (final item in rawBoxes) {
        if (item is Map) {
          final info = BackupBoxInfo.fromJson(Map<String, dynamic>.from(item));
          if (info != null && info.name.isNotEmpty) boxes.add(info);
        }
      }
    }
    return BackupManifest(
      formatName: json['format']?.toString() ?? '',
      formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 0,
      appVersion: json['appVersion']?.toString() ?? '',
      appVersionCode: (json['appVersionCode'] as num?)?.toInt() ?? 0,
      platform: json['platform']?.toString() ?? '',
      exportedAt:
          DateTime.tryParse(json['exportedAt']?.toString() ?? '') ??
              DateTime.now(),
      boxes: boxes,
    );
  }

  Set<BackupCategory> get categories =>
      boxes.map((b) => b.category).toSet();

  int get totalCount => boxes.fold(0, (sum, b) => sum + b.count);
  int get totalBytes => boxes.fold(0, (sum, b) => sum + b.bytes);
}