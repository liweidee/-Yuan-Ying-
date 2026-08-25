// lib/modules/setting/controllers/danmaku_config_controller.dart
import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/models/danmaku/danmaku_api.dart';
import 'package:yuanying/utils/storage_manager.dart';

class DanmakuConfigController extends GetxController {
  final RxList<DanmakuApi> apis = <DanmakuApi>[].obs;
  final RxString currentKey = ''.obs;
  final RxBool autoMatch = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadApis();
    autoMatch.value = StorageManager.getSetting<bool>(SettingBoxKey.danmakuAutoMatch) ?? false;
  }

  void loadApis() {
    final list = StorageManager.getSetting<List<dynamic>>(SettingBoxKey.danmakuApis) ?? [];
    apis.assignAll(list.map((e) => DanmakuApi.fromJson(Map<String, dynamic>.from(e))).toList());

    final savedKey = StorageManager.getSetting<String>(SettingBoxKey.danmakuCurrentKey);
    if (savedKey != null && apis.any((a) => a.key == savedKey)) {
      currentKey.value = savedKey;
    } else if (apis.isNotEmpty) {
      currentKey.value = apis.first.key;
      StorageManager.setSetting(SettingBoxKey.danmakuCurrentKey, currentKey.value);
    } else {
      currentKey.value = '';
    }
    // 初始加载后刷新
    apis.refresh();
  }

  Future<void> saveApis() async {
    await StorageManager.setSetting(
      SettingBoxKey.danmakuApis,
      apis.map((a) => a.toJson()).toList(),
    );
  }

  Future<void> switchApi(String key) async {
    if (currentKey.value == key) return;
    if (!apis.any((a) => a.key == key)) return;

    currentKey.value = key;
    await StorageManager.setSetting(SettingBoxKey.danmakuCurrentKey, key);
    // 强制刷新列表
    apis.refresh();
  }

  Future<void> addApi(String name, String api) async {
    final key = _generateKey(name);
    final newApi = DanmakuApi(key: key, name: name, api: api);
    apis.add(newApi);
    await saveApis();
    if (apis.length == 1) {
      currentKey.value = key;
      await StorageManager.setSetting(SettingBoxKey.danmakuCurrentKey, key);
    }
    // 添加后刷新
    apis.refresh();
  }

  Future<void> updateApi(String key, String name, String api) async {
    final index = apis.indexWhere((a) => a.key == key);
    if (index != -1) {
      apis[index] = DanmakuApi(key: key, name: name, api: api);
      await saveApis();
      if (currentKey.value == key) {
        currentKey.value = key;
        // 更新后刷新
        apis.refresh();
      }
    }
  }

  Future<void> deleteApi(String key) async {
    apis.removeWhere((a) => a.key == key);
    await saveApis();

    if (currentKey.value == key) {
      if (apis.isNotEmpty) {
        currentKey.value = apis.first.key;
        await StorageManager.setSetting(SettingBoxKey.danmakuCurrentKey, currentKey.value);
      } else {
        currentKey.value = '';
        await StorageManager.deleteSetting(SettingBoxKey.danmakuCurrentKey);
      }
    }
    // 删除后刷新
    apis.refresh();
  }

  Future<void> toggleAutoMatch(bool value) async {
    autoMatch.value = value;
    await StorageManager.setSetting(SettingBoxKey.danmakuAutoMatch, value);
  }

  String _generateKey(String name) {
    String key = name.toLowerCase().replaceAll(' ', '_');
    int index = 1;
    final existing = apis.map((a) => a.key).toList();
    while (existing.contains(key)) {
      key = '${name.toLowerCase().replaceAll(' ', '_')}_$index';
      index++;
    }
    return key;
  }
}