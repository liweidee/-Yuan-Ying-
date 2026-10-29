import 'dart:io';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yuanying/t4/models/site.dart';
import 'package:yuanying/t4/services/t4_api_service.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:collection/collection.dart';
import 'package:yuanying/t4/services/drpy2_api_service.dart';
import 'package:yuanying/t4/services/qjs_drpy2_service.dart';
import 'package:yuanying/t4/services/drpy3_api_service.dart';
import 'package:yuanying/t4/services/qjs_drpy3_service.dart';
import 'package:yuanying/utils/qjs_platform_helper.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/t4/services/xbpq_service.dart';
import 'package:yuanying/t4/services/xyq_service.dart';
import 'package:yuanying/t4/services/catvod_open_service.dart';
import 'package:yuanying/t4/services/py3_spider_service.dart';
import 'package:yuanying/t4/services/app_cms_service.dart';
import 'package:yuanying/t4/services/app_ysv2_service.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/t4/services/nodejs_spider_service.dart';
import 'package:yuanying/nodejs/nodejs_service.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/constants/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:yuanying/services/catvod_log_service.dart';
import 'package:yuanying/modules/manual_source/controllers/manual_source_controller.dart';
import 'site_switch_result.dart';
import 'package:yuanying/utils/error_formatter.dart';
import 'package:yuanying/utils/business_exception.dart';

class SourceManager extends GetxController {
  final T4ApiService _apiService = Get.find<T4ApiService>();
  // final Drpy2ApiService _drpy2Service = Get.find<Drpy2ApiService>();
  // final Drpy3ApiService _drpy3Service = Get.find<Drpy3ApiService>();

  final Drpy2ApiService _drpy2Legacy = Get.find<Drpy2ApiService>();
  final QjsDrpy2Service _qjsDrpy2 = Get.find<QjsDrpy2Service>();

  ISpiderService get _drpy2Service =>
      QjsPlatformHelper.isSupported ? _qjsDrpy2 : _drpy2Legacy;

  Future<bool> _ensureDrpy2Ready() async {
    if (QjsPlatformHelper.isSupported) return _qjsDrpy2.ensureInitialized();
    return _drpy2Legacy.ensureInitialized();
  }

  final Drpy3ApiService _drpy3Legacy = Get.find<Drpy3ApiService>();
  final QjsDrpy3Service _qjsDrpy3 = Get.find<QjsDrpy3Service>();

  ISpiderService get _drpy3Service =>
      QjsPlatformHelper.isSupported ? _qjsDrpy3 : _drpy3Legacy;

  /// 按平台分发 ensureInitialized 调用
  Future<bool> _ensureDrpy3Ready() async {
    if (QjsPlatformHelper.isSupported) {
      return _qjsDrpy3.ensureInitialized();
    }
    return _drpy3Legacy.ensureInitialized();
  }

  final RxList<Map<String, dynamic>> remoteSites = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> remoteParses = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> localSites = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> localParses = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> fileSites = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> fileParses = <Map<String, dynamic>>[].obs;

  /// 手动源列表（来自 ManualSourceController，configSource == 'manual' 时生效）
  final RxList<Map<String, dynamic>> manualSites = <Map<String, dynamic>>[].obs;

  final Rx<Map<String, dynamic>?> currentSite = Rx<Map<String, dynamic>?>(null);
  final RxList<Map<String, dynamic>> currentParses = <Map<String, dynamic>>[].obs;
  final RxString configLogo = ''.obs;
  final RxBool isConfigLoaded = false.obs;
  final RxString configSource = 'remote'.obs;
  final RxBool isConfigLoading = false.obs;
  final RxBool configLoadError = false.obs;
  /// 配置加载失败的具体原因（仅业务异常时有值，例如插件未安装/已关闭）
  /// 首页列表区域可读取展示；为空时使用默认占位文案。
  final RxString configLoadErrorMessage = ''.obs;

  /// 手动源为空（configSource == 'manual' 但手动源列表无任何文件）
  ///
  /// 用于首页给出准确提示（"手动源为空，请前往手动源管理上传"），
  /// 避免用户误以为是网络或接口配置问题。
  final RxBool isManualConfigEmpty = false.obs;

  final RxString currentConfigType = 'tvbox'.obs;
  final RxString currentConfigKey = ''.obs;

  bool _isRestoring = false;
  int _configLoadId = 0; // 防止异步竞态

  late CatVodLogService _logService;

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

  /// 判断是否为 drpy3 站点
  ///
  /// 判定条件（任一命中即可）：
  ///   1. `lang` 字段为 `dr3` / `drpy3`（官方设计标识，最权威）
  ///   2. `api` 文件名以 `drpy3.min.js` / `drpy3.js` 结尾
  ///   3. `key` 以 `drpy3_` 开头（兜底）
  static bool isDrpy3Site(Map<String, dynamic> site) {
    // 条件 1：lang 字段（最权威）
    final lang = site['lang']?.toString().toLowerCase() ?? '';
    if (lang == 'dr3' || lang == 'drpy3') return true;

    // 条件 2：api 文件名
    final type = site['type']?.toString() ?? '';
    final api = site['api']?.toString() ?? '';
    final apiWithoutQuery = api.split('?')[0].toLowerCase();
    if (type == '3' &&
        (apiWithoutQuery.endsWith('drpy3.min.js') ||
            apiWithoutQuery.endsWith('drpy3.js'))) {
      return true;
    }

    // 条件 3：key 前缀兜底
    final key = site['key']?.toString() ?? '';
    if (key.startsWith('drpy3_')) return true;

    return false;
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

  static bool isAppCmsSite(Map<String, dynamic> site) {
    final api = site['api']?.toString() ?? '';
    return api == 'csp_AppCMS';
  }

  static bool isAppV2Site(Map<String, dynamic> site) {
    final api = site['api']?.toString() ?? '';
    return api == 'csp_APPV2';
  }

  static bool isAppYsV2Site(Map<String, dynamic> site) {
    final api = site['api']?.toString() ?? '';
    return api == 'csp_AppYsV2';
  }

  /// 该源是否支持"合并当前分类列表为播放列表"
  static bool isMergeListSite(Map<String, dynamic>? site) {
    if (site == null) return false;
    final top = site['mergeList'];
    if (top == 1 || top == true || top == '1') return true;
    final more = site['more'];
    if (more is Map) {
      final inner = more['mergeList'];
      if (inner == 1 || inner == true || inner == '1') return true;
    }
    return false;
  }

  /// 根据站点配置判断详情类型（video / novel / manga）
  static String getDetailTypeFromSite(Map<String, dynamic>? site) {
    if (site == null) return DetailType.video;
    final key = site['key']?.toString() ?? '';
    final name = site['name']?.toString() ?? '';
    if (key.contains('[书]') || name.contains('[书]')) return DetailType.novel;
    if (key.contains('[画]') || name.contains('[画]')) return DetailType.manga;
    if (key.contains('[听]') || name.contains('[听]')) return DetailType.audio;
    return DetailType.video;
  }

  ISpiderService get currentApiService {
    final site = currentSite.value;
    if (site == null) return _apiService;
    if (isXbpqSite(site)) return _getOrCreateXbpqService(site);
    if (isXyqSite(site)) return _getOrCreateXyqService(site);
    if (isCatVodOpenSite(site)) return _getOrCreateCatvodOpenService(site);
    if (isPurePy3Site(site)) return _getOrCreatePy3Service(site);
    if (isDrpy3Site(site)) return _drpy3Service;
    if (isDrpy2Site(site)) return _drpy2Service;
    if (isNodeJSSite(site)) return _getNodeJSService();
    if (isAppCmsSite(site)) return _getOrCreateAppCmsService(site);
    if (isAppYsV2Site(site)) return _getOrCreateAppYsV2Service(site);
    if (isAppV2Site(site)) return _getOrCreateAppYsV2Service(site); // 兼容 csp_APPV2
    return _apiService;
  }

  ISpiderService createIndependentService(Map<String, dynamic> site) {
    final key = site['key']?.toString() ?? '';
    final api = site['api']?.toString() ?? '';
    final ext = site['ext'];
    if (!isDrpy3Site(site) &&
        !isDrpy2Site(site) &&
        !isXbpqSite(site) &&
        !isCatVodOpenSite(site) &&
        !isPurePy3Site(site) &&
        !isXyqSite(site) &&
        !isNodeJSSite(site)) {
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
    if (isDrpy3Site(site)) return _drpy3Service;
    if (isDrpy2Site(site)) return _drpy2Service;
    if (isCatVodOpenSite(site)) return Get.find<CatvodOpenService>();
    if (isNodeJSSite(site)) return _getNodeJSService();
    if (isAppCmsSite(site)) {
      final tag = 'appcms_$key';
      if (!Get.isRegistered<AppCmsService>(tag: tag)) {
        final service = AppCmsService(key, ext?.toString() ?? '');
        Get.put(service, tag: tag, permanent: true);
      }
      return Get.find<AppCmsService>(tag: tag);
    }
    if (isAppYsV2Site(site) || isAppV2Site(site)) {
      final tag = 'appysv2_$key';
      if (!Get.isRegistered<AppYsV2Service>(tag: tag)) {
        final service = AppYsV2Service(key, ext?.toString() ?? '');
        Get.put(service, tag: tag, permanent: true);
      }
      return Get.find<AppYsV2Service>(tag: tag);
    }
    return currentApiService;
  }

  final Rx<Map<String, dynamic>?> _pushAgentSite = Rx<Map<String, dynamic>?>(null);
  Map<String, dynamic>? get pushAgentSite => _pushAgentSite.value;

  /// 当前生效的源列表
  /// - configSource == 'manual' → 手动源
  /// - configSource == 'local' → 本地缓存
  /// - configSource == 'file' → 本地文件
  /// - 其他 → 远端
  List<Map<String, dynamic>> get sites {
    if (configSource.value == 'manual') {
      return manualSites;
    }
    if (configSource.value == 'local') return localSites;
    if (configSource.value == 'file') return fileSites;
    return remoteSites;
  }

  List<Map<String, dynamic>> get parses {
    if (configSource.value == 'manual') return const [];
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
    if (isDrpy3Site(site)) return true;
    if (apiWithoutQuery.endsWith('drpy2.min.js') || apiWithoutQuery.endsWith('drpy2.js')) return true;
    if (api == 'csp_XBPQ') return true;
    if (api == 'csp_XYQHiker') return true;
    if (api == 'csp_AppCMS') return true;
    if (api == 'csp_APPV2') return true;
    if (api == 'csp_AppYsV2') return true;
    if (apiWithoutQuery.endsWith('.py')) return true;
    if (key.startsWith('manual_')) return true;
    return false;
  }

  List<Map<String, dynamic>> _filterSites(List<Map<String, dynamic>> sites) {
    return sites.where(_shouldKeepSite).toList();
  }

  @override
  void onInit() {
    super.onInit();
    _logService = Get.find<CatVodLogService>();

    // ===== 预创建手动源配置记录 =====
    //
    // 背景：`manual_source` 原本只在 SiteConfigPage 打开时由
    // SiteConfigController 懒创建，导致首次启动时：
    //   - 首页左上角"切换接口"弹窗读 getCustomSites() 为空 → 弹窗空白
    //   - 用户必须先进一次设置页，记录才会出现
    //
    // 在 SourceManager 初始化时预创建，保证所有下游读取点（首页弹窗、
    // SiteConfigPage 列表、弹窗里的手动源跳转）第一次访问就能看到记录。
    // SiteConfigController._ensureManualConfigExists 保留幂等兜底，
    // 处理极端场景（如用户手动清空了 Hive）。
    _ensureManualConfigExists();

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

  /// 确保手动源配置记录存在（幂等）
  ///
  /// 与 SiteConfigController._ensureManualConfigExists 逻辑一致，
  /// 但调用时机更早（App 启动时），覆盖首页弹窗等早期入口。
  ///
  /// 记录结构（与 SiteConfigController 里创建的一致）：
  ///   key        = SettingBoxKey.manualConfigKey ('manual_source')
  ///   name       = '手动源'
  ///   api        = 'manual'
  ///   _source    = 'manual'
  ///   configType = 'tvbox'
  void _ensureManualConfigExists() {
    try {
      final list = GStorage.getCustomSites();
      final has = list.any(
        (s) => s['key']?.toString() == SettingBoxKey.manualConfigKey,
      );
      if (has) return;

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
      _log('[SourceManager] 已预创建手动源配置记录');
    } catch (e) {
      // 失败不阻断启动（极端情况下 GStorage 未就绪）
      debugPrint('[SourceManager] _ensureManualConfigExists failed: $e');
    }
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

      // 有站点可用 → 清除配置错误状态
      //
      // 场景：
      //   - 用户从"手动源为空"状态上传源后，reloadManualSites 调用本方法
      //   - 任何配置加载成功后的正常路径
      // 有站点即说明加载成功，`configLoadError` 理应回到 false，
      // 避免首页残留"配置加载失败 / 手动源为空"的错误占位。
      configLoadError.value = false;
      isManualConfigEmpty.value = false;
      configLoadErrorMessage.value = '';

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
    currentConfigKey.value = selectedConfig?['key']?.toString() ?? '';
    NodeJSService.instance.updateConfigType(currentConfigType.value);

    // 每次重新加载配置时先清空旧的业务错误，
    // 让"重试"和"切换配置"都能自然清除上一次的插件错误提示。
    configLoadErrorMessage.value = '';
    isManualConfigEmpty.value = false;

    try {
      // ===== 手动源配置分支 =====
      if (configSource.value == 'manual') {
        await _refreshManualSites();
        if (currentLoadId != _configLoadId) return;
        await _selectDefaultSite();
        if (!isConfigLoaded.value) isConfigLoaded.value = true;

        // 手动源为空：给出准确提示，避免用户误以为是"接口配置"问题
        //
        // 说明：manual 分支末尾有 return，会绕过下方统一的
        //      "hasCustomSites && sites.isEmpty" 判定，因此这里需要
        //      单独处理。仅当 manualSites 完全为空时才认为"手动源为空"，
        //      有源但 currentSite 为空属于其他异常，交给 _selectDefaultSite
        //      的既有逻辑（不会触发）。
        if (manualSites.isEmpty) {
          configLoadError.value = true;
          isManualConfigEmpty.value = true;
          configLoadErrorMessage.value =
              '手动源为空，请前往「手动源管理」上传 py / dr2 / dr3 / js 等源文件';
        }
        return;
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
      // 非"手动源为空"的失败路径（如 remote 配置加载失败但 hasCustomSites 为 false）
      // 确保该标记被重置，避免首页走"前往手动源管理"的错误分支
      isManualConfigEmpty.value = false;
    }
  }

  // ================================================================
  // 手动源
  // ================================================================

  /// 拉取手动源（不主动触发 controller.refresh，若全空则补扫一次）
  Future<void> _refreshManualSites() async {
    try {
      if (!Get.isRegistered<ManualSourceController>()) {
        manualSites.clear();
        return;
      }
      final ctrl = Get.find<ManualSourceController>();
      if (ctrl.all.isEmpty) {
        await ctrl.refresh();
      }
      manualSites.assignAll(ctrl.buildSites());
    } catch (e) {
      print('[SourceManager] refreshManualSites failed: $e');
    }
  }

  /// 手动源页操作完后调用：重新扫描 + 若当前是手动源配置则刷新站点列表
  Future<void> reloadManualSites() async {
    if (Get.isRegistered<ManualSourceController>()) {
      await Get.find<ManualSourceController>().refresh();
    }
    await _refreshManualSites();
    if (configSource.value == 'manual') {
      await _selectDefaultSite();
    }
  }

  /// 切换到手动源配置
  Future<void> switchToManualConfig() async {
    configSource.value = 'manual';
    GStorage.setSetting('config_source', 'manual');
    await loadConfig();
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
    // if (PlatformUtils.isDesktop && configType == 'catvod') {
    //   print('[SourceManager] 桌面端跳过猫影视配置加载');
    //   remoteSites.clear();
    //   remoteParses.clear();
    //   return;
    // }
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

  /// 导入 CatVod 本地 ZIP 配置（仅存储路径，不复制文件）
  Future<void> importCatvodZip(String name, String zipFilePath) async {
    // 1. 检查文件是否存在
    final zipFile = File(zipFilePath);
    if (!await zipFile.exists()) {
      throw Exception('ZIP 文件不存在: $zipFilePath');
    }

    // 2. 生成唯一配置 Key
    final key = 'catvod_${DateTime.now().millisecondsSinceEpoch}';

    // 3. 创建 Site 配置（直接存储原始路径）
    final newSite = Site(
      key: key,
      name: name,
      api: 'local_zip',
      searchable: 1,
      filterable: 1,
      quickSearch: 1,
      lang: 'ds',
      type: '3',
      source: 'catvod_local_zip',
      configType: 'catvod',
      zipFilePath: zipFilePath,
    );

    GStorage.addCustomSite(newSite.toJson());

    // 4. 刷新列表
    await loadConfig();

    // 不再强制自动切换
    // await switchConfig(key);

    // 注：如果这是第一个配置，_selectDefaultSite 会自动选中它
    // 但如果是后续配置，让用户手动点击卡片切换
  }

  void _log(String msg) {
    _logService.addLog(msg);
    debugPrint(msg);
  }

  /// 加载 CatVod 配置（远程或本地 ZIP）
  Future<void> _loadCatVodConfig(String configUrl, {int? loadId}) async {
    final currentLoadId = loadId ?? ++_configLoadId;
    try {
      // ===== 显式检查插件状态 =====
      // 即使 Node 进程已在运行，也要检查插件是否被禁用。
      // 场景：App 运行中用户关闭了 nodejs-win 插件，此时
      // nodejs.isInitialized 仍为 true，不会进入下面的 initialize()，
      // 从而绕过 _initializeDesktop() 里的插件检查。
      final nodejs = NodeJSService.instance;
      final pluginError = nodejs.checkPluginUsable();
      if (pluginError != null) {
        // 停掉已启动的 Node 进程，避免"关闭插件但进程还在跑"的状态
        await nodejs.stopForPluginDisabled();
        throw BusinessException(pluginError);
      }

      if (!nodejs.isInitialized || nodejs.managementPort == 0) {
        await nodejs.initialize();
      }
      if (currentLoadId != _configLoadId) return;

      // ---- 获取当前选中的配置信息 ----
      final selectedKey = GStorage.getSetting<String>('selected_config_key');
      Map<String, dynamic>? selectedConfig;
      if (selectedKey != null && selectedKey.isNotEmpty) {
        final customConfigs = GStorage.getCustomSites();
        try {
          selectedConfig = customConfigs.firstWhere((c) => c['key'] == selectedKey);
        } catch (_) {
          selectedConfig = null;
        }
      }

      // ---- 判断是否为本地 ZIP 配置 ----
      final isLocalZip = selectedConfig != null &&
          selectedConfig['_source'] == 'catvod_local_zip' &&
          selectedConfig['zipFilePath'] != null &&
          selectedConfig['zipFilePath'].toString().isNotEmpty;

      if (isLocalZip) {
        // ===== 本地 ZIP 分支 =====
        // 确保 managementPort 就绪（等待最多3秒）
        if (nodejs.managementPort == 0) {
          _log('📦 本地ZIP：等待 managementPort 就绪...');
          for (int i = 0; i < 6; i++) {
            await Future.delayed(const Duration(milliseconds: 500));
            if (nodejs.managementPort != 0) {
              _log('✅ managementPort 已就绪: ${nodejs.managementPort}');
              break;
            }
          }
        }
        if (nodejs.managementPort == 0) {
          _log('❌ 本地ZIP：managementPort 仍未就绪，无法加载');
          configLoadError.value = true;
          if (currentLoadId == _configLoadId) {
            remoteSites.clear();
            remoteParses.clear();
          }
          return;
        }

        final zipPath = selectedConfig!['zipFilePath'].toString();
        _log('📦 检测到本地 CatVod ZIP，解压并覆盖到固定目录');
        _log('ZIP 文件路径: $zipPath');

        final zipFile = File(zipPath);
        if (!await zipFile.exists()) {
          _log('❌ ZIP 文件不存在: $zipPath');
          configLoadError.value = true;
          if (currentLoadId == _configLoadId) {
            remoteSites.clear();
            remoteParses.clear();
          }
          return;
        }

        final sourceDirPath = await nodejs.getDefaultSourcePath();
        final sourceDir = Directory(sourceDirPath);
        await sourceDir.create(recursive: true);

        try {
          final zipBytes = await zipFile.readAsBytes();
          final archive = ZipDecoder().decodeBytes(zipBytes);

          for (final file in archive) {
            if (file.isFile) {
              final data = file.content as List<int>;
              final targetPath = '${sourceDir.path}/${file.name}';
              final targetFile = File(targetPath);
              await targetFile.parent.create(recursive: true);
              await targetFile.writeAsBytes(data, flush: true);
            }
          }
          _log('✅ 解压完成，共 ${archive.files.length} 个文件');

          final indexFile = File('${sourceDir.path}/index.js');
          if (!await indexFile.exists()) {
            throw Exception('ZIP 包中未找到 index.js');
          }

          final md5File = File('${sourceDir.path}/index.js.md5');
          if (await md5File.exists()) {
            await md5File.delete();
            _log('🧹 已删除旧的 .md5 缓存');
          }

          final loaded = await nodejs.reloadLocalSpider();
          if (!loaded) {
            throw Exception('Node.js 重载蜘蛛失败');
          }

          nodejs.setLastLoadedUrl('local_zip');
        } catch (e) {
          _log('❌ 解压或加载失败: $e');
          configLoadError.value = true;
          if (currentLoadId == _configLoadId) {
            remoteSites.clear();
            remoteParses.clear();
          }
          return;
        }
      } else {
        // ===== 远端分支 =====
        bool needLoadSource = true;
        if (nodejs.spiderPort > 0) {
          final alive = await nodejs.isServiceAlive();
          if (alive && nodejs.lastLoadedUrl == configUrl) {
            _log('[SourceManager] 服务存活且源未变，跳过加载源，直接复用');
            needLoadSource = false;
          }
        }

        if (needLoadSource) {
          final success = await nodejs.loadSourceFromURL(configUrl);
          if (!success) {
            configLoadError.value = true;
            if (currentLoadId == _configLoadId) {
              remoteSites.clear();
              remoteParses.clear();
            }
            return;
          }
          if (currentLoadId != _configLoadId) return;
        }
      }

      // ===== 统一等待 spiderPort 就绪（本地和远端都需要） =====
      await nodejs.waitForSpiderPort();
      if (nodejs.spiderPort == 0) {
        configLoadError.value = true;
        _log('[SourceManager] spiderPort 未就绪，无法获取配置');
        if (currentLoadId == _configLoadId) {
          remoteSites.clear();
        }
        return;
      }
      if (currentLoadId != _configLoadId) return;

      // ===== 获取配置列表（远程与本地共用） =====
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
    } catch (e) {
      configLoadError.value = true;
      _log('[SourceManager] 加载猫影视配置失败: $e');

      // 捕获业务异常（插件缺失/关闭），供首页列表区域展示引导文案
      if (e is BusinessException) {
        configLoadErrorMessage.value = e.message;
      }

      if (loadId == null || loadId == _configLoadId) {
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
    // if (PlatformUtils.isDesktop && configType == 'catvod') {
    //   SmartDialog.showToast('猫影视配置仅支持移动端');
    //   return;
    // }

    // 切换到非猫影视时，只清 Dart 层状态，不调用原生 stopNodeJS
    if (configType != 'catvod') {
      final nodejs = NodeJSService.instance;
      await nodejs.stop(); // 调用公共方法，安全清理所有 Dart 层状态
    }

    await GStorage.setSetting('selected_config_key', configKey);
    currentConfigKey.value = configKey;
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
    Map<String, dynamic>? target = sourceList.firstWhereOrNull(
        (s) => s['key']?.toString() == siteKey);
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

    // 等待切换结果（所有分支都返回 SiteSwitchResult，异常已在 _switchToSite 内 catch）
    final result = await _switchToSite(target);

    _updatePushAgentCache();
    _saveCurrentSiteKey();

    if (result.success) {
      _notifyHomeController();
    } else {
      final raw = result.error;
      final errorMsg = (raw != null && raw.isNotEmpty)
          ? ErrorFormatter.formatSwitchError(raw)   // 幂等，已带切源前缀原样返回
          : '切换源失败：未知错误';
      _notifyHomeControllerFailure(errorMsg);
    }
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
    if (target == null) {
      try {
        target = manualSites.firstWhere((site) => site['key']?.toString() == siteKey);
      } catch (_) {}
    }
    if (target != null) {
      switchSite(target);
    } else {
      print('站点不存在: $siteKey');
    }
  }

  Future<SiteSwitchResult> _switchToSite(Map<String, dynamic> site) async {
    print('_switchToSite received: key=${site['key']}, api=${site['api']}');

    final t = site['type']?.toString();
    if (t == '4' && (site['lang']?.toString() == 'html')) {
      print('[SourceManager] 本地 html 源暂未实现执行: ${site['key']}');
      return SiteSwitchResult.failure(
        '本地 HTML 源暂不支持',
        siteKey: site['key']?.toString(),
      );
    }

    final key = site['key']?.toString();

    try {
      if (isDrpy3Site(site)) {
        return await _switchToDrpy3Site(site);
      }
      if (isDrpy2Site(site)) {
        return await _switchToDrpy2Site(site);
      }
      if (isXbpqSite(site)) {
        return await _switchToXbpqSite(site);
      }
      if (isXyqSite(site)) {
        return await _switchToXyqSite(site);
      }
      if (isCatVodOpenSite(site)) {
        return await _switchToCatVodOpenSite(site);
      }
      if (isPurePy3Site(site)) {
        return await _switchToPy3Site(site);
      }
      if (isNodeJSSite(site)) {
        return await _switchToNodeJSSite(site);
      }
      if (isAppCmsSite(site)) {
        _getOrCreateAppCmsService(site).switchSite(
          site['api']?.toString() ?? '',
          site['key']?.toString() ?? '',
          ext: site['ext'],
        );
        return SiteSwitchResult.success(siteKey: key);
      }
      if (isAppYsV2Site(site) || isAppV2Site(site)) {
        _getOrCreateAppYsV2Service(site).switchSite(
          site['api']?.toString() ?? '',
          site['key']?.toString() ?? '',
          ext: site['ext'],
        );
        return SiteSwitchResult.success(siteKey: key);
      }
      _switchToT4Site(site);
      return SiteSwitchResult.success(siteKey: key);
    } catch (e, st) {
      debugPrint('[SourceManager] _switchToSite 异常: $e\n$st');
      return SiteSwitchResult.failure(
        ErrorFormatter.formatSwitchError(e),
        siteKey: key,
      );
    }
  }

  Future<SiteSwitchResult> _switchToDrpy2Site(Map<String, dynamic> site) async {
    final ok = await _ensureDrpy2Ready();
    if (!ok) {
      print('[SourceManager] drpy2 init failed, cannot switch to drpy2 site');
      return SiteSwitchResult.failure(
        'drpy2 初始化失败',
        siteKey: site['key']?.toString(),
      );
    }
    _drpy2Service.switchSite(
      site['api']?.toString() ?? '',
      site['key']?.toString() ?? '',
      ext: site['ext'],
    );
    return SiteSwitchResult.success(siteKey: site['key']?.toString());
  }

  Future<SiteSwitchResult> _switchToDrpy3Site(Map<String, dynamic> site) async {
    final ok = await _ensureDrpy3Ready();
    if (!ok) {
      print('[SourceManager] drpy3 init failed, cannot switch to drpy3 site');
      return SiteSwitchResult.failure(
        'drpy3 初始化失败',
        siteKey: site['key']?.toString(),
      );
    }
    _drpy3Service.switchSite(
      site['api']?.toString() ?? '',
      site['key']?.toString() ?? '',
      ext: site['ext'],
    );
    return SiteSwitchResult.success(siteKey: site['key']?.toString());
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

  Future<SiteSwitchResult> _switchToXbpqSite(Map<String, dynamic> site) async {
    final service = _getOrCreateXbpqService(site);
    try {
      await service.init();
      service.switchSite(
        site['api']?.toString() ?? '',
        site['key']?.toString() ?? '',
        ext: site['ext'],
      );
      return SiteSwitchResult.success(siteKey: site['key']?.toString());
      } catch (e) {
        return SiteSwitchResult.failure(
          ErrorFormatter.formatException(e),
          siteKey: site['key']?.toString(),
        );
      }
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

  Future<SiteSwitchResult> _switchToXyqSite(Map<String, dynamic> site) async {
    final service = _getOrCreateXyqService(site);
    try {
      await service.init();
      service.switchSite(
        site['api']?.toString() ?? '',
        site['key']?.toString() ?? '',
        ext: site['ext'],
      );
      return SiteSwitchResult.success(siteKey: site['key']?.toString());
      } catch (e) {
        return SiteSwitchResult.failure(
          ErrorFormatter.formatException(e),
          siteKey: site['key']?.toString(),
        );
      }
  }

  CatvodOpenService _getOrCreateCatvodOpenService(Map<String, dynamic> site) {
    return Get.find<CatvodOpenService>();
  }

  Future<SiteSwitchResult> _switchToCatVodOpenSite(Map<String, dynamic> site) async {
    print('_switchToCatVodOpenSite: start for ${site['key']}');
    try {
      final service = _getOrCreateCatvodOpenService(site);
      print('Service obtained, calling switchSiteSafe...');
      final result = await service.switchSiteSafe(
        site['api']?.toString() ?? '',
        site['key']?.toString() ?? '',
        ext: site['ext'],
      );
      print('_switchToCatVodOpenSite: '
          '${result.success ? "ready" : "fail: ${result.error}"}');
      return result;
    } catch (e, stack) {
      print('_switchToCatVodOpenSite error: $e\n$stack');
      return SiteSwitchResult.failure(
        ErrorFormatter.formatSwitchError(e),
        siteKey: site['key']?.toString(),
      );
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

  AppCmsService _getOrCreateAppCmsService(Map<String, dynamic> site) {
    final key = site['key']?.toString() ?? 'appcms_default';
    if (!Get.isRegistered<AppCmsService>(tag: key)) {
      final service = AppCmsService(key, site['ext']?.toString() ?? '');
      Get.put(service, tag: key, permanent: true);
    }
    return Get.find<AppCmsService>(tag: key);
  }

  AppYsV2Service _getOrCreateAppYsV2Service(Map<String, dynamic> site) {
    final key = site['key']?.toString() ?? 'appysv2_default';
    if (!Get.isRegistered<AppYsV2Service>(tag: key)) {
      final service = AppYsV2Service(key, site['ext']?.toString() ?? '');
      Get.put(service, tag: key, permanent: true);
    }
    return Get.find<AppYsV2Service>(tag: key);
  }

  Future<SiteSwitchResult> _switchToPy3Site(Map<String, dynamic> site) async {
    final service = _getOrCreatePy3Service(site);
    return await service.switchSiteSafe(
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

  Future<SiteSwitchResult> _switchToNodeJSSite(Map<String, dynamic> site) async {
    final service = _getNodeJSService();
    final siteKey = site['key']?.toString();
    final nodejs = NodeJSService.instance;

    // ===== 第一步：无条件先把 Dart 侧 spider 状态切到目标源 =====
    // switchSite 是同步方法，只更新 NodeJSSpiderService._currentKey/_baseUrl
    // 以及 NodeJSService._currentSpiderKey/_spiderApiBase，不发起网络请求。
    //
    // 即使插件关闭导致后续步骤失败，这里的更新也能保证：
    //   - _currentKey 与 currentSite.value 一致
    //   - 后续重试 / 刷新 / 切分类时，_ensureNodeReady 会用正确的 key
    service.switchSite(
      site['api']?.toString() ?? '',
      siteKey ?? '',
      ext: site['ext'],
    );

    // ===== 第二步：插件状态检查 =====
    final pluginError = nodejs.checkPluginUsable();
    if (pluginError != null) {
      await nodejs.stopForPluginDisabled();
      return SiteSwitchResult.failure(pluginError, siteKey: siteKey);
    }

    // ===== 第三步：确保 Node 进程 + 源就绪（幂等，已就绪时内部立即返回） =====
    try {
      await nodejs.ensureReady();
    } catch (e) {
      return SiteSwitchResult.failure(
        ErrorFormatter.formatSwitchError(e),
        siteKey: siteKey,
      );
    }

    // ===== 第四步：init spider =====
    try {
      await service.initSpider();
      return SiteSwitchResult.success(siteKey: siteKey);
    } catch (e) {
      return SiteSwitchResult.failure(
        ErrorFormatter.formatSwitchError(e),
        siteKey: siteKey,
      );
    }
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

  void _notifyHomeControllerFailure(String error) {
    if (Get.isRegistered<HomeController>()) {
      Get.find<HomeController>().onSiteChangedFailure(error);
    }
  }

  void _updatePushAgentCache() {
    for (final site in this.sites) {
      final key = site['key']?.toString() ?? '';
      final name = site['name']?.toString() ?? '';
      final type = site['type'] as int? ?? -1;

      // type=4 且（key 精确匹配 OR 名称包含 push_agent）
      // - 远端配置：key='push_agent', type=4
      // - 手动 T4：key='manual_t4_push_agent', name='push_agent(T4)', type=4
      if (type == 4 &&
          (key == 'push_agent' ||
              name.toLowerCase().contains('push_agent'))) {
        _pushAgentSite.value = site;
        return;
      }
    }
    _pushAgentSite.value = null;
  }
}