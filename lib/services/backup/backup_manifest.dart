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

/// manifest.json 中文件系统内容的元信息
class BackupFileInfo {
  /// 条目 id，如 'spider' / 'wallpaper'
  final String id;

  final BackupCategory category;
  final int count;
  final int bytes;

  const BackupFileInfo({
    required this.id,
    required this.category,
    required this.count,
    required this.bytes,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'category': category.name,
        'count': count,
        'bytes': bytes,
      };

  static BackupFileInfo? fromJson(Map<String, dynamic> json) {
    final category =
        BackupCategory.fromName(json['category']?.toString() ?? '');
    if (category == null) return null;
    return BackupFileInfo(
      id: json['id']?.toString() ?? '',
      category: category,
      count: (json['count'] as num?)?.toInt() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// manifest.json 完整结构
class BackupManifest {
  static const String format = 'yuanying-backup';

  /// 1：仅 boxes（旧版，不再支持）
  /// 2：boxes + files（spider 目录 / 壁纸）
  static const int currentFormatVersion = 2;

  final String formatName;
  final int formatVersion;
  final String appVersion;
  final int appVersionCode;
  final String platform;
  final DateTime exportedAt;
  final List<BackupBoxInfo> boxes;
  final List<BackupFileInfo> files;

  const BackupManifest({
    required this.formatName,
    required this.formatVersion,
    required this.appVersion,
    required this.appVersionCode,
    required this.platform,
    required this.exportedAt,
    required this.boxes,
    this.files = const [],
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'format': formatName,
        'formatVersion': formatVersion,
        'appVersion': appVersion,
        'appVersionCode': appVersionCode,
        'platform': platform,
        'exportedAt': exportedAt.toIso8601String(),
        'boxes': boxes.map((b) => b.toJson()).toList(),
        'files': files.map((f) => f.toJson()).toList(),
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
    final rawFiles = json['files'];
    final files = <BackupFileInfo>[];
    if (rawFiles is List) {
      for (final item in rawFiles) {
        if (item is Map) {
          final info = BackupFileInfo.fromJson(Map<String, dynamic>.from(item));
          if (info != null && info.id.isNotEmpty) files.add(info);
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
      files: files,
    );
  }

  /// 分类集合（boxes + files 合并去重）
  Set<BackupCategory> get categories {
    final set = <BackupCategory>{...boxes.map((b) => b.category)};
    set.addAll(files.map((f) => f.category));
    return set;
  }

  int get totalCount =>
      boxes.fold(0, (sum, b) => sum + b.count) +
      files.fold(0, (sum, f) => sum + f.count);

  int get totalBytes =>
      boxes.fold(0, (sum, b) => sum + b.bytes) +
      files.fold(0, (sum, f) => sum + f.bytes);
}