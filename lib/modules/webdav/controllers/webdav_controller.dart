import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/utils/device_utils.dart';

class WebDavController extends GetxController {
  late String _webdavDirectory;
  String? _fileName;
  webdav.Client? _client;

  final RxBool isLoading = false.obs;

  // ============================================================
  // 初始化 / 测试连接
  // ============================================================
  Future<bool> init() async {
    final webDavUri = SettingPref.webdavUri;
    final webDavUsername = SettingPref.webdavUsername;
    final webDavPassword = SettingPref.webdavPassword;
    _webdavDirectory = SettingPref.webdavDirectory;
    if (!_webdavDirectory.endsWith('/')) {
      _webdavDirectory += '/';
    }
    _webdavDirectory += '源影';

    try {
      _client = null;
      final client = webdav.newClient(
        webDavUri,
        user: webDavUsername,
        password: webDavPassword,
      )
        ..setHeaders({'accept-charset': 'utf-8'})
        ..setConnectTimeout(12000)
        ..setReceiveTimeout(12000)
        ..setSendTimeout(12000);

      await client.mkdirAll(_webdavDirectory);
      _client = client;
      return true;
    } catch (e) {
      return false;
    }
  }

  String _getFileName() {
    return 'yuanying_backup.zip';
  }

  // ============================================================
  // 上传：把 ZIP 字节写到 WebDAV
  // ============================================================
  Future<bool> uploadBackup(Uint8List zipBytes) async {
    if (_client == null) {
      final success = await init();
      if (!success) return false;
    }
    try {
      _fileName ??= _getFileName();
      final path = '$_webdavDirectory/$_fileName';
      try {
        await _client!.remove(path);
      } catch (_) {}
      await _client!.write(path, zipBytes);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // 下载：从 WebDAV 读取 ZIP 字节
  // ============================================================
  Future<Uint8List?> downloadBackup() async {
    if (_client == null) {
      final success = await init();
      if (!success) return null;
    }
    try {
      _fileName ??= _getFileName();
      final path = '$_webdavDirectory/$_fileName';
      final data = await _client!.read(path);
      return Uint8List.fromList(data);
    } catch (e) {
      return null;
    }
  }
}