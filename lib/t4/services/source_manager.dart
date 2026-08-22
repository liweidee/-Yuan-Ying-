import 'dart:io';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:yuanying/t4/services/t4_api_service.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:collection/collection.dart';
import 'package:yuanying/t4/services/drpy2_api_service.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/t4/services/xbpq_service.dart';
import 'package:yuanying/t4/services/xyq_service.dart';
import 'package:yuanying/t4/services/catvod_open_service.dart';
import 'package:yuanying/t4/services/py3_spider_service.dart';
import 'package:yuanying/core/constants/storage_keys.dart';

import 'package:yuanying/t4/services/nodejs_spider_service.dart';
import 'package:yuanying/nodejs/nodejs_service.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class SourceManager extends GetxController {
  final T4ApiService _apiService = Get.find<T4ApiService>();
  final Drpy2ApiService _drpy2Service = Get.find<Drpy2ApiService>();

  // ===== 三类配置的爬虫源列表 =====
  final RxList<Map<String, dynamic>> remoteSites = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> remoteParses = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> localSites = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> localParses = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> fileSites = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> fileParses = <Map<String, dynamic>>[].obs;

  // ===== 当前状态 =====
  final Rx<Map<String, dynamic>?> currentSite = Rx<Map<String, dynamic>?>(null);
  final RxList<Map<String, dynamic>> currentParses = <Map<String, dynamic>>[].obs;
  final RxString configLogo = ''.obs;
  final RxBool isConfigLoaded = false.obs;
  final RxString configSource = 'remote'.obs; // 'remote' | 'local' | 'file'
  final RxBool isConfigLoading = false.obs;
  final RxBool configLoadError = false.obs;
  final RxString currentConfigType = 'tvbox'.obs;

  // ===== 内部状态 =====
  bool _isRestoring = false;

  // ===== 辅助方法 =====
  void _saveCurrentSiteKey() {
    final site = currentSite.value;
    if (site != null) {
      final key = site['key']?.toString();
      if (key != null && key.isNotEmpty) {
        GStorage.setSetting(SettingBoxKey.lastSelectedSiteKey, key);
      }
    }
  }

  // ===== 静态爬虫类型判断 =====
  static bool isDrpy2Site(Map<String, dynamic> site) {
    final type = site['type']?.toString() ?? '';
    final api = site['api']?.toString() ?? '';
    final apiWithoutQuery = api.split('?')[0];
    return type == '3' &&
        (apiWithoutQuery.endsWith('drpy2.min.js') || apiWithoutQuery.endsWith('drpy2.js'));
  }
  static bool isXbpqSite(Map<String, dynamic> site) {
    final api = site['api']?.toString() ?? '';
    return api == 'csp_XBPQ';
  }
  static bool isXyqSite(Map<String, dynamic> site) {
    final api = site['api']?.toString() ?? '';
    return api == 'csp_XYQHiker';
  }
  static bool isCatVodOpenSite(Map<String, dynamic> site) {
    final type = site['type']?.toString() ?? '';
    final key = site['key']?.toString() ?? '';
    return type == '3' && key.startsWith('catvod_');
  }
  static bool isPurePy3Site(Map<String, dynamic> site) {
    final type = site['type']?.toString() ?? '';
    final api = site['api']?.toString() ?? '';
    if (type != '3') return false;
    final apiWithoutQuery = api.split('?')[0];
    return apiWithoutQuery.endsWith('.py');
  }
  static bool isNodeJSSite(Map<String, dynamic> site) {
    final type = site['type']?.toString() ?? '';
    final key = site['key']?.toString() ?? '';
    return type == '3' && key.startsWith('nodejs_');
  }

  // ===== 获取当前使用的爬虫服务 =====
  ISpiderService get currentApiService {
    final site = currentSite.value;
    if (site == null) return _apiService;
    if (isXbpqSite(site)) return _getOrCreateXbpqService(site);
    if (isXyqSite(site)) return _getOrCreateXyqService(site);
    if (isCatVodOpenSite(site)) return _getOrCreateCatvodOpenService(site);
    if (isPurePy3Site(site)) return _getOrCreatePy3Service(site);
    if (isDrpy2Site(site)) return _drpy2Service;
    if (isNodeJSSite(site)) return _getNodeJSService();
    return _apiService;
  }

  // ===== 独立服务（详情页使用） =====
  ISpiderService createIndependentService(Map<String, dynamic> site) {
    final key = site['key']?.toString() ?? '';
    final api = site['api']?.toString() ?? '';
    final ext = site['ext'];

    if (!isDrpy2Site(site) && !isXbpqSite(site) && !isCatVodOpenSite(site) &&
        !isPurePy3Site(site) && !isXyqSite(site) && !isNodeJSSite(site)) {
      final service = T4ApiService();
      service.switchSite(api, key, ext: ext);
      return service;
    }

    if (isXbpqSite(site)) {
      final tag = 'xbpq_$key';
      if (!Get.isRegistered<XbpqService>(tag: tag)) {
        final service = XbpqService(key, api, ext?.toString() ?? '', []);
        Get.put(service, tag: tag, permanent: true);
      }
      return Get.find<XbpqService>(tag: tag);
    }
    if (isXyqSite(site)) {
      final tag = 'xyq_$key';
      if (!Get.isRegistered<XyqService>(tag: tag)) {
        final service = XyqService(key, api, ext?.toString() ?? '', []);
        Get.put(service, tag: tag, permanent: true);
      }
      return Get.find<XyqService>(tag: tag);
    }
    if (isPurePy3Site(site)) {
      final tag = 'py3_$key';
      if (!Get.isRegistered<Py3SpiderService>(tag: tag)) {
        final service = Py3SpiderService(key);
        Get.put(service, tag: tag, permanent: true);
      }
      return Get.find<Py3SpiderService>(tag: tag);
    }
    if (isDrpy2Site(site)) return _drpy2Service;
    if (isCatVodOpenSite(site)) return Get.find<CatvodOpenService>();
    if (isNodeJSSite(site)) return _getNodeJSService();
    return currentApiService;
  }

  // ===== 推送代理站点缓存 =====
  final Rx<Map<String, dynamic>?> _pushAgentSite = Rx<Map<String, dynamic>?>(null);
  Map<String, dynamic>? get pushAgentSite => _pushAgentSite.value;

  // ===== 获取当前活动的爬虫源列表 =====
  List<Map<String, dynamic>> get sites {
    if (configSource.value == 'local') return localSites;
    if (configSource.value == 'file') return fileSites;
    return remoteSites;
  }
  List<Map<String, dynamic>> get parses {
    if (configSource.value == 'local') return localParses;
    if (configSource.value == 'file') return fileParses;
    return remoteParses;
  }

  // ===== 过滤有效爬虫 =====
  bool _shouldKeepSite(Map<String, dynamic> site) {
    final type = site['type']?.toString() ?? '';
    final key = site['key']?.toString() ?? '';
    final api = site['api']?.toString() ?? '';
    final apiWithoutQuery = api.split('?').first;
    if (type == '4') return true;
    if (type != '3') return false;
    if (key.contains('catvod_')) return true;
    if (key.startsWith('nodejs_')) return true;
    if (apiWithoutQuery.endsWith('drpy2.min.js') || apiWithoutQuery.endsWith('drpy2.js')) return true;
    if (api == 'csp_XBPQ') return true;
    if (api == 'csp_XYQHiker') return true;
    if (apiWithoutQuery.endsWith('.py')) return true;
    return false;
  }
  List<Map<String, dynamic>> _filterSites(List<Map<String, dynamic>> sites) {
    return sites.where(_shouldKeepSite).toList();
  }

  // ===== 生命周期 =====
  @override
  void onInit() {
    super.onInit();
    configSource.value = GStorage.getSetting<String>('config_source') ?? 'remote';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadConfig();
    });

    ever(currentSite, (_) {
      if (!_isRestoring) {
        _saveCurrentSiteKey();
      }
    });
  }

  // ===== 选择默认爬虫源（强制重置 currentSite 并刷新首页） =====
  Future<void> _selectDefaultSite() async {
    _isRestoring = true;
    final siteList = this.sites;
    final parseList = this.parses;

    if (siteList.isNotEmpty) {
      Map<String, dynamic>? selectedSite;
      final savedKey = GStorage.getSetting<String>(SettingBoxKey.lastSelectedSiteKey);
      if (savedKey != null && savedKey.isNotEmpty) {
        try {
          selectedSite = siteList.firstWhere((s) => s['key']?.toString() == savedKey);
        } catch (_) {
          selectedSite = null;
          GStorage.deleteSetting('source_switch_scroll_grid');
          GStorage.deleteSetting('source_switch_scroll_list');
        }
      }
      selectedSite ??= siteList.first;

      currentSite.value = selectedSite;
      currentParses.value = List.from(parseList);
      await _switchToSite(currentSite.value!);
      _notifyHomeController();
      _updatePushAgentCache();
      _saveCurrentSiteKey();
    } else {
      currentSite.value = null;
      currentParses.clear();
    }
    _isRestoring = false;
  }

  // ===== 核心：加载当前配置并强制重置爬虫源 =====
  Future<void> loadConfig() async {
    isConfigLoading.value = true;

    // ---- 更新当前接口配置类型 ----
    final customConfigs = GStorage.getCustomSites();
    final savedKey = GStorage.setting.get('selected_config_key');
    Map<String, dynamic>? selectedConfig;
    if (savedKey != null && savedKey.toString().isNotEmpty) {
      selectedConfig = customConfigs.firstWhereOrNull((c) => c['key'] == savedKey);
    }
    selectedConfig ??= customConfigs.isNotEmpty ? customConfigs.first : null;
    currentConfigType.value = selectedConfig?['configType']?.toString() ?? 'tvbox';
    // --------------------------------
    
    try {
      if (PlatformUtils.isDesktop) {
        final customConfigs = GStorage.getCustomSites();
        if (customConfigs.isNotEmpty) {
          final savedKey = GStorage.getSetting<String>('selected_config_key');
          if (savedKey != null && savedKey.isNotEmpty) {
            final targetConfig = customConfigs.firstWhereOrNull(
              (c) => c['key']?.toString() == savedKey
            );
            if (targetConfig != null) {
              final configType = targetConfig['configType']?.toString() ?? 'tvbox';
              if (configType == 'catvod') {
                // 当前选中 CatVod，自动跳转到第一个 TVBox
                final tvboxConfig = customConfigs.firstWhereOrNull(
                  (c) => (c['configType']?.toString() ?? 'tvbox') != 'catvod'
                );
                if (tvboxConfig != null) {
                  final newKey = tvboxConfig['key']?.toString() ?? '';
                  await GStorage.setSetting('selected_config_key', newKey);
                  print('[SourceManager] 桌面端自动跳转到 TVBox 配置: $newKey');
                } else {
                  await GStorage.deleteSetting('selected_config_key');
                  print('[SourceManager] 桌面端无可用 TVBox 配置');
                }
              }
            }
          }
        }
      }

      if (configSource.value == 'local') {
        await _loadLocalConfigBySavedKey();
      } else if (configSource.value == 'file') {
        await _loadFileConfigBySavedKey();
      } else {
        await _loadRemoteConfig();
      }
      await _selectDefaultSite();
      if (!isConfigLoaded.value) {
        isConfigLoaded.value = true;
      }
    } catch (e) {
      print('loadConfig error: $e');
      // 异常时，sites 可能为空，但下面会通过 hasCustomSites 判断
    } finally {
      isConfigLoading.value = false;
    }

    // ---- 判断是否加载失败 ----
    final hasCustomSites = GStorage.getCustomSites().isNotEmpty;
    final isCatVodConfig = currentConfigType.value == 'catvod';
    if (hasCustomSites && this.sites.isEmpty && !isConfigLoading.value) {
      configLoadError.value = isCatVodConfig; // 只有猫影视配置无数据时才报错
    } else {
      configLoadError.value = false;
    }
  }

  // ===== 加载远端配置 =====
  Future<void> _loadRemoteConfig() async {
    final customConfigs = GStorage.getCustomSites();
    if (customConfigs.isEmpty) {
      remoteSites.clear();
      remoteParses.clear();
      return;
    }

    final savedKey = GStorage.setting.get('selected_config_key');
    Map<String, dynamic>? selectedConfig;
    if (savedKey != null && savedKey.toString().isNotEmpty) {
      try {
        selectedConfig = customConfigs.firstWhere((c) => c['key'] == savedKey);
      } catch (_) {
        selectedConfig = null;
      }
    }
    selectedConfig ??= customConfigs.first;

    final configUrl = selectedConfig['api']?.toString();
    if (configUrl == null || configUrl.isEmpty) {
      remoteSites.clear();
      remoteParses.clear();
      return;
    }

    // ===== 先判断 configType，精准分流 =====
    final configType = selectedConfig['configType']?.toString() ?? 'tvbox';
    
    // ===== 桌面端防御 =====
    if (PlatformUtils.isDesktop && configType == 'catvod') {
      print('[SourceManager] 桌面端跳过猫影视配置加载');
      remoteSites.clear();
      remoteParses.clear();
      return;
    }

    if (configType == 'catvod') {
      // 猫影视类型：走 Node.js 流程
      await _loadCatVodConfig(configUrl);
      return;
    }

    try {
      final result = await _apiService.fetchConfig(configUrl: configUrl);
      if (result['sites'] != null && result['sites'] is List) {
        final rawSites = (result['sites'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final filteredSites = _filterSites(rawSites);
        remoteSites.value = filteredSites;
        if (result['logo'] != null) {
          configLogo.value = result['logo'].toString();
        }
      } else {
        remoteSites.clear();
      }
      if (result['parses'] != null && result['parses'] is List) {
        remoteParses.value = (result['parses'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        remoteParses.clear();
      }
      _updatePushAgentCache();
    } catch (e) {
      print('加载远端配置失败: $e');
      remoteSites.clear();
      remoteParses.clear();
    }
  }

  // ===== 加载猫影视配置 =====
  Future<void> _loadCatVodConfig(String configUrl) async {
    try {
      final nodejs = NodeJSService.instance;
      // 直接调用 loadSourceFromURL，它内部会确保服务可用
      final success = await nodejs.loadSourceFromURL(configUrl);
      if (!success) {
        print('[SourceManager] 猫影视源加载失败，保留旧数据');
        return;
      }

      // 等待 spiderPort
      await nodejs.waitForSpiderPort();
      if (nodejs.spiderPort == 0) {
        print('[SourceManager] spiderPort 未就绪');
        return;
      }

      // 获取配置
      final result = await nodejs.getCatConfig();
      final videoSites = result['video']?['sites'] as List<dynamic>? ?? [];
      if (videoSites.isNotEmpty) {
        final rawSites = videoSites.map((e) => Map<String, dynamic>.from(e)).toList();
        final filteredSites = _filterSites(rawSites);
        remoteSites.value = filteredSites;
        if (result['logo'] != null) {
          configLogo.value = result['logo'].toString();
        }
      } else {
        print('[SourceManager] getCatConfig 返回空 sites');
      }

      if (result['parses'] != null && result['parses'] is List) {
        remoteParses.value = (result['parses'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        remoteParses.clear();
      }

      _updatePushAgentCache();
      print('[SourceManager] 猫影视配置加载成功，${remoteSites.length} 个站点');
    } catch (e) {
      print('[SourceManager] 加载猫影视配置异常: $e');
      // 发生异常时也不要清空 remoteSites，保留旧数据供用户重试
    }
  }

  // ===== 加载本地缓存配置 =====
  Future<void> _loadLocalConfigPackage(String configKey) async {
    final package = GStorage.getConfigPackage(configKey);
    if (package == null) {
      print('配置包不存在: $configKey');
      localSites.clear();
      localParses.clear();
      return;
    }

    final rawSites = package['sites'] as List? ?? [];
    final rawParses = package['parses'] as List? ?? [];

    final allSites = rawSites.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final filteredSites = _filterSites(allSites);

    if (filteredSites.isEmpty) {
      localSites.clear();
      localParses.clear();
      return;
    }

    for (var site in filteredSites) {
      site['_configKey'] = configKey;
      site['_source'] = 'local';
    }

    localSites.value = filteredSites;
    localParses.value = rawParses.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    _updatePushAgentCache();
  }

  Future<void> _loadLocalConfigBySavedKey() async {
    final customConfigs = GStorage.getCustomSites();
    final savedKey = GStorage.setting.get('selected_config_key');
    Map<String, dynamic>? targetConfig;
    if (savedKey != null && savedKey.toString().isNotEmpty) {
      targetConfig = customConfigs.firstWhereOrNull(
        (c) => c['key'] == savedKey && c['_source']?.toString() == 'local',
      );
    }
    targetConfig ??= customConfigs.firstWhereOrNull(
      (c) => c['_source']?.toString() == 'local',
    );
    if (targetConfig != null) {
      final packageKey = targetConfig['_configKey']?.toString();
      if (packageKey != null && packageKey.isNotEmpty) {
        await _loadLocalConfigPackage(packageKey);
        return;
      }
    }
    localSites.clear();
    localParses.clear();
  }

  // ===== 加载本地文件配置 =====
  Future<void> _loadFileConfig(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('文件不存在: $filePath');
        fileSites.clear();
        fileParses.clear();
        return;
      }
      final content = await file.readAsString();
      final jsonData = jsonDecode(content) as Map<String, dynamic>;
      if (jsonData['sites'] == null || jsonData['sites'] is! List) {
        print('配置文件缺少 sites 字段');
        fileSites.clear();
        fileParses.clear();
        return;
      }
      final rawSites = (jsonData['sites'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final filteredSites = _filterSites(rawSites);
      if (filteredSites.isEmpty) {
        fileSites.clear();
        fileParses.clear();
        return;
      }
      for (var site in filteredSites) {
        site['_source'] = 'local_file';
      }
      fileSites.value = filteredSites;
      fileParses.value = (jsonData['parses'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e))
          .toList() ?? [];
      _updatePushAgentCache();
    } catch (e) {
      print('加载本地文件配置失败: $e');
      fileSites.clear();
      fileParses.clear();
    }
  }

  Future<void> _loadFileConfigBySavedKey() async {
    final customConfigs = GStorage.getCustomSites();
    final savedKey = GStorage.setting.get('selected_config_key');
    Map<String, dynamic>? targetConfig;
    if (savedKey != null && savedKey.toString().isNotEmpty) {
      targetConfig = customConfigs.firstWhereOrNull(
        (c) => c['key'] == savedKey && c['_source']?.toString() == 'local_file',
      );
    }
    targetConfig ??= customConfigs.firstWhereOrNull(
      (c) => c['_source']?.toString() == 'local_file',
    );
    if (targetConfig != null) {
      final filePath = targetConfig['api']?.toString();
      if (filePath != null && filePath.isNotEmpty) {
        await _loadFileConfig(filePath);
        return;
      }
    }
    fileSites.clear();
    fileParses.clear();
  }

  // ===== 对外接口：切换配置源类型 =====
  Future<void> switchConfigSource(String source) async {
    if (configSource.value == source) return;
    configSource.value = source;
    GStorage.setSetting('config_source', source);
    await loadConfig();
  }

  // ===== 对外接口：切换远端配置（指定 key） =====
  Future<void> switchConfig(String configKey) async {
    final customConfigs = GStorage.getCustomSites();
    final targetConfig = customConfigs.firstWhereOrNull((c) => c['key'] == configKey);
    if (targetConfig == null) return;

    // ===== 桌面端拦截 =====
    final configType = targetConfig['configType']?.toString() ?? 'tvbox';
    if (PlatformUtils.isDesktop && configType == 'catvod') {
      print('[SourceManager] 桌面端不支持猫影视配置');
      SmartDialog.showToast('猫影视配置仅支持移动端');
      return;
    }

    final exists = customConfigs.any((c) => c['key'] == configKey);
    if (!exists) return;
    await GStorage.setSetting('selected_config_key', configKey);
    configSource.value = 'remote';
    GStorage.setSetting('config_source', 'remote');
    await loadConfig();
  }

  // ===== 对外接口：应用本地缓存配置包 =====
  Future<void> applyLocalConfigPackage({
    required List<Map<String, dynamic>> sites,
    required List<Map<String, dynamic>> parses,
    required String siteKey,    // 接口配置的 key
    required String packageKey, // 配置包 key
  }) async {
    // 保存配置包
    GStorage.saveConfigPackage(packageKey, {
      'sites': sites,
      'parses': parses,
    });
    // 设置当前选中的配置 key 为 siteKey
    await GStorage.setSetting('selected_config_key', siteKey);
    configSource.value = 'local';
    GStorage.setSetting('config_source', 'local');
    await loadConfig();
  }

  // ===== 对外接口：加载本地文件配置 =====
  Future<void> loadFileConfig(String filePath, {String? siteKey}) async {
    final key = siteKey ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
    await GStorage.setSetting('selected_config_key', key);
    configSource.value = 'file';
    GStorage.setSetting('config_source', 'file');
    await loadConfig();
  }

  // ===== 切换爬虫源 =====
  Future<void> switchSite(Map<String, dynamic> site) async {
    // 卸载旧的 py3 爬虫（如果存在且不同）
    final oldSite = currentSite.value;
    if (oldSite != null && SourceManager.isPurePy3Site(oldSite)) {
      final oldKey = oldSite['key']?.toString() ?? '';
      final newKey = site['key']?.toString() ?? '';
      if (oldKey.isNotEmpty && oldKey != newKey) {
        if (Get.isRegistered<Py3SpiderService>(tag: oldKey)) {
          final oldService = Get.find<Py3SpiderService>(tag: oldKey);
          await oldService.unload();
        }
      }
    }

    final siteKey = site['key']?.toString();
    if (siteKey == null || siteKey.isEmpty) {
      print('[SourceManager] switchSite: site key is empty');
      return;
    }

    // 根据当前 configSource 获取对应的爬虫源列表
    final sourceList = this.sites;
    final parseList = this.parses;

    Map<String, dynamic>? target = sourceList.firstWhereOrNull((s) => s['key']?.toString() == siteKey);
    if (target == null) {
      // 如果找不到，回退到第一个
      target = sourceList.isNotEmpty ? sourceList.first : null;
    }

    if (target == null) {
      currentSite.value = null;
      currentParses.clear();
      return;
    }

    currentSite.value = target;
    currentParses.value = List.from(parseList);
    await _switchToSite(target);
    _notifyHomeController();
    _updatePushAgentCache();
    _saveCurrentSiteKey();
  }

  Future<void> refreshSites() async {
    await _loadRemoteConfig();
  }

  List<Map<String, dynamic>> getAvailableConfigs() {
    final result = <Map<String, dynamic>>[];
    if (remoteSites.isNotEmpty) {
      result.add({
        'key': 'remote',
        'name': '远端配置',
        '_source': 'remote',
        '_displayName': '远端配置',
      });
    }
    final customConfigs = GStorage.getCustomSites();
    for (final config in customConfigs) {
      if (config['_source']?.toString() == 'local') {
        result.add(config);
      }
    }
    return result;
  }

  Map<String, dynamic>? getCurrentSite() => currentSite.value;
  List<Map<String, dynamic>> getCurrentParses() => List.from(currentParses);

  void switchSiteByKey(String siteKey) {
    if (siteKey.isEmpty) return;
    Map<String, dynamic>? target;
    try {
      target = remoteSites.firstWhere((site) => site['key']?.toString() == siteKey);
    } catch (_) {}
    if (target == null) {
      try {
        target = localSites.firstWhere((site) => site['key']?.toString() == siteKey);
      } catch (_) {}
    }
    if (target == null) {
      try {
        target = fileSites.firstWhere((site) => site['key']?.toString() == siteKey);
      } catch (_) {}
    }
    if (target != null) {
      switchSite(target);
    } else {
      print('站点不存在: $siteKey');
    }
  }

  // ===== 实际切换爬虫服务 =====
  Future<void> _switchToSite(Map<String, dynamic> site) async {
    print('_switchToSite received: key=${site['key']}, api=${site['api']}');
    if (isDrpy2Site(site)) {
      await _switchToDrpy2Site(site);
    } else if (isXbpqSite(site)) {
      await _switchToXbpqSite(site);
    } else if (isXyqSite(site)) {
      await _switchToXyqSite(site);
    } else if (isCatVodOpenSite(site)) {
      await _switchToCatVodOpenSite(site);
    } else if (isPurePy3Site(site)) {
      await _switchToPy3Site(site);
    } else if (isNodeJSSite(site)) {
      await _switchToNodeJSSite(site);
    } else {
      _switchToT4Site(site);
    }
  }

  Future<void> _switchToDrpy2Site(Map<String, dynamic> site) async {
    final ok = await _drpy2Service.ensureInitialized();
    if (!ok) {
      print('[SourceManager] drpy2 init failed, cannot switch to drpy2 site');
      return;
    }
    _drpy2Service.switchSite(
      site['api']?.toString() ?? '',
      site['key']?.toString() ?? '',
      ext: site['ext'],
    );
  }

  XbpqService _getOrCreateXbpqService(Map<String, dynamic> site) {
    final key = site['key']?.toString() ?? 'xbpq_default';
    if (!Get.isRegistered<XbpqService>(tag: key)) {
      final extUrl = site['ext']?.toString() ?? '';
      final categories = <String>[];
      final service = XbpqService(key, site['api']?.toString() ?? '', extUrl, categories);
      Get.put(service, tag: key, permanent: true);
    }
    return Get.find<XbpqService>(tag: key);
  }

  Future<void> _switchToXbpqSite(Map<String, dynamic> site) async {
    final service = _getOrCreateXbpqService(site);
    await service.init();
    service.switchSite(
      site['api']?.toString() ?? '',
      site['key']?.toString() ?? '',
      ext: site['ext'],
    );
  }

  XyqService _getOrCreateXyqService(Map<String, dynamic> site) {
    final key = site['key']?.toString() ?? 'xyq_default';
    if (!Get.isRegistered<XyqService>(tag: key)) {
      final extUrl = site['ext']?.toString() ?? '';
      final service = XyqService(key, site['api']?.toString() ?? '', extUrl, []);
      Get.put(service, tag: key, permanent: true);
    }
    return Get.find<XyqService>(tag: key);
  }

  Future<void> _switchToXyqSite(Map<String, dynamic> site) async {
    final service = _getOrCreateXyqService(site);
    await service.init();
    service.switchSite(
      site['api']?.toString() ?? '',
      site['key']?.toString() ?? '',
      ext: site['ext'],
    );
  }

  CatvodOpenService _getOrCreateCatvodOpenService(Map<String, dynamic> site) {
    return Get.find<CatvodOpenService>();
  }

  Future<void> _switchToCatVodOpenSite(Map<String, dynamic> site) async {
    print('_switchToCatVodOpenSite: start for ${site['key']}');
    try {
      final service = _getOrCreateCatvodOpenService(site);
      print('Service obtained, calling switchSite...');
      await service.switchSite(
        site['api']?.toString() ?? '',
        site['key']?.toString() ?? '',
        ext: site['ext'],
      );
      print('_switchToCatVodOpenSite: ready');
    } catch (e, stack) {
      print('_switchToCatVodOpenSite error: $e\n$stack');
      rethrow;
    }
  }

  Py3SpiderService _getOrCreatePy3Service(Map<String, dynamic> site) {
    final key = site['key']?.toString() ?? 'py3_default';
    if (!Get.isRegistered<Py3SpiderService>(tag: key)) {
      final service = Py3SpiderService(key);
      Get.put(service, tag: key, permanent: true);
    }
    return Get.find<Py3SpiderService>(tag: key);
  }

  Future<void> _switchToPy3Site(Map<String, dynamic> site) async {
    final service = _getOrCreatePy3Service(site);
    await service.switchSite(
      site['api']?.toString() ?? '',
      site['key']?.toString() ?? '',
      ext: site['ext'],
    );
  }

  // ===== 切换到猫影视 Node.js 源 =====
  NodeJSSpiderService _getNodeJSService() {
    if (!Get.isRegistered<NodeJSSpiderService>()) {
      Get.put(NodeJSSpiderService(), permanent: true);
    }
    return Get.find<NodeJSSpiderService>();
  }

  Future<void> _switchToNodeJSSite(Map<String, dynamic> site) async {
    final service = _getNodeJSService();
    service.switchSite(
      site['api']?.toString() ?? '',
      site['key']?.toString() ?? '',
      ext: site['ext'],
    );
    await service.initSpider();
  }

  void _switchToT4Site(Map<String, dynamic> site) {
    _apiService.switchSite(
      site['api']?.toString() ?? '',
      site['key']?.toString() ?? '',
      ext: site['ext'],
    );
  }

  void _notifyHomeController() {
    if (Get.isRegistered<HomeController>()) {
      Get.find<HomeController>().onSiteChanged();
    }
  }

  void _updatePushAgentCache() {
    for (final site in this.sites) {
      final key = site['key']?.toString() ?? '';
      final type = site['type'] as int? ?? -1;
      if (key == 'push_agent' && type == 4) {
        _pushAgentSite.value = site;
        return;
      }
    }
    _pushAgentSite.value = null;
  }
}