// lib/modules/setting/controllers/live_config_controller.dart
import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/models/live/live_config.dart';
import 'package:yuanying/utils/storage_manager.dart';

class LiveConfigController extends GetxController {
  final RxList<LiveConfig> configs = <LiveConfig>[].obs;
  final RxString currentKey = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadConfigs();
  }

  void loadConfigs() {
    final list = StorageManager.getSetting<List<dynamic>>(SettingBoxKey.liveConfigs) ?? [];
    configs.assignAll(list.map((e) => LiveConfig.fromJson(Map<String, dynamic>.from(e))).toList());

    final savedKey = StorageManager.getSetting<String>(SettingBoxKey.liveCurrentKey);
    if (savedKey != null && configs.any((c) => c.key == savedKey)) {
      currentKey.value = savedKey;
    } else if (configs.isNotEmpty) {
      currentKey.value = configs.first.key;
      StorageManager.setSetting(SettingBoxKey.liveCurrentKey, currentKey.value);
    } else {
      currentKey.value = '';
    }
    // 初始加载后刷新一次，确保UI同步
    configs.refresh();
  }

  Future<void> saveConfigs() async {
    await StorageManager.setSetting(
      SettingBoxKey.liveConfigs,
      configs.map((c) => c.toJson()).toList(),
    );
  }

  Future<void> switchConfig(String key) async {
    if (currentKey.value == key) return;
    if (!configs.any((c) => c.key == key)) return;

    currentKey.value = key;
    await StorageManager.setSetting(SettingBoxKey.liveCurrentKey, key);
    // 强制刷新列表，确保UI更新选中状态
    configs.refresh();
  }

  Future<void> addConfig(String name, String url, {String? ua, String? epg, String? logo}) async {
    final key = _generateKey(name);
    final newConfig = LiveConfig(
      key: key,
      name: name,
      url: url,
      ua: ua,
      epg: epg,
      logo: logo,
    );
    configs.add(newConfig);
    await saveConfigs();
    if (configs.length == 1) {
      currentKey.value = key;
      await StorageManager.setSetting(SettingBoxKey.liveCurrentKey, key);
    }
    // 添加后刷新
    configs.refresh();
  }

  Future<void> updateConfig(String key, String name, String url, {String? ua, String? epg, String? logo}) async {
    final index = configs.indexWhere((c) => c.key == key);
    if (index != -1) {
      configs[index] = LiveConfig(
        key: key,
        name: name,
        url: url,
        ua: ua,
        epg: epg,
        logo: logo,
      );
      await saveConfigs();
      if (currentKey.value == key) {
        currentKey.value = key;
        // 更新后刷新
        configs.refresh();
      }
    }
  }

  Future<void> deleteConfig(String key) async {
    configs.removeWhere((c) => c.key == key);
    await saveConfigs();

    if (currentKey.value == key) {
      if (configs.isNotEmpty) {
        currentKey.value = configs.first.key;
        await StorageManager.setSetting(SettingBoxKey.liveCurrentKey, currentKey.value);
      } else {
        currentKey.value = '';
        await StorageManager.deleteSetting(SettingBoxKey.liveCurrentKey);
      }
    }
    // 删除后刷新
    configs.refresh();
  }

  String _generateKey(String name) {
    String key = name.toLowerCase().replaceAll(' ', '_');
    int index = 1;
    final existing = configs.map((c) => c.key).toList();
    while (existing.contains(key)) {
      key = '${name.toLowerCase().replaceAll(' ', '_')}_$index';
      index++;
    }
    return key;
  }
}