import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

import '../models/ftp_server.dart';

class FtpServerController extends GetxController {
  final RxList<FtpServer> servers = <FtpServer>[].obs;
  final RxString currentId = ''.obs;

  FtpServer? get current {
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
      FtpStorageKeys.servers,
    );
    if (raw != null) {
      servers.assignAll(raw
          .map((e) => FtpServer.fromJson(Map<String, dynamic>.from(e)))
          .toList());
    }
    currentId.value =
        StorageManager.getSetting<String>(FtpStorageKeys.currentId) ?? '';
  }

  void _save() {
    StorageManager.setSetting(
      FtpStorageKeys.servers,
      servers.map((s) => s.toJson()).toList(),
    );
    StorageManager.setSetting(FtpStorageKeys.currentId, currentId.value);
  }

  Future<void> addServer(FtpServer server) async {
    servers.add(server);
    if (currentId.value.isEmpty) currentId.value = server.id;
    _save();
  }

  Future<void> updateServer(FtpServer server) async {
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