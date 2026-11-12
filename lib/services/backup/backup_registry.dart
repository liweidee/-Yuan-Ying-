import 'package:yuanying/core/constants/storage_keys.dart';

import 'backup_category.dart';
import 'backup_entry.dart';

/// 备份清单
///
/// 新增需要备份的 Hive Box 时，只需在 [entries] 里加一行。
/// 未在此声明的 Box 不会被导出。
abstract final class BackupRegistry {
  static const List<BackupEntry> entries = <BackupEntry>[
    // ============================================================
    // settings
    // ============================================================
    BackupEntry(
      boxName: 'setting',
      category: BackupCategory.settings,
      displayName: '基础设置',
    ),
    BackupEntry(
      boxName: 'app_settings',
      category: BackupCategory.settings,
      displayName: '应用设置',
      excludedKeys: <String>{
        EmbyStorageKeys.downloadList,      // 'emby_download_list'
        JellyfinStorageKeys.downloadList,  // 'jellyfin_download_list'
        AlistStorageKeys.downloadRecords,  // 'alist_download_records'
        SettingBoxKey.localFileScanPaths,  // 'local_file_scan_paths'
        SettingBoxKey.downloadPath,        // 'downloadPath'（设备专属绝对路径）
      },
    ),
    BackupEntry(
      boxName: 'video_settings',
      category: BackupCategory.settings,
      displayName: '播放器设置',
    ),
    BackupEntry(
      boxName: 'player_settings',
      category: BackupCategory.settings,
      displayName: '播放器设置(旧)',
    ),
    BackupEntry(
      boxName: 'sandbox_pref',
      category: BackupCategory.settings,
      displayName: '沙盒偏好',
    ),
    BackupEntry(
      boxName: 'web_ds_default',
      category: BackupCategory.settings,
      displayName: 'Web Tab 默认值',
    ),

    // ============================================================
    // media
    // ============================================================
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
      boxName: 'tmdb_matches',
      category: BackupCategory.media,
      displayName: 'TMDB 匹配记录',
    ),

    // ============================================================
    // sources
    // ============================================================
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
    BackupEntry(
      boxName: 'plugin_market',
      category: BackupCategory.sources,
      displayName: '插件市场',
    ),
    BackupEntry(
      boxName: 'lx_music',
      category: BackupCategory.sources,
      displayName: '洛雪音乐',
    ),
    BackupEntry(
      boxName: 'manual_source_meta',
      category: BackupCategory.sources,
      displayName: '手动源元信息',
    ),
    BackupEntry(
      boxName: 'manual_source_order',
      category: BackupCategory.sources,
      displayName: '手动源排序',
    ),
    BackupEntry(
      boxName: 'manual_source_disabled',
      category: BackupCategory.sources,
      displayName: '手动源禁用',
    ),
    BackupEntry(
      boxName: 'py_source_meta',
      category: BackupCategory.sources,
      displayName: 'PY 源元信息',
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