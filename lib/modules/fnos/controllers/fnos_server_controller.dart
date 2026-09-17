import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../models/fnos_server_model.dart';
import '../services/fnos_api_service.dart';

class FnosServerController extends GetxController {
  final RxList<FnosServer> servers = <FnosServer>[].obs;
  final RxString currentServerId = ''.obs;
  final FnosApiService apiService = FnosApiService();

  FnosServer? get currentServer {
    if (currentServerId.isNotEmpty &&
        servers.any((s) => s.id == currentServerId.value)) {
      return servers.firstWhere((s) => s.id == currentServerId.value);
    }
    if (servers.isNotEmpty) {
      final def = servers.firstWhere(
        (s) => s.isDefault,
        orElse: () => servers.first,
      );
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

  // ============================================================
  // 存储
  // ============================================================
  void _loadFromStorage() {
    final list = StorageManager.getSetting<List<dynamic>>(
          FnosStorageKeys.servers,
        ) ??
        [];
    servers.assignAll(list.map((e) {
      return FnosServer.fromJson(Map<String, dynamic>.from(e as Map));
    }));

    final savedId = StorageManager.getSetting<String>(
          FnosStorageKeys.currentServerId,
        ) ??
        '';
    if (servers.any((s) => s.id == savedId)) {
      currentServerId.value = savedId;
    } else if (servers.isNotEmpty) {
      currentServerId.value = servers.first.id;
      _saveCurrentId();
    }
    servers.refresh();
  }

  void _saveToStorage() {
    StorageManager.setSetting(
      FnosStorageKeys.servers,
      servers.map((s) => s.toJson()).toList(),
    );
  }

  void _saveCurrentId() {
    StorageManager.setSetting(
      FnosStorageKeys.currentServerId,
      currentServerId.value,
    );
  }

  // ============================================================
  // 增删改
  // ============================================================
  Future<void> addServer(String name, String baseUrl) async {
    var url = baseUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    final server = FnosServer(
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
    await StorageManager.deleteSetting('${FnosStorageKeys.tokenPrefix}$id');
  }

  Future<void> setDefault(String id) async {
    for (final s in servers) {
      s.isDefault = s.id == id;
    }
    currentServerId.value = id;
    _saveToStorage();
    _saveCurrentId();
    servers.refresh();
  }

  Future<void> updateServerCredentials(
    String id,
    String username,
  ) async {
    final index = servers.indexWhere((s) => s.id == id);
    if (index != -1) {
      servers[index] = servers[index].copyWith(
        userId: username,
        username: username,
      );
      _saveToStorage();
      servers.refresh();
    }
  }

  // ============================================================
  // Token
  // ============================================================
  String? getToken(String serverId) {
    return StorageManager.getSetting<String>(
      '${FnosStorageKeys.tokenPrefix}$serverId',
    );
  }

  Future<void> saveToken(String serverId, String token) async {
    await StorageManager.setSetting(
      '${FnosStorageKeys.tokenPrefix}$serverId',
      token,
    );
  }

  Future<void> deleteToken(String serverId) async {
    await StorageManager.deleteSetting(
      '${FnosStorageKeys.tokenPrefix}$serverId',
    );
  }

  bool isLoggedIn(String serverId) => getToken(serverId) != null;

  // ============================================================
  // 登录 / 退出
  // ============================================================
  Future<bool> login({
    required String serverId,
    required String username,
    required String password,
  }) async {
    final idx = servers.indexWhere((s) => s.id == serverId);
    if (idx == -1) return false;
    final server = servers[idx];

    final result = await apiService.login(
      baseUrl: server.baseUrl,
      username: username,
      password: password,
    );
    if (result['code'] != 0) return false;

    final data = result['data'];
    if (data is! Map) return false;
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) return false;

    await saveToken(serverId, token);
    await updateServerCredentials(serverId, username);
    return true;
  }

  Future<void> logout(String serverId) async {
    await deleteToken(serverId);
    final index = servers.indexWhere((s) => s.id == serverId);
    if (index != -1) {
      servers[index] = FnosServer(
        id: servers[index].id,
        name: servers[index].name,
        baseUrl: servers[index].baseUrl,
        isDefault: servers[index].isDefault,
      );
      _saveToStorage();
      servers.refresh();
    }
  }
}