// lib/modules/manual_source/widgets/manual_source_edit_dialog.dart

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:yuanying/core/theme/style.dart';
import '../models/manual_source_item.dart';

class ManualSourceEditResult {
  final ManualSourceType type;
  final String name;
  final String api;
  /// 本地文件路径（添加文件类型时非空，T4 时为 null）
  final String? localFilePath;
  final int searchable;
  final int filterable;
  final int quickSearch;
  final String ext;

  ManualSourceEditResult({
    required this.type,
    required this.name,
    required this.api,
    required this.localFilePath,
    required this.searchable,
    required this.filterable,
    required this.quickSearch,
    required this.ext,
  });
}

/// 统一编辑/添加对话框
/// - [existing] 为 null 时是「添加」模式
/// - [existing] 非空时是「编辑」模式
Future<ManualSourceEditResult?> showManualSourceEditDialog(
  BuildContext context, {
  ManualSourceItem? existing,
}) async {
  final isAdd = existing == null;

  ManualSourceType selectedType = existing?.type ?? ManualSourceType.py;
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final apiCtrl = TextEditingController(text: existing?.path ?? '');
  final extCtrl = TextEditingController(text: existing?.ext ?? '');
  bool searchable = (existing?.searchable ?? 1) == 1;
  bool quickSearch = (existing?.quickSearch ?? 1) == 1;
  bool filterable = (existing?.filterable ?? 1) == 1;

  // 添加模式下已选文件路径
  String? pickedFilePath;

  return showDialog<ManualSourceEditResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final isT4 = selectedType == ManualSourceType.t4;
        final isFileSource = !isT4;
        final fileLock = !isAdd && existing != null && existing.type.isFileBased;

        // 添加模式下，文件类型必须已选文件才能提交
        final canSubmit = () {
          if (fileLock) return true; // 编辑文件源，不用选文件
          if (isT4) {
            return nameCtrl.text.trim().isNotEmpty && apiCtrl.text.trim().isNotEmpty;
          }
          // 添加文件类型：必须已选文件
          return pickedFilePath != null && pickedFilePath!.isNotEmpty;
        }();

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
          backgroundColor: colorScheme.surface,
          title: Text(
            isAdd ? '添加源' : '编辑 ${existing.name}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== 类型下拉（仅添加模式）=====
                  if (isAdd) ...[
                    DropdownButtonFormField<ManualSourceType>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: '源类型',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ManualSourceType.values.map((t) {
                        return DropdownMenuItem(
                          value: t,
                          child: Text(t.label),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          selectedType = v;
                          pickedFilePath = null;
                          nameCtrl.clear();
                          if (v == ManualSourceType.t4) {
                            apiCtrl.clear();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ===== T4：名称 + URL =====
                  if (isT4) ...[
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '源名称',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiCtrl,
                      decoration: const InputDecoration(
                        labelText: '接口 URL',
                        hintText: 'http://example.com/t4',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ===== 文件类型：选择文件（添加模式）=====
                  if (isFileSource && isAdd) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.pickFile(
                          type: FileType.custom,
                          allowedExtensions: [selectedType.ext],
                        );
                        if (picked == null || picked.path == null) return;
                        setState(() {
                          pickedFilePath = picked.path;
                          if (nameCtrl.text.trim().isEmpty) {
                            final base = File(picked.path!)
                                .uri
                                .pathSegments
                                .last
                                .replaceAll('.${selectedType.ext}', '');
                            nameCtrl.text = base;
                          }
                        });
                      },
                      icon: const Icon(Icons.file_open, size: 18),
                      label: Text(
                        pickedFilePath == null
                            ? '选择 .${selectedType.ext} 文件'
                            : '重新选择 .${selectedType.ext} 文件',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (pickedFilePath != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 16, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                pickedFilePath!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],

                  // ===== 文件类型：编辑模式显示当前路径 =====
                  if (isFileSource && !isAdd) ...[
                    TextField(
                      controller: apiCtrl,
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: '文件路径（不可修改）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ===== 三个开关 =====
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

                  // ===== ext =====
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
              onPressed: canSubmit
                  ? () {
                      Navigator.pop(
                        ctx,
                        ManualSourceEditResult(
                          type: selectedType,
                          name: fileLock
                              ? existing.name
                              : (isT4
                                  ? nameCtrl.text.trim()
                                  : (nameCtrl.text.trim().isEmpty
                                      ? File(pickedFilePath!)
                                          .uri
                                          .pathSegments
                                          .last
                                          .replaceAll('.${selectedType.ext}', '')
                                      : nameCtrl.text.trim())),
                          api: fileLock
                              ? existing.path
                              : (isT4 ? apiCtrl.text.trim() : ''),
                          localFilePath: fileLock ? null : pickedFilePath,
                          searchable: searchable ? 1 : 0,
                          filterable: filterable ? 1 : 0,
                          quickSearch: quickSearch ? 1 : 0,
                          ext: extCtrl.text.trim(),
                        ),
                      );
                    }
                  : null,
              child: Text(isAdd ? '添加' : '保存'),
            ),
          ],
        );
      },
    ),
  );
}