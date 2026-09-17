import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/network_media/widgets/network_main_shell.dart';

import '../controllers/ftp_download_controller.dart';
import '../controllers/ftp_file_controller.dart';
import '../controllers/ftp_server_controller.dart';
import 'ftp_download_page.dart';
import 'ftp_file_page.dart';

class FtpMainShell extends StatelessWidget {
  const FtpMainShell({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<FtpServerController>()) {
      Get.put(FtpServerController());
    }
    if (!Get.isRegistered<FtpFileController>()) {
      Get.put(FtpFileController());
    }
    if (!Get.isRegistered<FtpDownloadController>()) {
      Get.put(FtpDownloadController());
    }
    final args = Get.arguments;
    if (args is Map && args['serverId'] is String) {
      final id = args['serverId'] as String;
      Get.find<FtpServerController>().selectServer(id);
      Get.find<FtpFileController>().refresh();
    }
    final server = Get.find<FtpServerController>().current;
    final title = server?.name ?? 'FTP/SFTP';

    return NetworkMainShell(
      title: title,
      filePage: const FtpFilePage(),
      downloadPage: const FtpDownloadPage(),
    );
  }
}