import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/network_media/widgets/network_main_shell.dart';
import '../controllers/webdav_download_controller.dart';
import '../controllers/webdav_file_controller.dart';
import '../controllers/webdav_server_controller.dart';
import 'webdav_download_page.dart';
import 'webdav_file_page.dart';

class WebDavMainShell extends StatelessWidget {
  const WebDavMainShell({super.key});

  @override
  Widget build(BuildContext context) {
    // 确保所有 controller 已注册
    if (!Get.isRegistered<WebDavServerController>()) {
      Get.put(WebDavServerController());
    }
    if (!Get.isRegistered<WebDavFileController>()) {
      Get.put(WebDavFileController());
    }
    if (!Get.isRegistered<WebDavDownloadController>()) {
      Get.put(WebDavDownloadController());
    }
    // 若从服务器列表跳转过来，切换到选中的服务器
    final args = Get.arguments;
    if (args is Map && args['serverId'] is String) {
      final id = args['serverId'] as String;
      Get.find<WebDavServerController>().selectServer(id);
      // 重新加载当前目录
      Get.find<WebDavFileController>().refresh();
    }
    final title = Get.find<WebDavServerController>().current?.name ?? 'WebDAV';

    return NetworkMainShell(
      title: title,
      filePage: const WebDavFilePage(),
      downloadPage: const WebDavDownloadPage(),
    );
  }
}