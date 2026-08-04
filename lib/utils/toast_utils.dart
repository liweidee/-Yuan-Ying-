import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class ToastUtils {
  /// 靠底部、浅色主题色背景、大圆角、深色主题色文字
  static void show(
    String msg, {
    Duration displayTime = const Duration(milliseconds: 1500),
  }) {
    final context = Get.context;
    if (context == null) {
      SmartDialog.showToast(msg);
      return;
    }
    final colorScheme = ColorScheme.of(context);

    SmartDialog.show(
      maskColor: Colors.transparent,
      animationType: SmartAnimationType.fade,
      alignment: Alignment.bottomCenter,
      builder: (_) => Container(
        margin: const EdgeInsets.only(bottom: 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          msg,
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontSize: 14,
          ),
        ),
      ),
      displayTime: displayTime,
    );
  }
}