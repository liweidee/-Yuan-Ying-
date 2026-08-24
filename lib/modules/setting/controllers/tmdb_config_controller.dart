import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/storage_manager.dart';

class TmdbConfigController extends GetxController {
  final SourceManager sourceManager = Get.find<SourceManager>();

  final RxString accessToken = ''.obs;
  final RxString apiProxy = ''.obs;
  final RxString imageProxy = ''.obs;
  final RxBool enabled = false.obs;
  
  // 响应式站点启用状态 Map
  final RxMap<String, bool> siteEnabledMap = <String, bool>{}.obs;

  late final TextEditingController tokenController;
  late final TextEditingController apiProxyController;
  late final TextEditingController imageProxyController;

  static const List<String> apiProxyOptions = [
    'https://api.tmdb.org',
    'https://api.tmdb.org/proxy1',
    'https://api.tmdb.org/proxy2',
  ];
  static const List<String> imageProxyOptions = [
    'https://images.tmdb.org/t/p',
    'https://image.tmdb.org/t/p',
    'https://img.tmdb.org/t/p',
  ];

  @override
  void onInit() {
    super.onInit();
    tokenController = TextEditingController();
    apiProxyController = TextEditingController();
    imageProxyController = TextEditingController();

    loadSettings();

    tokenController.addListener(() => accessToken.value = tokenController.text);
    apiProxyController.addListener(() => apiProxy.value = apiProxyController.text);
    imageProxyController.addListener(() => imageProxy.value = imageProxyController.text);
  }

  @override
  void onClose() {
    tokenController.dispose();
    apiProxyController.dispose();
    imageProxyController.dispose();
    super.onClose();
  }

  void loadSettings() {
    final token = StorageManager.getSetting<String>(SettingBoxKey.tmdbAccessToken) ?? '';
    final api = StorageManager.getSetting<String>(SettingBoxKey.tmdbApiProxy) ?? 'https://api.tmdb.org';
    final image = StorageManager.getSetting<String>(SettingBoxKey.tmdbImageProxy) ?? 'https://images.tmdb.org/t/p';
    final enabled = StorageManager.getSetting<bool>(SettingBoxKey.tmdbEnabled) ?? false;

    accessToken.value = token;
    apiProxy.value = api;
    imageProxy.value = image;
    this.enabled.value = enabled;

    tokenController.text = token;
    apiProxyController.text = api;
    imageProxyController.text = image;

    // 加载站点启用状态
    final map = StorageManager.getSetting<Map<String, dynamic>>(SettingBoxKey.tmdbSiteEnabledMap);
    if (map != null) {
      siteEnabledMap.assignAll(map.map((k, v) => MapEntry(k, v as bool)));
    } else {
      siteEnabledMap.clear();
    }
  }

  Future<void> saveSettings() async {
    await StorageManager.setSetting(SettingBoxKey.tmdbAccessToken, accessToken.value);
    await StorageManager.setSetting(SettingBoxKey.tmdbApiProxy, apiProxy.value);
    await StorageManager.setSetting(SettingBoxKey.tmdbImageProxy, imageProxy.value);
    await StorageManager.setSetting(SettingBoxKey.tmdbEnabled, enabled.value);
  }

  Future<void> clearSettings() async {
    await StorageManager.deleteSetting(SettingBoxKey.tmdbAccessToken);
    await StorageManager.deleteSetting(SettingBoxKey.tmdbApiProxy);
    await StorageManager.deleteSetting(SettingBoxKey.tmdbImageProxy);
    await StorageManager.deleteSetting(SettingBoxKey.tmdbEnabled);
    await StorageManager.deleteSetting(SettingBoxKey.tmdbSiteEnabledMap);
    loadSettings();
  }

  void setApiProxy(String url) {
    apiProxyController.text = url;
    apiProxy.value = url;
  }

  void setImageProxy(String url) {
    imageProxyController.text = url;
    imageProxy.value = url;
  }

  // ===== 站点启用状态管理（使用 RxMap） =====
  Future<void> setSiteEnabled(String siteKey, bool enabled) async {
    siteEnabledMap[siteKey] = enabled;
    final map = Map<String, bool>.from(siteEnabledMap);
    await StorageManager.setSetting(SettingBoxKey.tmdbSiteEnabledMap, map);
  }

  bool isSiteEnabled(String siteKey) {
    return siteEnabledMap[siteKey] ?? false;
  }

  // 获取所有站点列表（从 SourceManager）
  List<Map<String, dynamic>> getSites() {
    return sourceManager.sites;
  }

  // 获取启用数量（基于 RxMap 动态计算）
  int getEnabledCount() {
    int count = 0;
    for (final site in getSites()) {
      final key = site['key']?.toString() ?? '';
      if (key.isNotEmpty && (siteEnabledMap[key] ?? false)) {
        count++;
      }
    }
    return count;
  }
}