import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:yuanying/t4/services/source_manager.dart';

class SettingController extends GetxController {
  final SourceManager sourceManager = Get.find<SourceManager>();

  void goToSourceManage() {
    Get.toNamed('/sourceManage');
  }
}