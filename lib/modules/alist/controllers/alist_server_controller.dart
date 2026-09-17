import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../models/alist_server.dart';

class AlistServerController extends GetxController {
  final RxList<AlistServer> servers = <AlistServer>[].obs;
  final RxString currentServerId = ''.obs;

  AlistServer? get currentServer {
    if (servers.isEmpty) return null;
    if (currentServerId.isNotEmpty &&
        servers.any((s) => s.id == currentServerId.value)) {
      return servers.firstWhere((s) => s.id == currentServerId.value);
    }
    final def = servers.firstWhere(
      (s) => s.isDefault,
      orElse: () => servers.first,
    );
    currentServerId.value = def.id;
    return def;
  }

  @override
  void onInit() {
    super.onInit();
    _loadFromStorage();
  }

  void _loadFromStorage() {
    final list = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.servers,
        ) ??
        [];
    servers.assignAll(
      list
          .map((e) => AlistServer.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
    final savedId = StorageManager.getSetting<String>(
          AlistStorageKeys.currentServerId,
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
      AlistStorageKeys.servers,
      servers.map((s) => s.toJson()).toList(),
    );
  }

  void _saveCurrentId() {
    StorageManager.setSetting(
      AlistStorageKeys.currentServerId,
      currentServerId.value,
    );
  }

  Future<void> addServer(String name, String baseUrl) async {
    var url = baseUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (!url.endsWith('/')) url = '$url/';

    final server = AlistServer(
      id: const Uuid().v4(),
      name: name.trim().isEmpty ? url : name.trim(),
      serverUrl: url,
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
    await StorageManager.deleteSetting('${AlistStorageKeys.tokenPrefix}$id');
    servers.refresh();
  }

  Future<void> setDefault(String id) async {
    // 如果已经是当前默认，直接返回（避免无谓的 RxList 通知）
    if (currentServerId.value == id &&
        servers.any((s) => s.id == id && s.isDefault)) {
      return;
    }

    for (final s in servers) {
      s.isDefault = s.id == id;
    }
    currentServerId.value = id;
    _saveToStorage();
    _saveCurrentId();
    servers.refresh();
  }

  Future<void> updateCredentials(
    String id, {
    String? username,
    String? password,
    bool? guest,
    bool? ignoreSSLError,
  }) async {
    final index = servers.indexWhere((s) => s.id == id);
    if (index == -1) return;
    servers[index] = servers[index].copyWith(
      username: username,
      password: password,
      guest: guest,
      ignoreSSLError: ignoreSSLError,
    );
    _saveToStorage();
    servers.refresh();
  }

  /// 退出登录：清除 token 和用户凭证，保留服务器配置
  Future<void> logout(String serverId) async {
    await deleteToken(serverId);
    final index = servers.indexWhere((s) => s.id == serverId);
    if (index != -1) {
      final s = servers[index];
      servers[index] = AlistServer(
        id: s.id,
        name: s.name,
        serverUrl: s.serverUrl,
        username: null,
        password: null,
        guest: false,
        ignoreSSLError: s.ignoreSSLError,
        isDefault: s.isDefault,
      );
      _saveToStorage();
      servers.refresh();
    }
  }

  // ===== Token 管理 =====
  String? getToken(String serverId) {
    return StorageManager.getSetting<String>(
      '${AlistStorageKeys.tokenPrefix}$serverId',
    );
  }

  Future<void> saveToken(String serverId, String token) async {
    await StorageManager.setSetting(
      '${AlistStorageKeys.tokenPrefix}$serverId',
      token,
    );
  }

  Future<void> deleteToken(String serverId) async {
    await StorageManager.deleteSetting(
      '${AlistStorageKeys.tokenPrefix}$serverId',
    );
  }

  bool isLoggedIn(String serverId) {
    final t = getToken(serverId);
    return t != null && t.isNotEmpty;
  }
}