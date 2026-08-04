import 'dart:convert';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/utils/device_utils.dart';
import 'package:yuanying/utils/storage.dart';

class WebDavController extends GetxController {
  late String _webdavDirectory;
  String? _fileName;
  webdav.Client? _client;

  // 加载状态
  final RxBool isLoading = false.obs;

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
    return 'yuanying_settings_${DeviceUtils.platformName}.json';
  }

  Future<void> backup() async {
    if (_client == null) {
      final success = await init();
      if (!success) {
        SmartDialog.showToast('备份失败，请检查 WebDAV 配置');
        return;
      }
    }
    try {
      String data = GStorage.exportAllSettings();
      _fileName ??= _getFileName();
      final path = '$_webdavDirectory/$_fileName';
      try {
        await _client!.remove(path);
      } catch (_) {}
      await _client!.write(path, utf8.encode(data));
      SmartDialog.showToast('备份成功');
    } catch (e) {
      SmartDialog.showToast('备份失败: $e');
    }
  }

  Future<void> restore() async {
    if (_client == null) {
      final success = await init();
      if (!success) {
        SmartDialog.showToast('恢复失败，请检查 WebDAV 配置');
        return;
      }
    }
    try {
      _fileName ??= _getFileName();
      final path = '$_webdavDirectory/$_fileName';
      final data = await _client!.read(path);
      await GStorage.importAllSettings(utf8.decode(data));
      SmartDialog.showToast('恢复成功');
    } catch (e) {
      SmartDialog.showToast('恢复失败: $e');
    }
  }
}