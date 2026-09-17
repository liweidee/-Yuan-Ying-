import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../models/webdav_server.dart';

class WebDavServerController extends GetxController {
  final RxList<WebDavServer> servers = <WebDavServer>[].obs;
  final RxString currentId = ''.obs;

  WebDavServer? get current {
    if (servers.isEmpty) return null;
    if (currentId.value.isEmpty) return servers.first;
    try {
      return servers.firstWhere((s) => s.id == currentId.value);
    } catch (_) {
      return servers.first;
    }
  }

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void _load() {
    final raw = StorageManager.getSetting<List<dynamic>>(
      WebDavStorageKeys.servers,
    );
    if (raw != null) {
      servers.assignAll(raw
          .map((e) => WebDavServer.fromJson(Map<String, dynamic>.from(e)))
          .toList());
    }
    currentId.value =
        StorageManager.getSetting<String>(WebDavStorageKeys.currentId) ?? '';
  }

  void _save() {
    StorageManager.setSetting(
      WebDavStorageKeys.servers,
      servers.map((s) => s.toJson()).toList(),
    );
    StorageManager.setSetting(WebDavStorageKeys.currentId, currentId.value);
  }

  Future<void> addServer({
    required String name,
    required String url,
    required String username,
    required String password,
    required bool allowSelfSigned,
  }) async {
    final server = WebDavServer(
      id: const Uuid().v4(),
      name: name.isEmpty ? url : name,
      url: url.endsWith('/') ? url.substring(0, url.length - 1) : url,
      username: username,
      password: password,
      allowSelfSigned: allowSelfSigned,
    );
    servers.add(server);
    if (currentId.value.isEmpty) currentId.value = server.id;
    _save();
  }

  Future<void> updateServer(
    String id, {
    required String name,
    required String url,
    required String username,
    required String password,
    required bool allowSelfSigned,
  }) async {
    final i = servers.indexWhere((s) => s.id == id);
    if (i < 0) return;
    servers[i] = servers[i].copyWith(
      name: name.isEmpty ? url : name,
      url: url.endsWith('/') ? url.substring(0, url.length - 1) : url,
      username: username,
      password: password.isEmpty ? servers[i].password : password,
      allowSelfSigned: allowSelfSigned,
    );
    _save();
  }

  Future<void> deleteServer(String id) async {
    servers.removeWhere((s) => s.id == id);
    if (currentId.value == id) {
      currentId.value = servers.isNotEmpty ? servers.first.id : '';
    }
    _save();
  }

  Future<void> selectServer(String id) async {
    currentId.value = id;
    _save();
  }
}