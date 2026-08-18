import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:yuanying/t4/models/site.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class SiteConfigController extends GetxController {
  final SourceManager sourceManager = Get.find<SourceManager>();
  final RxList<Site> sites = <Site>[].obs;
  final RxString currentSiteKey = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadSites();
  }

  void loadSites() {
    final customConfigs = GStorage.getCustomSites().map((s) => Site.fromJson(s)).toList();
    sites.clear();
    sites.addAll(customConfigs);

    final savedKey = GStorage.getSetting<String>('selected_config_key');
    if (savedKey != null && savedKey.isNotEmpty && sites.any((s) => s.key == savedKey)) {
      currentSiteKey.value = savedKey;
    } else if (sites.isNotEmpty) {
      currentSiteKey.value = sites.first.key;
    } else {
      currentSiteKey.value = '';
    }
  }

  Future<void> switchSite(String key) async {
    if (currentSiteKey.value == key) return;
    if (!sites.any((s) => s.key == key)) return;

    final targetSite = sites.firstWhere((s) => s.key == key);
    if (PlatformUtils.isDesktop && targetSite.isCatVodConfig) {
      SmartDialog.showToast('猫影视配置仅支持移动端');
      return;
    }

    // 1. 立即更新选中状态（同步）
    currentSiteKey.value = key;
    GStorage.setSetting('selected_config_key', key);
    
    // 2. 立即刷新 UI 列表（同步），高亮秒变
    loadSites();

    // 3. 异步执行配置加载（不阻塞 UI）
    final site = sites.firstWhere((s) => s.key == key);

    if (site.isLocalConfig) {
      // 本地缓存配置
      final packageKey = site.configPackageKey!;
      final package = GStorage.getConfigPackage(packageKey);
      if (package != null) {
        final sitesList = (package['sites'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
        final parsesList = (package['parses'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
        await sourceManager.applyLocalConfigPackage(
          sites: sitesList,
          parses: parsesList,
          siteKey: key,
          packageKey: packageKey,
        );
      } else {
        print('本地配置包不存在: $packageKey');
      }
    } else if (site.isLocalFile) {
      // 本地文件配置
      await sourceManager.loadFileConfig(site.api, siteKey: key);
    } else {
      // 远端配置
      await sourceManager.switchConfig(key);
    }

    loadSites();
  }

  void refreshListOnly() {
    loadSites();
  }

  // ===== 手动添加远端配置 =====
  void addSite(String name, String api, {String configType = 'tvbox'}) {
    if (PlatformUtils.isDesktop && configType == 'catvod') {
      SmartDialog.showToast('桌面端不支持猫影视配置');
      return;
    }

    final key = _generateKey(name);
    final newSite = Site(
      key: key,
      name: name,
      api: api,
      searchable: 1,
      filterable: 1,
      quickSearch: 1,
      lang: 'ds',
      logo: null,
      type: SiteConfigController.detectType(api, key),
      source: 'remote',
      configType: configType,
    );
    GStorage.addCustomSite(newSite.toJson());
    sites.add(newSite);

    if (sites.length == 1) {
      currentSiteKey.value = key;
      GStorage.setSetting('selected_config_key', key);
      sourceManager.switchConfig(key);
    } else {
      loadSites();
    }
  }

  // ===== 本地缓存配置（手动输入/剪切板导入） =====
  void addLocalConfig(String name, String fileName, Map<String, dynamic> configPackage, {String configType = 'tvbox'}) {
    // ===== 桌面端拦截 =====
    if (PlatformUtils.isDesktop && configType == 'catvod') {
      SmartDialog.showToast('桌面端不支持猫影视配置');
      return;
    }

    final key = _generateKey(name);
    final packageKey = 'package_${DateTime.now().millisecondsSinceEpoch}_$key';

    GStorage.saveConfigPackage(packageKey, configPackage);

    final newSite = Site(
      key: key,
      name: name,
      api: fileName,
      searchable: 1,
      filterable: 1,
      quickSearch: 1,
      lang: 'ds',
      logo: null,
      type: SiteConfigController.detectType(fileName),
      source: 'local',
      configPackageKey: packageKey,
      configType: configType,
    );
    GStorage.addCustomSite(newSite.toJson());
    sites.add(newSite);

    if (sites.length == 1) {
      currentSiteKey.value = key;
      GStorage.setSetting('selected_config_key', key);
      switchSite(key);
    } else {
      loadSites();
    }
  }

  // ===== 本地文件配置（只存路径） =====
  void addLocalFileSite(String name, String filePath) {
    final key = _generateKey(name);
    final newSite = Site(
      key: key,
      name: name,
      api: filePath,
      searchable: 1,
      filterable: 1,
      quickSearch: 1,
      lang: 'ds',
      logo: null,
      type: SiteConfigController.detectType(filePath),
      source: 'local_file',
      configPackageKey: null,
    );
    GStorage.addCustomSite(newSite.toJson());
    sites.add(newSite);

    if (sites.length == 1) {
      currentSiteKey.value = key;
      GStorage.setSetting('selected_config_key', key);
      switchSite(key);
    } else {
      loadSites();
    }
  }

  void updateSite(String key, String name, String api) {
    final index = sites.indexWhere((s) => s.key == key);
    if (index != -1) {
      final site = sites[index];
      final updatedSite = Site(
        key: key,
        name: name,
        api: site.isLocalConfig ? site.api : api,
        searchable: site.searchable,
        filterable: site.filterable,
        quickSearch: site.quickSearch,
        lang: site.lang,
        logo: site.logo,
        type: site.type,
        source: site.source,
        configPackageKey: site.configPackageKey,
        ext: site.ext,
      );
      sites[index] = updatedSite;
      GStorage.updateCustomSite(key, updatedSite.toJson());
      if (!site.isLocalConfig && !site.isLocalFile) {
        sourceManager.switchConfig(key);
      }
    }
  }

  Future<void> deleteSite(String key) async {
    final site = sites.firstWhereOrNull((s) => s.key == key);
    if (site != null && site.isLocalConfig && site.configPackageKey != null) {
      GStorage.deleteConfigPackage(site.configPackageKey!);
    }

    sites.removeWhere((s) => s.key == key);
    GStorage.removeCustomSite(key);

    if (currentSiteKey.value == key) {
      if (sites.isNotEmpty) {
        // 还有剩余配置，切换到第一个
        await switchSite(sites.first.key);
      } else {
        // 没有配置了，清空选中状态并重置 SourceManager
        currentSiteKey.value = '';
        GStorage.deleteSetting('selected_config_key');
        // 关键：重新加载配置，让 SourceManager 清空所有源列表
        await sourceManager.loadConfig();
      }
    }

    loadSites();
    SmartDialog.showToast('接口已移除');
  }

  String _generateKey(String name) {
    String key = name.toLowerCase().replaceAll(' ', '_');
    int index = 1;
    final existing = sites.map((s) => s.key).toList();
    while (existing.contains(key)) {
      key = '${name.toLowerCase().replaceAll(' ', '_')}_$index';
      index++;
    }
    return key;
  }

  static String detectType(String api, [String? key]) {
    final lower = api.toLowerCase();
    if (key != null && key.startsWith('catvod_')) return '3';
    if (lower.endsWith('drpy2.min.js') || lower.endsWith('drpy2.js')) return '3';
    if (lower == 'csp_xbpq' || lower == 'csp_xyqhiker') return '3';
    if (lower.endsWith('.js')) return '3';
    return '4';
  }
}