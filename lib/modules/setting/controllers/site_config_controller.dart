// lib/modules/setting/controllers/site_config_controller.dart

import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
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
    _ensureManualConfigExists();
    loadSites();
  }

  /// 确保手动源配置存在（一条固定记录）
  void _ensureManualConfigExists() {
    final list = GStorage.getCustomSites();
    final has = list.any((s) => s['key']?.toString() == SettingBoxKey.manualConfigKey);
    if (!has) {
      GStorage.addCustomSite({
        'key': SettingBoxKey.manualConfigKey,
        'name': '手动源',
        'api': 'manual',
        'searchable': 0,
        'filterable': 0,
        'quickSearch': 0,
        'lang': 'manual',
        'type': '3',
        '_source': 'manual',
        'configType': 'tvbox',
      });
    }
  }

  void loadSites() {
    final customConfigs = GStorage.getCustomSites().map((s) => Site.fromJson(s)).toList();
    // 手动源排最前
    customConfigs.sort((a, b) {
      final am = a.isManualConfig ? 0 : 1;
      final bm = b.isManualConfig ? 0 : 1;
      if (am != bm) return am.compareTo(bm);
      return 0;
    });
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

    currentSiteKey.value = key;
    GStorage.setSetting('selected_config_key', key);
    loadSites();

    final site = sites.firstWhere((s) => s.key == key);

    if (site.isManualConfig) {
      await sourceManager.switchToManualConfig();
    } else if (site.isLocalConfig) {
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
      await sourceManager.loadFileConfig(site.api, siteKey: key);
    } else {
      await sourceManager.switchConfig(key);
    }

    loadSites();
  }

  void refreshListOnly() {
    loadSites();
  }

  // ===== 手动源配置：重命名 =====
  void renameManualConfig(String name) {
    final index = sites.indexWhere((s) => s.isManualConfig);
    if (index < 0) return;
    final site = sites[index];
    final updated = Site(
      key: site.key,
      name: name,
      api: 'manual',
      searchable: 0,
      filterable: 0,
      quickSearch: 0,
      lang: 'manual',
      type: '3',
      source: 'manual',
      configType: 'tvbox',
    );
    sites[index] = updated;
    GStorage.updateCustomSite(site.key, updated.toJson());
    loadSites();
  }

  // ===== 手动添加远端配置 =====
  void addSite(String name, String api, {String configType = 'tvbox'}) {
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

  void addLocalConfig(String name, String fileName, Map<String, dynamic> configPackage, {String configType = 'tvbox'}) {
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
        api: site.isLocalConfig || site.isManualConfig ? site.api : api,
        searchable: site.searchable,
        filterable: site.filterable,
        quickSearch: site.quickSearch,
        lang: site.lang,
        logo: site.logo,
        type: site.type,
        source: site.source,
        configPackageKey: site.configPackageKey,
        ext: site.ext,
        configType: site.configType,
        zipFilePath: site.zipFilePath,
      );
      sites[index] = updatedSite;
      GStorage.updateCustomSite(key, updatedSite.toJson());
      if (!site.isLocalConfig && !site.isLocalFile && !site.isManualConfig) {
        sourceManager.switchConfig(key);
      }
    }
  }

  Future<void> deleteSite(String key) async {
    final site = sites.firstWhereOrNull((s) => s.key == key);
    if (site == null) return;
    // 手动源配置不可删除
    if (site.isManualConfig) {
      SmartDialog.showToast('手动源配置不可删除');
      return;
    }

    if (site.isLocalConfig && site.configPackageKey != null) {
      GStorage.deleteConfigPackage(site.configPackageKey!);
    }

    sites.removeWhere((s) => s.key == key);
    GStorage.removeCustomSite(key);

    if (currentSiteKey.value == key) {
      if (sites.isNotEmpty) {
        await switchSite(sites.first.key);
      } else {
        currentSiteKey.value = '';
        GStorage.deleteSetting('selected_config_key');
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
    if (lower == 'csp_appcms') return '3';
    if (lower == 'csp_appv2') return '3';
    if (lower == 'csp_appysv2') return '3';
    if (lower.endsWith('.js')) return '3';
    return '4';
  }
}