// lib/modules/sandbox/widgets/software_source_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/sandbox/models/sandbox_pref.dart';
import 'package:yuanying/modules/sandbox/services/proot_launcher.dart';
import 'package:yuanying/modules/sandbox/services/rootfs_manager.dart';

/// 弹出软件源切换对话框，切换后自动刷新索引
///
/// 返回 true 表示切换并刷新成功
Future<bool> showSoftwareSourceDialog(
  BuildContext context, {
  required String distroId,
}) async {
  final sources = softwareSourcesFor(distroId);
  if (sources.isEmpty) {
    SmartDialog.showToast('当前发行版不支持切换软件源');
    return false;
  }

  final current = SandboxPref.softwareMirror;
  final selected = await showDialog<SoftwareSource>(
    context: context,
    builder: (_) => _SoftwareSourceDialog(
      distroId: distroId,
      sources: sources,
      currentId: current,
    ),
  );
  if (selected == null) return false;
  if (selected.id == current) {
    SmartDialog.showToast('已是当前软件源');
    return false;
  }

  // 切换 + 刷新
  SmartDialog.showLoading(msg: '切换中…');
  try {
    await RootfsManager.instance.applySoftwareSource(distroId, selected.id);

    // 刷新索引
    SmartDialog.showLoading(msg: '刷新软件索引…');
    final updateCmd = distroId == 'alpine'
        ? ['/bin/sh', '-c', 'apk update']
        : ['/bin/sh', '-c', 'apt update -y'];
    final result = await ProotLauncher.runOnce(
      distroId: distroId,
      command: updateCmd,
    );
    SmartDialog.dismiss();

    if (result.exitCode != 0) {
      SmartDialog.showToast('已切换到 ${selected.label}，但索引刷新失败，请稍后在终端手动执行 update');
      return true;
    }
    SmartDialog.showToast('已切换到 ${selected.label}，索引已刷新');
    return true;
  } catch (e) {
    SmartDialog.dismiss();
    SmartDialog.showToast('切换失败：$e');
    return false;
  }
}

class _SoftwareSourceDialog extends StatefulWidget {
  final String distroId;
  final List<SoftwareSource> sources;
  final String currentId;

  const _SoftwareSourceDialog({
    required this.distroId,
    required this.sources,
    required this.currentId,
  });

  @override
  State<_SoftwareSourceDialog> createState() => _SoftwareSourceDialogState();
}

class _SoftwareSourceDialogState extends State<_SoftwareSourceDialog> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentId;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAlpine = widget.distroId == 'alpine';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: const Text(
        '切换软件源',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAlpine
                  ? '影响 apk 装软件的速度。切换后会自动刷新软件索引。'
                  : '影响 apt 装软件的速度。切换后会自动刷新软件索引。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            ...widget.sources.map((s) => _buildOption(s, colorScheme)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final s = widget.sources.firstWhere((e) => e.id == _selected);
            Navigator.pop(context, s);
          },
          child: const Text('切换并刷新'),
        ),
      ],
    );
  }

  Widget _buildOption(SoftwareSource s, ColorScheme colorScheme) {
    final selected = _selected == s.id;
    return InkWell(
      borderRadius: Style.mdRadius,
      onTap: () => setState(() => _selected = s.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: Style.mdRadius,
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _iconFor(s.icon),
              size: 18,
              color: selected ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 18, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String key) {
    switch (key) {
      case 'aliyun':
        return Icons.cloud_circle;
      case 'tuna':
        return Icons.school;
      case 'huawei':
        return Icons.cloud;
      case 'official':
        return Icons.public;
      default:
        return Icons.dns_outlined;
    }
  }
}