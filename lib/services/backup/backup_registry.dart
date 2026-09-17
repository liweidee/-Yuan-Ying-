import 'package:yuanying/core/constants/storage_keys.dart';

import 'backup_category.dart';
import 'backup_entry.dart';

/// 备份清单
///
/// 新增需要备份的 Hive Box 时，只需在 [entries] 里加一行。
/// 未在此声明的 Box 不会被导出。
abstract final class BackupRegistry {
  static const List<BackupEntry> entries = <BackupEntry>[
    BackupEntry(
      boxName: 'setting',
      category: BackupCategory.settings,
      displayName: '基础设置',
    ),
    BackupEntry(
      boxName: 'app_settings',
      category: BackupCategory.settings,
      displayName: '应用设置',
      // 下载记录与本地文件路径关联，跨设备恢复后失效，因此不备份
      excludedKeys: <String>{
        EmbyStorageKeys.downloadList,      // 'emby_download_list'
        JellyfinStorageKeys.downloadList,  // 'jellyfin_download_list'
        AlistStorageKeys.downloadRecords,  // 'alist_download_records'
      },
    ),
    BackupEntry(
      boxName: 'video_settings',
      category: BackupCategory.settings,
      displayName: '播放器设置',
    ),
    BackupEntry(
      boxName: 'video',
      category: BackupCategory.media,
      displayName: '收藏',
    ),
    BackupEntry(
      boxName: 'historyWord',
      category: BackupCategory.media,
      displayName: '搜索历史',
    ),
    BackupEntry(
      boxName: 'watchProgress',
      category: BackupCategory.media,
      displayName: '观看进度',
    ),
    BackupEntry(
      boxName: 'custom_sites',
      category: BackupCategory.sources,
      displayName: '自定义站点',
    ),
    BackupEntry(
      boxName: 'config_package',
      category: BackupCategory.sources,
      displayName: '本地配置包',
    ),
  ];

  static List<BackupEntry> byCategory(BackupCategory category) =>
      entries.where((e) => e.category == category).toList();

  static BackupEntry? byName(String boxName) {
    for (final e in entries) {
      if (e.boxName == boxName) return e;
    }
    return null;
  }
}