import 'package:get/get.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/storage.dart';

/// 搜索筛选服务（全局单例）
class SearchFilterService extends GetxService {
  final SourceManager _sourceManager = Get.find<SourceManager>();

  // ===== 状态 =====
  final RxBool onlyDefaultSource = true.obs;
  final RxList<String> enabledSourceKeys = <String>[].obs;
  final RxString filterSearchQuery = ''.obs;

  // ===== 存储键 =====
  static const String _storageOnlyDefault = 'search_only_default';
  static const String _storageEnabledSources = 'search_enabled_sources';

  // ===== 获取所有可搜索的源 =====
  List<Map<String, dynamic>> get searchableSites {
    return _sourceManager.sites.where((site) {
      final searchable = site['searchable'] as int? ?? 0;
      return searchable != 0;
    }).toList();
  }

  // ===== 获取当前启用的源列表 =====
  List<Map<String, dynamic>> get enabledSites {
    if (onlyDefaultSource.value) {
      final current = _sourceManager.currentSite.value;
      if (current != null) {
        final searchable = current['searchable'] as int? ?? 0;
        if (searchable != 0) {
          return [current];
        }
      }
      return [];
    }
    return searchableSites.where((site) {
      final key = site['key']?.toString() ?? '';
      return enabledSourceKeys.contains(key);
    }).toList();
  }

  // ===== 获取当前启用的源 key 列表 =====
  List<String> get enabledSourceKeyList {
    return enabledSites.map((site) => site['key']?.toString() ?? '').where((key) => key.isNotEmpty).toList();
  }

  // ===== 初始化 =====
  @override
  void onInit() {
    super.onInit();
    _loadConfig();
  }

  // ===== 加载配置 =====
  void _loadConfig() {
    onlyDefaultSource.value = GStorage.getSetting<bool>(_storageOnlyDefault) ?? true;

    final saved = GStorage.getSetting<List<dynamic>>(_storageEnabledSources);
    if (saved != null && saved.isNotEmpty) {
      enabledSourceKeys.value = saved.map((e) => e.toString()).toList();
    } else {
      // 默认：所有可搜索的源都启用
      enabledSourceKeys.value = searchableSites
          .map((site) => site['key']?.toString() ?? '')
          .where((key) => key.isNotEmpty)
          .toList();
    }
  }

  // ===== 保存配置 =====
  void _saveConfig() {
    GStorage.setSetting(_storageOnlyDefault, onlyDefaultSource.value);
    GStorage.setSetting(_storageEnabledSources, enabledSourceKeys.toList());
  }

  // ===== 切换只搜默认源 =====
  void toggleOnlyDefaultSource(bool value) {
    onlyDefaultSource.value = value;
    _saveConfig();
  }

  // ===== 切换单个源启用状态 =====
  void toggleSourceEnabled(String key, bool enabled) {
    if (enabled) {
      if (!enabledSourceKeys.contains(key)) {
        enabledSourceKeys.add(key);
      }
    } else {
      enabledSourceKeys.remove(key);
    }
    _saveConfig();
  }

  // ===== 全选 =====
  void selectAllSources() {
    final keys = searchableSites
        .map((site) => site['key']?.toString() ?? '')
        .where((key) => key.isNotEmpty)
        .toList();
    enabledSourceKeys.value = keys;
    _saveConfig();
  }

  // ===== 全不选 =====
  void deselectAllSources() {
    enabledSourceKeys.clear();
    _saveConfig();
  }

  // ===== 检查源是否启用 =====
  bool isSourceEnabled(String key) {
    return enabledSourceKeys.contains(key);
  }

  // ===== 获取过滤后的源列表 =====
  List<Map<String, dynamic>> getFilteredSites(String query) {
    if (query.trim().isEmpty) {
      return searchableSites;
    }
    final lowerQuery = query.toLowerCase();
    return searchableSites.where((site) {
      final name = site['name']?.toString()?.toLowerCase() ?? '';
      final key = site['key']?.toString()?.toLowerCase() ?? '';
      return name.contains(lowerQuery) || key.contains(lowerQuery);
    }).toList();
  }

  // ===== 更新筛选弹窗搜索词 =====
  void updateFilterSearch(String value) {
    filterSearchQuery.value = value;
  }
}