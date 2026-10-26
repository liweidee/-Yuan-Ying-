// lib/modules/py_source/widgets/reset_meta_dialog.dart

import 'package:flutter/material.dart';

import 'package:yuanying/core/theme/style.dart';

Future<bool?> showResetMetaDialog(BuildContext context, int count) async {
  final colorScheme = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: const Text('重置元数据',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: Text(
        '将重读所选 $count 个本地源文件的 @header，'
        '按文件头重新应用名称/可搜索/可快搜/可筛选/类型/图标（ext 保留），确定继续？',
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('重置'),
        ),
      ],
    ),
  );
}