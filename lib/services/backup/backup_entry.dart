import 'backup_category.dart';

/// 描述一个参与备份的 Hive Box
class BackupEntry {
  /// Hive Box 名
  final String boxName;

  /// 所属分类
  final BackupCategory category;

  /// 用户可见名
  final String displayName;

  /// 导出时需要从 Box 中过滤掉的键
  ///
  /// 用于排除「跨设备失效」的数据，例如：
  /// - 下载记录（本地文件路径）
  /// - 本地扫描路径（用户设备专属）
  ///
  /// 导入时不做特殊处理（统一 clear + putAll）。
  final Set<String> excludedKeys;

  const BackupEntry({
    required this.boxName,
    required this.category,
    required this.displayName,
    this.excludedKeys = const {},
  });
}