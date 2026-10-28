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

  /// 本地文件路径列表
  /// - T4：null
  /// - HTML：1~N 个（.web.json / .html / .js 混合）
  /// - 其他类型：1 个
  final List<String>? localFilePaths;

  final int searchable;
  final int filterable;
  final int quickSearch;
  final String ext;

  ManualSourceEditResult({
    required this.type,
    required this.name,
    required this.api,
    required this.localFilePaths,
    required this.searchable,
    required this.filterable,
    required this.quickSearch,
    required this.ext,
  });
}

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

  String? pickedSinglePath;
  final List<String> pickedMultiPaths = [];

  return showDialog<ManualSourceEditResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final isT4 = selectedType == ManualSourceType.t4;
        final isFileSource = !isT4;
        final isMulti = selectedType.isMultiFile;
        // HTML 不参与搜索/筛选，也不需要名称输入
        final isHtml = selectedType == ManualSourceType.html;
        final fileLock = !isAdd && existing != null && existing.type.isFileBased;

        final canSubmit = () {
          if (fileLock) return true;
          if (isT4) {
            return nameCtrl.text.trim().isNotEmpty &&
                apiCtrl.text.trim().isNotEmpty;
          }
          if (isMulti) {
            final hasMain = pickedMultiPaths.any((p) {
              final l = p.toLowerCase();
              return l.endsWith('.web.json') || l.endsWith('.html');
            });
            return hasMain;
          }
          return pickedSinglePath != null && pickedSinglePath!.isNotEmpty;
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
                          pickedSinglePath = null;
                          pickedMultiPaths.clear();
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

                  // ===== HTML 类型：多选文件（无名称、无开关） =====
                  if (isMulti && isAdd) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final List<PlatformFile> files =
                            await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['html', 'json', 'js'],
                        );
                        if (files.isEmpty) return;
                        final paths = files
                            .map((f) => f.path)
                            .whereType<String>()
                            .where((p) => p.isNotEmpty)
                            .toList();
                        if (paths.isEmpty) return;
                        if (paths.length > 5) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('最多选择 5 个文件')),
                          );
                          return;
                        }
                        setState(() {
                          pickedMultiPaths
                            ..clear()
                            ..addAll(paths);
                          // 不再需要填 nameCtrl
                        });
                      },
                      icon: const Icon(Icons.file_open, size: 18),
                      label: Text(
                        pickedMultiPaths.isEmpty
                            ? '选择文件（.html / .web.json / .js，可多选）'
                            : '重新选择（已选 ${pickedMultiPaths.length}）',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (pickedMultiPaths.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: pickedMultiPaths.map((path) {
                            final fileName =
                                File(path).uri.pathSegments.last;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle,
                                      size: 14, color: colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      fileName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        '需要至少一个 .web.json 或 .html 主文件；.js 为可选增强脚本。\n显示名自动读取：.web.json 用其 name 字段，.html 用文件名',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ★ HTML 类型不显示名称输入框、不显示三个开关
                  ],

                  // ===== 其他文件类型：单文件选择 + 三个开关 =====
                  if (isFileSource && isAdd && !isMulti) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.pickFile(
                          type: FileType.custom,
                          allowedExtensions: [selectedType.ext],
                        );
                        if (picked == null || picked.path == null) return;
                        setState(() {
                          pickedSinglePath = picked.path;
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
                        pickedSinglePath == null
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
                    if (pickedSinglePath != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 16, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                pickedSinglePath!,
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

                  // ===== 编辑模式：显示当前路径 =====
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

                  // ===== 三个开关（仅非 HTML 类型） =====
                  if (!isHtml) ...[
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
                      // HTML 类型：三个开关固定为 0（不参与搜索/筛选）
                      final finalSearchable =
                          isHtml ? 0 : (searchable ? 1 : 0);
                      final finalFilterable =
                          isHtml ? 0 : (filterable ? 1 : 0);
                      final finalQuickSearch =
                          isHtml ? 0 : (quickSearch ? 1 : 0);

                      // name：HTML 类型从文件自动派生；其他类型用 nameCtrl
                      final computedName = fileLock
                          ? existing.name
                          : (isT4
                              ? nameCtrl.text.trim()
                              : isHtml
                                  ? _autoNameFor(pickedMultiPaths)
                                  : (nameCtrl.text.trim().isEmpty
                                      ? _autoNameFor([pickedSinglePath!])
                                      : nameCtrl.text.trim()));

                      Navigator.pop(
                        ctx,
                        ManualSourceEditResult(
                          type: selectedType,
                          name: computedName,
                          api: fileLock
                              ? existing.path
                              : (isT4 ? apiCtrl.text.trim() : ''),
                          localFilePaths: fileLock
                              ? null
                              : (isMulti
                                  ? List<String>.from(pickedMultiPaths)
                                  : (pickedSinglePath != null
                                      ? [pickedSinglePath!]
                                      : null)),
                          searchable: finalSearchable,
                          filterable: finalFilterable,
                          quickSearch: finalQuickSearch,
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

// ===== 辅助方法 =====

String? _findMainFile(List<String> paths) {
  for (final p in paths) {
    if (p.toLowerCase().endsWith('.web.json')) return p;
  }
  for (final p in paths) {
    if (p.toLowerCase().endsWith('.html')) return p;
  }
  return paths.isNotEmpty ? paths.first : null;
}

String _extractBaseName(String path) {
  final name = File(path).uri.pathSegments.last;
  final lower = name.toLowerCase();
  if (lower.endsWith('.web.json')) {
    return name.substring(0, name.length - '.web.json'.length);
  }
  final dot = name.lastIndexOf('.');
  if (dot > 0) return name.substring(0, dot);
  return name;
}

String _autoNameFor(List<String> paths) {
  if (paths.isEmpty) return '';
  final main = _findMainFile(paths);
  if (main == null) return '';
  final base = _extractBaseName(main);
  return base.isEmpty ? File(main).uri.pathSegments.last : base;
}