import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/utils/storage_utils.dart';
import 'package:yuanying/utils/utils.dart';

/// 导出到剪贴板
void exportToClipBoard({
  required String Function() onExport,
}) {
  Utils.copyText(onExport());
}

/// 导出到本地文件
void exportToLocalFile({
  required String Function() onExport,
  required String Function() localFileName,
}) {
  final res = utf8.encode(onExport());
  StorageUtils.saveBytes2File(
    name:
        'yuanying_${localFileName()}_'
        '${DateFormat('yyyyMMddHHmmss').format(DateTime.now())}.json',
    bytes: Uint8List.fromList(res),
  );
}

/// 从本地文件导入
Future<void> importFromLocalFile<T>({
  required FutureOr<void> Function(T json) onImport,
  List<String> allowedExtensions = const ['json', 'txt'],
  FileType type = FileType.custom,
}) async {
  final result = await FilePicker.pickFile(
    type: type,
    allowedExtensions: allowedExtensions,
  );
  if (result != null) {
    try {
      final data = await result.xFile.readAsString();
      final T json = jsonDecode(data) as T;
      try {
        await onImport(json);
        SmartDialog.showToast('导入成功');
      } catch (e) {
        SmartDialog.showToast('导入失败：$e');
      }
    } catch (e) {
      SmartDialog.showToast('解析文件失败：$e');
    }
  }
}

/// 从剪贴板导入
Future<void> importFromClipBoard<T>(
  BuildContext context, {
  required String title,
  required String Function() onExport,
  required FutureOr<void> Function(T json) onImport,
  bool showConfirmDialog = true,
}) async {
  final data = await Clipboard.getData('text/plain');
  if (data?.text case final text? when (text.isNotEmpty)) {
    if (!context.mounted) return;

    try {
      final T json = jsonDecode(text) as T;
      final String formatText = Utils.jsonEncoder.convert(json);

      if (showConfirmDialog) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            final colorScheme = ColorScheme.of(context);
            return AlertDialog(
              title: Text('是否导入如下$title？'),
              content: SingleChildScrollView(
                child: Text(
                  formatText,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 15,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: Get.back,
                  child: Text(
                    '取消',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () => Get.back(result: true),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
        if (confirmed != true) return;
      }

      try {
        await onImport(json);
        SmartDialog.showToast('导入成功');
      } catch (e) {
        SmartDialog.showToast('导入失败：$e');
      }
    } catch (e) {
      SmartDialog.showToast('解析JSON失败：$e');
    }
  } else {
    SmartDialog.showToast('剪贴板无数据');
  }
}

/// 手动输入导入
void importFromInput<T>(
  BuildContext context, {
  required String title,
  required FutureOr<void> Function(T json) onImport,
}) {
  final key = GlobalKey<FormFieldState<String>>();
  late T json;
  String? forceErrorText;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('输入$title'),
      constraints: Style.dialogFixedConstraints,
      content: TextFormField(
        key: key,
        minLines: 4,
        maxLines: 12,
        autofocus: true,
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          errorMaxLines: 3,
          hintText: '请输入JSON数据',
          hintStyle: TextStyle(
            color: ColorScheme.of(context).outline.withValues(alpha: 0.5),
          ),
        ),
        validator: (value) {
          if (forceErrorText != null) return forceErrorText;
          try {
            json = jsonDecode(value!) as T;
            return null;
          } catch (e) {
            return '解析JSON失败：$e';
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(
              color: ColorScheme.of(context).outline,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            if (key.currentState?.validate() == true) {
              try {
                await onImport(json);
                Get.back();
                SmartDialog.showToast('导入成功');
                return;
              } catch (e) {
                forceErrorText = '导入失败：$e';
              }
              key.currentState?.validate();
              forceErrorText = null;
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 完整的导入/导出对话框
Future<void> showImportExportDialog<T>(
  BuildContext context, {
  required String title,
  required String Function() onExport,
  required FutureOr<void> Function(T json) onImport,
  required String Function() localFileName,
  List<String> importExtensions = const ['json', 'txt'],
}) {
  final colorScheme = ColorScheme.of(context);
  const itemStyle = TextStyle(fontSize: 15);

  return showDialog(
    context: context,
    builder: (context) => SimpleDialog(
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      backgroundColor: colorScheme.surface,
      title: Text(
        '导入/导出$title',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      children: [
        // 导出区域
        ListTile(
          dense: true,
          title: const Text('导出至剪贴板', style: itemStyle),
          onTap: () {
            Get.back();
            exportToClipBoard(onExport: onExport);
          },
        ),
        ListTile(
          dense: true,
          title: const Text('导出文件至本地', style: itemStyle),
          onTap: () {
            Get.back();
            exportToLocalFile(onExport: onExport, localFileName: localFileName);
          },
        ),
        Divider(
          height: 1,
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
        // 导入区域
        ListTile(
          dense: true,
          title: const Text('手动输入', style: itemStyle),
          onTap: () {
            Get.back();
            importFromInput<T>(context, title: title, onImport: onImport);
          },
        ),
        ListTile(
          dense: true,
          title: const Text('从剪贴板导入', style: itemStyle),
          onTap: () {
            Get.back();
            importFromClipBoard<T>(
              context,
              title: title,
              onExport: onExport,
              onImport: onImport,
            );
          },
        ),
        ListTile(
          dense: true,
          title: const Text('从本地文件导入', style: itemStyle),
          onTap: () {
            Get.back();
            importFromLocalFile<T>(
              onImport: onImport,
              allowedExtensions: importExtensions,
            );
          },
        ),
      ],
    ),
  );
}