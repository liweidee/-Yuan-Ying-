// lib/core/constants/plugin_storage_keys.dart

/// 插件中心专用 Hive Box / Key
abstract final class PluginStorageKeys {
  /// 市场源列表 + 索引缓存
  static const String marketBox = 'plugin_market';

  /// 已装插件登记
  static const String installedBox = 'plugin_installed';

  /// 服务配置
  static const String serviceBox = 'plugin_services';

  // ===== marketBox 内的 Key =====
  static const String marketSources = 'market_sources';
  static const String marketIndexCachePrefix = 'market_index_';

  // ===== installedBox 内的 Key =====
  /// 存放 List<Map> 的键
  static const String installedList = 'installed_list';

  // ===== serviceBox 内的 Key =====
  /// 存放 List<Map> 的键
  static const String serviceList = 'service_list';

  /// 自动清理开关
  static const String autoCleanOrphan = 'auto_clean_orphan';
}