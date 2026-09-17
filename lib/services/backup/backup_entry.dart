import 'backup_category.dart';

/// 描述一个参与备份的 Hive Box
class BackupEntry {
  /// Hive Box 名
  final String boxName;

  /// 所属分类
  final BackupCategory category;

  /// 用户可见名
  final String displayName;

  /// 导出/导入时需要从 Box 中过滤掉的键（例如运行期生成的下载记录）
  final Set<String> excludedKeys;

  const BackupEntry({
    required this.boxName,
    required this.category,
    required this.displayName,
    this.excludedKeys = const {},
  });
}