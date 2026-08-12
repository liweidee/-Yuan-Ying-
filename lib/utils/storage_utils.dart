import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/utils/platform_utils.dart';

/// 存储工具类
abstract final class StorageUtils {
  /// 保存字节数据到本地文件
  /// [name] 文件名
  /// [bytes] 文件数据
  static Future<void> saveBytes2File({
    required String name,
    required Uint8List bytes,
  }) async {
    try {
      final path = await FilePicker.saveFile(
        fileName: name,
        bytes: PlatformUtils.isDesktop ? Uint8List(0) : bytes,
      );
      if (path == null) {
        SmartDialog.showToast("取消保存");
        return;
      }
      if (PlatformUtils.isDesktop) {
        await File(path).writeAsBytes(bytes);
      }
      SmartDialog.showToast("已保存");
    } catch (e) {
      SmartDialog.showToast("保存失败: $e");
    }
  }
}