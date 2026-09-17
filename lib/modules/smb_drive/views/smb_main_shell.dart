import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/network_media/widgets/network_main_shell.dart';

import '../controllers/smb_download_controller.dart';
import '../controllers/smb_file_controller.dart';
import '../controllers/smb_server_controller.dart';
import 'smb_download_page.dart';
import 'smb_file_page.dart';

class SmbMainShell extends StatelessWidget {
  const SmbMainShell({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SmbServerController>()) {
      Get.put(SmbServerController());
    }
    if (!Get.isRegistered<SmbFileController>()) {
      Get.put(SmbFileController());
    }
    if (!Get.isRegistered<SmbDownloadController>()) {
      Get.put(SmbDownloadController());
    }
    final args = Get.arguments;
    if (args is Map && args['serverId'] is String) {
      final id = args['serverId'] as String;
      Get.find<SmbServerController>().selectServer(id);
      Get.find<SmbFileController>().refresh();
    }
    final server = Get.find<SmbServerController>().current;
    final title = server?.name ?? 'SMB / NAS';

    return NetworkMainShell(
      title: title,
      filePage: const SmbFilePage(),
      downloadPage: const SmbDownloadPage(),
    );
  }
}