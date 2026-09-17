import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:yuanying/services/backup/backup_category.dart';
import 'package:yuanying/services/backup/backup_manifest.dart';
import 'package:yuanying/services/backup/backup_registry.dart';
import 'package:yuanying/services/backup/backup_service.dart';
import 'package:yuanying/utils/storage_utils.dart';

/// 打开「备份与恢复」对话框
Future<void> showBackupDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => const _BackupDialog(),
  );
}

class _BackupDialog extends StatefulWidget {
  const _BackupDialog();

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  /// 0 = 导出，1 = 导入
  int _tabIndex = 0;

  // ---------- 导出 ----------
  final Set<BackupCategory> _exportSelected = {...BackupCategory.values};
  bool _exporting = false;

  // ---------- 导入 ----------
  Uint8List? _importBytes;
  BackupManifest? _importManifest;
  final Set<BackupCategory> _importSelected = {};
  bool _importing = false;
  String? _importError;

  bool get _busy => _exporting || _importing;

  // ============================================================
  // 导出
  // ============================================================
  Future<void> _doExport() async {
    if (_exportSelected.isEmpty) {
      SmartDialog.showToast('请至少选择一个分类');
      return;
    }
    setState(() => _exporting = true);
    try {
      final result = await BackupService.export(categories: _exportSelected);
      if (!mounted) return;
      if (!result.success || result.zipBytes == null) {
        SmartDialog.showToast(result.error ?? '导出失败');
        return;
      }
      final name =
          'yuanying_backup_${DateFormat('yyyyMMddHHmmss').format(DateTime.now())}.zip';
      await StorageUtils.saveBytes2File(name: name, bytes: result.zipBytes!);
      if (!mounted) return;
      Get.back();
      if (result.warnings.isNotEmpty) {
        SmartDialog.showToast('导出完成（${result.warnings.length} 条警告）');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ============================================================
  // 导入：选择文件
  // ============================================================
  Future<void> _pickImportFile() async {
    setState(() => _importError = null);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (picked == null) return;
      final bytes = await picked.xFile.readAsBytes();
      final preview = BackupService.preview(bytes);
      if (!preview.success || preview.manifest == null) {
        setState(() {
          _importBytes = null;
          _importManifest = null;
          _importError = preview.error ?? '解析失败';
        });
        return;
      }
      setState(() {
        _importBytes = bytes;
        _importManifest = preview.manifest;
        _importSelected
          ..clear()
          ..addAll(preview.manifest!.categories);
        _importError = null;
      });
    } catch (e) {
      setState(() {
        _importError = '读取文件失败：$e';
        _importBytes = null;
        _importManifest = null;
      });
    }
  }

  // ============================================================
  // 导入：执行
  // ============================================================
  Future<void> _doImport() async {
    if (_importBytes == null || _importManifest == null) return;
    if (_importSelected.isEmpty) {
      SmartDialog.showToast('请至少选择一个分类');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入？'),
        content: const Text('导入将覆盖所选分类的现有数据，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _importing = true);
    try {
      final result = await BackupService.import(
        _importBytes!,
        categories: _importSelected,
      );
      if (!mounted) return;
      if (!result.success) {
        SmartDialog.showToast(result.error ?? '导入失败');
        return;
      }
      Get.back();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('导入完成'),
          content: const Text('已恢复配置。\n\n部分设置需要重启应用才能生效。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      if (result.warnings.isNotEmpty) {
        SmartDialog.showToast('导入完成（${result.warnings.length} 条警告）');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ============================================================
  // UI 主结构
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme),
            _buildSegmented(theme),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 4),
                child: _tabIndex == 0
                    ? _buildExportContent(theme)
                    : _buildImportContent(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 头部
  // ============================================================
  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 10, 4),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '备份与恢复',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 分段控件
  // ============================================================
  Widget _buildSegmented(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _buildSegmentButton(theme, '导出', 0),
          _buildSegmentButton(theme, '导入', 1),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(ThemeData theme, String label, int index) {
    final selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 导出内容
  // ============================================================
  Widget _buildExportContent(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final category in BackupCategory.values)
          _buildCategoryCard(
            theme: theme,
            category: category,
            selected: _exportSelected.contains(category),
            moduleNames: BackupRegistry.byCategory(category)
                .map((e) => e.displayName)
                .toList(),
            onToggle: (v) {
              setState(() {
                if (v) {
                  _exportSelected.add(category);
                } else {
                  _exportSelected.remove(category);
                }
              });
            },
          ),
        const SizedBox(height: 8),
        _buildActionButton(
          theme: theme,
          label: '导出为 ZIP',
          icon: Icons.archive_outlined,
          busy: _exporting,
          onPressed: _doExport,
        ),
      ],
    );
  }

  // ============================================================
  // 导入内容
  // ============================================================
  Widget _buildImportContent(ThemeData theme) {
    final manifest = _importManifest;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 错误提示
        if (_importError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _importError!,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 选择文件
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: SizedBox(
            width: double.infinity,
            height: 36,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickImportFile,
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(
                manifest == null ? '选择 ZIP 文件' : '重新选择文件',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        ),

        // 文件信息 + 分类
        if (manifest != null) ...[
          _buildFileInfoCard(theme, manifest),
          const SizedBox(height: 8),
          for (final category in BackupCategory.values)
            if (manifest.categories.contains(category))
              _buildCategoryCard(
                theme: theme,
                category: category,
                selected: _importSelected.contains(category),
                moduleNames: manifest.boxes
                    .where((b) => b.category == category)
                    .map((b) =>
                        BackupRegistry.byName(b.name)?.displayName ?? b.name)
                    .toList(),
                onToggle: (v) {
                  setState(() {
                    if (v) {
                      _importSelected.add(category);
                    } else {
                      _importSelected.remove(category);
                    }
                  });
                },
              ),
        ],

        const SizedBox(height: 8),
        _buildActionButton(
          theme: theme,
          label: '开始导入',
          icon: Icons.restore,
          busy: _importing,
          onPressed: manifest == null ? null : _doImport,
        ),
      ],
    );
  }

  // ============================================================
  // 底部主按钮
  // ============================================================
  Widget _buildActionButton({
    required ThemeData theme,
    required String label,
    required IconData icon,
    required bool busy,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: SizedBox(
        width: double.infinity,
        height: 36,
        child: FilledButton.icon(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 16),
          label: Text(busy ? '处理中...' : label),
        ),
      ),
    );
  }

  // ============================================================
  // 分类选项（纯列表样式：只有复选框 + 图标 + 文案，无背景无边框）
  // ============================================================
  Widget _buildCategoryCard({
    required ThemeData theme,
    required BackupCategory category,
    required bool selected,
    required List<String> moduleNames,
    required ValueChanged<bool> onToggle,
  }) {
    final disabled = _busy;
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: disabled ? null : () => onToggle(!selected),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              // ===== 左侧方形复选框 =====
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: selected ? primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: selected
                        ? primary
                        : theme.colorScheme.outline.withValues(alpha: 0.6),
                    width: 1.8,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check,
                        size: 14,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // ===== 图标 =====
              Icon(
                _categoryIcon(category),
                size: 18,
                color: selected ? primary : theme.colorScheme.outline,
              ),
              const SizedBox(width: 10),

              // ===== 标题 + 模块名 =====
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      category.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (moduleNames.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          moduleNames.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(BackupCategory category) {
    switch (category) {
      case BackupCategory.settings:
        return Icons.tune;
      case BackupCategory.media:
        return Icons.bookmark_outline;
      case BackupCategory.sources:
        return Icons.rss_feed;
    }
  }

  // ============================================================
  // 文件信息卡片（导入预览）
  // ============================================================
  Widget _buildFileInfoCard(ThemeData theme, BackupManifest manifest) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '备份文件',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${manifest.totalCount} 项 · ${_formatBytes(manifest.totalBytes)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _infoChip(theme, Icons.info_outline, 'v${manifest.appVersion}'),
                const SizedBox(width: 6),
                _infoChip(
                  theme,
                  Icons.access_time,
                  DateFormat('yyyy-MM-dd HH:mm').format(manifest.exportedAt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(ThemeData theme, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}