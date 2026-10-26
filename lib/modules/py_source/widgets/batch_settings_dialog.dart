// lib/modules/py_source/widgets/batch_settings_dialog.dart

import 'package:flutter/material.dart';

import 'package:yuanying/core/theme/style.dart';

Future<({bool searchable, bool quickSearch, bool filterable})?>
    showBatchSettingsDialog(BuildContext context, int count) async {
  bool s = true, q = true, f = true;
  return showDialog<({bool searchable, bool quickSearch, bool filterable})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
          backgroundColor: colorScheme.surface,
          title: Text('批量设置 ($count 个源)',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('可搜索'),
                value: s,
                onChanged: (v) => setState(() => s = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('可快搜'),
                value: q,
                onChanged: (v) => setState(() => q = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('可筛选'),
                value: f,
                onChanged: (v) => setState(() => f = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                (searchable: s, quickSearch: q, filterable: f),
              ),
              child: const Text('应用'),
            ),
          ],
        );
      },
    ),
  );
}