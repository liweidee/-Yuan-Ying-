import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../widgets/alist_file_info_dialog.dart';

class AlistFileReaderPage extends StatelessWidget {
  const AlistFileReaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments as Map? ?? {};
    final name = args['name'] as String? ?? '';
    final path = args['path'] as String? ?? '';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      AlistFileInfoDialog.show(
        context,
        name: name,
        path: path,
      );
    });

    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}