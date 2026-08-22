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

  final RxList<Map<String, dynamic>> remoteSites = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> remoteParses = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> localSites = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> localParses = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> fileSites = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> fileParses = <Map<String, dynamic>>[].obs;

  final Rx<Map<String, dynamic>?> currentSite = Rx<Map<String, dynamic>?>(null);
  final RxList<Map<String, dynamic>> currentParses = <Map<String, dynamic>>[].obs;
  final RxString configLogo = ''.obs;
  final RxBool isConfigLoaded = false.obs;
  final RxString configSource = 'remote'.obs;
  final RxBool isConfigLoading = false.obs;
  final RxBool configLoadError = false.obs;
  final RxString currentConfigType = 'tvbox'.obs;

  bool _isRestoring = false;
  int _configLoadId = 0; // 防止异步竞态

  void _saveCurrentSiteKey() {
    final site = currentSite.value;
    if (site != null) {
      final key = site['key']?.toString();
      if (key != null && key.isNotEmpty) {
        GStorage.setSetting(SettingBoxKey.lastSelectedSiteKey, key);
      }
    }
  }

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

  final Rx<Map<String, dynamic>?> _pushAgentSite = Rx<Map<String, dynamic>?>(null);
  Map<String, dynamic>? get pushAgentSite => _pushAgentSite.value;

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

  Future<void> loadConfig() async {
    isConfigLoading.value = true;
    ++_configLoadId;
    final currentLoadId = _configLoadId;
    final customConfigs = GStorage.getCustomSites();
    final savedKey = GStorage.setting.get('selected_config_key');
    Map<String, dynamic>? selectedConfig;
    if (savedKey != null && savedKey.toString().isNotEmpty) {
      selectedConfig = customConfigs.firstWhereOrNull((c) => c['key'] == savedKey);
    }
    selectedConfig ??= customConfigs.isNotEmpty ? customConfigs.first : null;
    currentConfigType.value = selectedConfig?['configType']?.toString() ?? 'tvbox';
    NodeJSService.instance.updateConfigType(currentConfigType.value);

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
        await _loadRemoteConfig(loadId: currentLoadId);
      }
      await _selectDefaultSite();
      if (!isConfigLoaded.value) {
        isConfigLoaded.value = true;
      }
    } catch (e) {
      print('loadConfig error: $e');
    } finally {
      isConfigLoading.value = false;
    }

    final hasCustomSites = GStorage.getCustomSites().isNotEmpty;
    if (hasCustomSites && this.sites.isEmpty) {
      configLoadError.value = true;
    } else {
      configLoadError.value = false;
    }
  }

  Future<void> _loadRemoteConfig({int? loadId}) async {
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

    final configType = selectedConfig['configType']?.toString() ?? 'tvbox';
    if (PlatformUtils.isDesktop && configType == 'catvod') {
      print('[SourceManager] 桌面端跳过猫影视配置加载');
      remoteSites.clear();
      remoteParses.clear();
      return;
    }
    if (configType == 'catvod') {
      await _loadCatVodConfig(configUrl, loadId: loadId);
      return;
    }
    try {
      final result = await _apiService.fetchConfig(configUrl: configUrl);
      // 检查是否被更新的请求覆盖了
      if (loadId != null && loadId != _configLoadId) return;
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
        if (loadId == null || loadId == _configLoadId) remoteSites.clear();
      }
      if (result['parses'] != null && result['parses'] is List) {
        if (loadId == null || loadId == _configLoadId) {
          remoteParses.value = (result['parses'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } else {
        if (loadId == null || loadId == _configLoadId) remoteParses.clear();
      }
      if (loadId == null || loadId == _configLoadId) _updatePushAgentCache();
    } catch (e) {
      print('加载远端配置失败: $e');
      if (loadId == null || loadId == _configLoadId) {
        remoteSites.clear();
        remoteParses.clear();
      }
    }
  }

  Future<void> _loadCatVodConfig(String configUrl, {int? loadId}) async {
    final currentLoadId = loadId ?? ++_configLoadId;
    try {
      final nodejs = NodeJSService.instance;
      
      // 确保 Node.js 初始化
      if (!nodejs.isInitialized || nodejs.managementPort == 0) {
        await nodejs.initialize();  // 这会调用原生 startNodeJS
      }
      
      if (currentLoadId != _configLoadId) return;
      
      // 加载源
      final success = await nodejs.loadSourceFromURL(configUrl);
      if (!success) {
        if (currentLoadId == _configLoadId) {
          remoteSites.clear();
          remoteParses.clear();
        }
        return;
      }
      if (currentLoadId != _configLoadId) return;

      await nodejs.waitForSpiderPort();
      if (nodejs.spiderPort == 0) {
        print('[SourceManager] spiderPort 未就绪，无法获取配置');
        if (currentLoadId == _configLoadId) {
          remoteSites.clear();
        }
        return;
      }
      if (currentLoadId != _configLoadId) return;

      final result = await nodejs.getCatConfig();
      if (currentLoadId != _configLoadId) return;

      final videoSites = result['video']?['sites'] as List<dynamic>? ?? [];
      if (videoSites.isNotEmpty) {
        final rawSites = videoSites.map((e) => Map<String, dynamic>.from(e)).toList();
        final filteredSites = _filterSites(rawSites);
        if (currentLoadId == _configLoadId) {
          remoteSites.value = filteredSites;
          if (result['logo'] != null) {
            configLogo.value = result['logo'].toString();
          }
        }
      } else {
        if (currentLoadId == _configLoadId) remoteSites.clear();
      }

      if (result['parses'] != null && result['parses'] is List) {
        if (currentLoadId == _configLoadId) {
          remoteParses.value = (result['parses'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } else {
        if (currentLoadId == _configLoadId) remoteParses.clear();
      }
      if (currentLoadId == _configLoadId) _updatePushAgentCache();
      if (currentLoadId == _configLoadId) {
        print('[SourceManager] 猫影视配置加载成功，${remoteSites.length} 个站点');
      }
    } catch (e) {
      print('[SourceManager] 加载猫影视配置失败: $e');
      if (currentLoadId == _configLoadId) {
        remoteSites.clear();
        remoteParses.clear();
      }
    }
  }

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

  Future<void> switchConfigSource(String source) async {
    if (configSource.value == source) return;
    configSource.value = source;
    GStorage.setSetting('config_source', source);
    await loadConfig();
  }

  Future<void> switchConfig(String configKey) async {
    final customConfigs = GStorage.getCustomSites();
    final targetConfig = customConfigs.firstWhereOrNull((c) => c['key'] == configKey);
    if (targetConfig == null) return;
    
    final configType = targetConfig['configType']?.toString() ?? 'tvbox';
    if (PlatformUtils.isDesktop && configType == 'catvod') {
      SmartDialog.showToast('猫影视配置仅支持移动端');
      return;
    }
    
    // 切换到非猫影视时，只清 Dart 层状态，不调用原生 stopNodeJS
    if (configType != 'catvod') {
      final nodejs = NodeJSService.instance;
      await nodejs.stop(); // ★ 调用公共方法，安全清理所有 Dart 层状态
    }
    
    await GStorage.setSetting('selected_config_key', configKey);
    configSource.value = 'remote';
    GStorage.setSetting('config_source', 'remote');
    await loadConfig();
  }

  Future<void> applyLocalConfigPackage({
    required List<Map<String, dynamic>> sites,
    required List<Map<String, dynamic>> parses,
    required String siteKey,
    required String packageKey,
  }) async {
    GStorage.saveConfigPackage(packageKey, {
      'sites': sites,
      'parses': parses,
    });
    await GStorage.setSetting('selected_config_key', siteKey);
    configSource.value = 'local';
    GStorage.setSetting('config_source', 'local');
    await loadConfig();
  }

  Future<void> loadFileConfig(String filePath, {String? siteKey}) async {
    final key = siteKey ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
    await GStorage.setSetting('selected_config_key', key);
    configSource.value = 'file';
    GStorage.setSetting('config_source', 'file');
    await loadConfig();
  }

  Future<void> switchSite(Map<String, dynamic> site) async {
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
    final sourceList = this.sites;
    final parseList = this.parses;
    Map<String, dynamic>? target = sourceList.firstWhereOrNull((s) => s['key']?.toString() == siteKey);
    if (target == null) {
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