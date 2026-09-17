import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

import '../models/smb_server.dart';

class SmbServerController extends GetxController {
  final RxList<SmbServer> servers = <SmbServer>[].obs;
  final RxString currentId = ''.obs;

  SmbServer? get current {
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
      SmbStorageKeys.servers,
    );
    if (raw != null) {
      servers.assignAll(raw
          .map((e) => SmbServer.fromJson(Map<String, dynamic>.from(e)))
          .toList());
    }
    currentId.value =
        StorageManager.getSetting<String>(SmbStorageKeys.currentId) ?? '';
  }

  void _save() {
    StorageManager.setSetting(
      SmbStorageKeys.servers,
      servers.map((s) => s.toJson()).toList(),
    );
    StorageManager.setSetting(SmbStorageKeys.currentId, currentId.value);
  }

  Future<void> addServer(SmbServer server) async {
    servers.add(server);
    if (currentId.value.isEmpty) currentId.value = server.id;
    _save();
  }

  Future<void> updateServer(SmbServer server) async {
    final i = servers.indexWhere((s) => s.id == server.id);
    if (i < 0) return;
    servers[i] = server;
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

  String newId() => const Uuid().v4();
}