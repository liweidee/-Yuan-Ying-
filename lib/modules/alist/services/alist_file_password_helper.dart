import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../controllers/alist_server_controller.dart';
import '../models/alist_file_password.dart';

class AlistFilePasswordHelper {
  AlistFilePasswordHelper._();
  static final AlistFilePasswordHelper instance = AlistFilePasswordHelper._();

  List<AlistFilePassword> _loadAll() {
    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.filePasswords,
        ) ??
        [];
    return raw
        .map((e) => AlistFilePassword.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _saveAll(List<AlistFilePassword> list) async {
    await StorageManager.setSetting(
      AlistStorageKeys.filePasswords,
      list.map((e) => e.toJson()).toList(),
    );
  }

  /// 从当前路径向上查找密码
  Future<String?> findPasswordByPath(
    String remotePath, {
    String? backupPassword,
  }) async {
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return backupPassword;

    var path = remotePath;
    if (!path.startsWith('/')) path = '/$path';

    final all = _loadAll();
    final serverId = server.id;
    final userId = server.username ?? 'guest';

    if (backupPassword != null) {
      // 精确匹配 + backup 兜底
      final exact = all.firstWhereOrNull((p) =>
          p.serverId == serverId &&
          p.userId == userId &&
          p.remotePath == path);
      return exact?.password ?? backupPassword;
    }

    // 从当前路径逐级向上查找
    var current = path;
    while (current.isNotEmpty) {
      final found = all.firstWhereOrNull((p) =>
          p.serverId == serverId &&
          p.userId == userId &&
          p.remotePath == current);
      if (found != null) return found.password;
      final idx = current.lastIndexOf('/');
      if (idx <= 0) break;
      current = current.substring(0, idx);
    }
    return null;
  }

  Future<void> savePassword(String remotePath, String password) async {
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return;

    final all = _loadAll();
    final serverId = server.id;
    final userId = server.username ?? 'guest';

    // 先删旧的
    all.removeWhere((p) =>
        p.serverId == serverId &&
        p.userId == userId &&
        p.remotePath == remotePath);

    all.add(AlistFilePassword(
      id: const Uuid().v4(),
      serverId: serverId,
      userId: userId,
      remotePath: remotePath,
      password: password,
      createTime: DateTime.now().millisecondsSinceEpoch,
    ));

    await _saveAll(all);
  }

  Future<void> deletePassword(String remotePath) async {
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return;

    final all = _loadAll();
    all.removeWhere((p) =>
        p.serverId == server.id &&
        p.userId == (server.username ?? 'guest') &&
        p.remotePath == remotePath);
    await _saveAll(all);
  }
}