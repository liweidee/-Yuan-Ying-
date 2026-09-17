/// 备份分类
enum BackupCategory {
  settings('设置与账户'),
  media('收藏与历史'),
  sources('站点与配置包');

  const BackupCategory(this.label);

  /// 用户可见的分类名
  final String label;

  /// 从字符串名称反序列化（用于 manifest.json 解析）
  static BackupCategory? fromName(String name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}