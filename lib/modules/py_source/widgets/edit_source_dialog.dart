// lib/modules/py_source/widgets/edit_source_dialog.dart

import 'package:flutter/material.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/py_source/models/py_local_source.dart';

/// 返回 null=取消，否则返回更新后的 meta
Future<PySourceMeta?> showEditSourceDialog(
  BuildContext context,
  PyLocalSource s,
) async {
  final nameCtrl = TextEditingController(text: s.effectiveName);
  final extCtrl = TextEditingController(text: s.effectiveExt);
  bool searchable = s.effectiveSearchable == 1;
  bool quickSearch = s.effectiveQuickSearch == 1;
  bool filterable = s.effectiveFilterable == 1;

  return showDialog<PySourceMeta>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
          backgroundColor: colorScheme.surface,
          title: Text(
            '编辑 ${s.siteKey}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '源名称',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('可搜索'),
                    value: searchable,
                    onChanged: (v) => setState(() => searchable = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('可快搜'),
                    value: quickSearch,
                    onChanged: (v) => setState(() => quickSearch = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('可筛选'),
                    value: filterable,
                    onChanged: (v) => setState(() => filterable = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: extCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'ext 配置（选填，JSON 或字符串）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final meta = PySourceMeta(
                  name: nameCtrl.text.trim().isEmpty
                      ? s.name
                      : nameCtrl.text.trim(),
                  title: s.effectiveTitle,
                  searchable: searchable ? 1 : 0,
                  filterable: filterable ? 1 : 0,
                  quickSearch: quickSearch ? 1 : 0,
                  ext: extCtrl.text.trim().isEmpty ? null : extCtrl.text.trim(),
                );
                Navigator.pop(ctx, meta);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );
}