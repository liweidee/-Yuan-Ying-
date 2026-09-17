import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../models/emby_server_model.dart';
import '../services/emby_api_service.dart';

class EmbyServerController extends GetxController {
  final RxList<EmbyServer> servers = <EmbyServer>[].obs;
  final RxString currentServerId = ''.obs;
  final EmbyApiService apiService = EmbyApiService();

  EmbyServer? get currentServer {
    if (currentServerId.isNotEmpty && servers.any((s) => s.id == currentServerId.value)) {
      return servers.firstWhere((s) => s.id == currentServerId.value);
    }
    if (servers.isNotEmpty) {
      final def = servers.firstWhere((s) => s.isDefault, orElse: () => servers.first);
      currentServerId.value = def.id;
      return def;
    }
    return null;
  }

  @override
  void onInit() {
    super.onInit();
    _loadFromStorage();
  }

  void _loadFromStorage() {
    final list = StorageManager.getSetting<List<dynamic>>(EmbyStorageKeys.servers) ?? [];
    servers.assignAll(list.map((e) => EmbyServer.fromJson(Map<String, dynamic>.from(e))));
    final savedId = StorageManager.getSetting<String>(EmbyStorageKeys.currentServerId) ?? '';
    if (servers.any((s) => s.id == savedId)) {
      currentServerId.value = savedId;
    } else if (servers.isNotEmpty) {
      currentServerId.value = servers.first.id;
      _saveCurrentId();
    }
    servers.refresh();
  }

  void _saveToStorage() {
    StorageManager.setSetting(EmbyStorageKeys.servers, servers.map((s) => s.toJson()).toList());
  }

  void _saveCurrentId() {
    StorageManager.setSetting(EmbyStorageKeys.currentServerId, currentServerId.value);
  }

  Future<void> addServer(String name, String baseUrl) async {
    var url = baseUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    final server = EmbyServer(
      id: const Uuid().v4(),
      name: name.trim(),
      baseUrl: url,
      isDefault: servers.isEmpty,
    );
    servers.add(server);
    _saveToStorage();
    if (servers.length == 1) {
      currentServerId.value = server.id;
      _saveCurrentId();
    }
    servers.refresh();
  }

  Future<void> deleteServer(String id) async {
    servers.removeWhere((s) => s.id == id);
    _saveToStorage();
    if (currentServerId.value == id) {
      currentServerId.value = servers.isNotEmpty ? servers.first.id : '';
      _saveCurrentId();
    }
    servers.refresh();
    await StorageManager.deleteSetting('${EmbyStorageKeys.tokenPrefix}$id');
  }

  Future<void> setDefault(String id) async {
    for (final s in servers) s.isDefault = s.id == id;
    currentServerId.value = id;
    _saveToStorage();
    _saveCurrentId();
    servers.refresh();
  }

  Future<void> updateServerCredentials(String id, String userId, String username) async {
    final index = servers.indexWhere((s) => s.id == id);
    if (index != -1) {
      servers[index] = servers[index].copyWith(userId: userId, username: username);
      _saveToStorage();
      servers.refresh();
    }
  }

  // ----- Token 管理 -----
  String? getToken(String serverId) {
    return StorageManager.getSetting<String>('${EmbyStorageKeys.tokenPrefix}$serverId');
  }

  Future<void> saveToken(String serverId, String token) async {
    await StorageManager.setSetting('${EmbyStorageKeys.tokenPrefix}$serverId', token);
  }

  Future<void> deleteToken(String serverId) async {
    await StorageManager.deleteSetting('${EmbyStorageKeys.tokenPrefix}$serverId');
  }

  // ----- 便捷方法：检查是否已登录 -----
  bool isLoggedIn(String serverId) => getToken(serverId) != null;

  // ----- 退出登录（清除 Token 和用户信息，但保留服务器配置） -----
  Future<void> logout(String serverId) async {
    // 1. 删除 Token
    await deleteToken(serverId);

    // 2. 清除该服务器的用户绑定信息（userId / username）
    final index = servers.indexWhere((s) => s.id == serverId);
    if (index != -1) {
      servers[index] = EmbyServer(
        id: servers[index].id,
        name: servers[index].name,
        baseUrl: servers[index].baseUrl,
        userId: null,      // 清除
        username: null,    // 清除
        isDefault: servers[index].isDefault,
      );
      _saveToStorage();
      servers.refresh();
    }
  }
}