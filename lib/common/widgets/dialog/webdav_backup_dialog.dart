import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:yuanying/modules/webdav/controllers/webdav_controller.dart';
import 'package:yuanying/services/backup/backup_category.dart';
import 'package:yuanying/services/backup/backup_manifest.dart';
import 'package:yuanying/services/backup/backup_registry.dart';
import 'package:yuanying/services/backup/backup_service.dart';

/// 打开「WebDAV 备份与恢复」对话框
///
/// [controller] 内部会自动调用 `init()` 确保连接可用
/// [initialMode] 0 = 上传，1 = 恢复
Future<void> showWebDavBackupDialog(
  BuildContext context, {
  required WebDavController controller,
  int initialMode = 0,
}) {
  return showDialog(
    context: context,
    builder: (_) => _WebDavBackupDialog(
      controller: controller,
      initialMode: initialMode,
    ),
  );
}

class _WebDavBackupDialog extends StatefulWidget {
  final WebDavController controller;
  final int initialMode;

  const _WebDavBackupDialog({
    required this.controller,
    required this.initialMode,
  });

  @override
  State<_WebDavBackupDialog> createState() => _WebDavBackupDialogState();
}

class _WebDavBackupDialogState extends State<_WebDavBackupDialog> {
  late int _tabIndex = widget.initialMode;

  // ---------- 上传 ----------
  final Set<BackupCategory> _uploadSelected = {...BackupCategory.values};
  bool _uploading = false;

  // ---------- 恢复 ----------
  BackupManifest? _remoteManifest;
  Uint8List? _remoteBytes;
  final Set<BackupCategory> _restoreSelected = {};
  bool _restoring = false;
  bool _fetching = false;
  String? _error;

  bool get _busy => _uploading || _restoring || _fetching;

  // ============================================================
  // 上传
  // ============================================================
  Future<void> _doUpload() async {
    if (_uploadSelected.isEmpty) {
      SmartDialog.showToast('请至少选择一个分类');
      return;
    }
    setState(() => _uploading = true);
    try {
      final result = await BackupService.export(categories: _uploadSelected);
      if (!mounted) return;
      if (!result.success || result.zipBytes == null) {
        SmartDialog.showToast(result.error ?? '打包失败');
        return;
      }
      final ok = await widget.controller.uploadBackup(result.zipBytes!);
      if (!mounted) return;
      if (!ok) {
        SmartDialog.showToast('上传失败，请检查 WebDAV 配置');
        return;
      }
      Get.back();
      SmartDialog.showToast('上传成功');
      if (result.warnings.isNotEmpty) {
        SmartDialog.showToast('导出完成（${result.warnings.length} 条警告）');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ============================================================
  // 拉取云端备份并预览
  // ============================================================
  Future<void> _fetchRemote() async {
    setState(() {
      _error = null;
      _fetching = true;
      _remoteBytes = null;
      _remoteManifest = null;
    });
    try {
      final bytes = await widget.controller.downloadBackup();
      if (!mounted) return;
      if (bytes == null) {
        setState(() {
          _error = '云端无备份文件或下载失败';
          _fetching = false;
        });
        return;
      }
      final preview = BackupService.preview(bytes);
      if (!mounted) return;
      if (!preview.success || preview.manifest == null) {
        setState(() {
          _error = preview.error ?? '文件解析失败';
          _fetching = false;
        });
        return;
      }
      setState(() {
        _remoteBytes = bytes;
        _remoteManifest = preview.manifest;
        _restoreSelected
          ..clear()
          ..addAll(preview.manifest!.categories);
        _fetching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '下载失败：$e';
        _fetching = false;
      });
    }
  }

  // ============================================================
  // 恢复（执行导入）
  // ============================================================
  Future<void> _doRestore() async {
    if (_remoteBytes == null || _remoteManifest == null) return;
    if (_restoreSelected.isEmpty) {
      SmartDialog.showToast('请至少选择一个分类');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复？'),
        content: const Text('恢复将覆盖所选分类的现有数据，此操作不可撤销。'),
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

    setState(() => _restoring = true);
    try {
      final result = await BackupService.import(
        _remoteBytes!,
        categories: _restoreSelected,
      );
      if (!mounted) return;
      if (!result.success) {
        SmartDialog.showToast(result.error ?? '恢复失败');
        return;
      }
      Get.back();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('恢复完成'),
          content: const Text('已从 WebDAV 恢复配置。\n\n部分设置需要重启应用才能生效。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      if (result.warnings.isNotEmpty) {
        SmartDialog.showToast('恢复完成（${result.warnings.length} 条警告）');
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  // ============================================================
  // UI
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
                    ? _buildUploadContent(theme)
                    : _buildRestoreContent(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 10, 4),
      child: Row(
        children: [
          Icon(
            Icons.cloud_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'WebDAV 备份',
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
          _buildSegmentButton(theme, '上传', 0),
          _buildSegmentButton(theme, '恢复', 1),
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
  // 上传 Tab
  // ============================================================
  Widget _buildUploadContent(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final category in BackupCategory.values)
          _buildCategoryTile(
            theme: theme,
            category: category,
            selected: _uploadSelected.contains(category),
            moduleNames: BackupRegistry.byCategory(category)
                .map((e) => e.displayName)
                .toList(),
            onToggle: (v) {
              setState(() {
                if (v) {
                  _uploadSelected.add(category);
                } else {
                  _uploadSelected.remove(category);
                }
              });
            },
          ),
        const SizedBox(height: 8),
        _buildActionButton(
          theme: theme,
          label: '上传到 WebDAV',
          icon: Icons.cloud_upload_outlined,
          busy: _uploading,
          onPressed: _doUpload,
        ),
      ],
    );
  }

  // ============================================================
  // 恢复 Tab
  // ============================================================
  Widget _buildRestoreContent(ThemeData theme) {
    final manifest = _remoteManifest;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: _buildErrorBox(theme, _error!),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: SizedBox(
            width: double.infinity,
            height: 36,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _fetchRemote,
              icon: _fetching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 16),
              label: Text(
                manifest == null ? '从 WebDAV 读取备份' : '重新读取',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        ),

        if (manifest != null) ...[
          _buildFileInfoCard(theme, manifest),
          const SizedBox(height: 8),
          for (final category in BackupCategory.values)
            if (manifest.categories.contains(category))
              _buildCategoryTile(
                theme: theme,
                category: category,
                selected: _restoreSelected.contains(category),
                moduleNames: manifest.boxes
                    .where((b) => b.category == category)
                    .map((b) =>
                        BackupRegistry.byName(b.name)?.displayName ?? b.name)
                    .toList(),
                onToggle: (v) {
                  setState(() {
                    if (v) {
                      _restoreSelected.add(category);
                    } else {
                      _restoreSelected.remove(category);
                    }
                  });
                },
              ),
        ],

        const SizedBox(height: 8),
        _buildActionButton(
          theme: theme,
          label: '从 WebDAV 恢复',
          icon: Icons.cloud_sync_outlined,
          busy: _restoring,
          onPressed: manifest == null ? null : _doRestore,
        ),
      ],
    );
  }

  // ============================================================
  // 通用小组件
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

  Widget _buildCategoryTile({
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
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Icon(
                _categoryIcon(category),
                size: 18,
                color: selected ? primary : theme.colorScheme.outline,
              ),
              const SizedBox(width: 10),
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
                  '云端备份',
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

  Widget _buildErrorBox(ThemeData theme, String msg) {
    return Container(
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
              msg,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
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