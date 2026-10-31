// lib/modules/sandbox/widgets/rootfs_mirror_picker_dialog.dart
import 'package:flutter/material.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/sandbox/models/sandbox_pref.dart';
import 'package:yuanying/modules/sandbox/services/rootfs_manager.dart';

/// 弹出下载源选择对话框。
///
/// 返回：
///  - `null`：用户取消
///  - `'auto'`：自动 fallback
///  - 镜像 label（如 `'清华'`）：只用该镜像
Future<String?> showRootfsMirrorPickerDialog(
  BuildContext context, {
  required DistroInfo distro,
}) async {
  // 上次选择作为默认
  final lastChoice = SandboxPref.downloadMirror;
  // 如果上次选择的 label 在当前 distro 里不存在（如上次选了"华为云"但现在是 Ubuntu），回退 auto
  final validLast = lastChoice == 'auto' ||
      distro.mirrors.any((m) => m.label == lastChoice);
  final initial = validLast ? lastChoice : 'auto';

  return showDialog<String>(
    context: context,
    builder: (_) => _RootfsMirrorPickerDialog(
      distro: distro,
      initialChoice: initial,
    ),
  );
}

class _RootfsMirrorPickerDialog extends StatefulWidget {
  final DistroInfo distro;
  final String initialChoice;

  const _RootfsMirrorPickerDialog({
    required this.distro,
    required this.initialChoice,
  });

  @override
  State<_RootfsMirrorPickerDialog> createState() =>
      _RootfsMirrorPickerDialogState();
}

class _RootfsMirrorPickerDialogState extends State<_RootfsMirrorPickerDialog> {
  late String _selected;
  bool _remember = true;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialChoice;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final distro = widget.distro;

    // 选项列表：auto 优先，然后是各镜像
    final options = <_MirrorOption>[
      _MirrorOption(
        id: 'auto',
        label: '自动（${distro.mirrors.map((m) => m.label).join(' → ')}）',
        subtitle: '智能降级重试，推荐',
        icon: Icons.auto_awesome,
      ),
      ...distro.mirrors.map((m) => _MirrorOption(
            id: m.label,
            label: '仅 ${m.label}',
            subtitle: _mirrorHint(m.label),
            icon: _mirrorIcon(m.label),
          )),
    ];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '下载镜像源 · ${distro.name} ${distro.version}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '海外官方源直连多数网络会 403/超时，推荐自动（国内镜像优先）',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...options.map((o) => _buildOption(o, colorScheme)),
            const SizedBox(height: 4),
            Row(
              children: [
                Checkbox(
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? false),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _remember = !_remember),
                    child: Text(
                      '记住选择（下次自动使用）',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            if (_remember) {
              await SandboxPref.setDownloadMirror(_selected);
            }
            if (context.mounted) {
              Navigator.pop(context, _selected);
            }
          },
          child: const Text('开始下载'),
        ),
      ],
    );
  }

  Widget _buildOption(_MirrorOption option, ColorScheme colorScheme) {
    final selected = _selected == option.id;
    return InkWell(
      borderRadius: Style.mdRadius,
      onTap: () => setState(() => _selected = option.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
              option.icon,
              size: 20,
              color: selected ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (option.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      option.subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 18, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  IconData _mirrorIcon(String label) {
    switch (label) {
      case '华为云':
        return Icons.cloud;
      case '清华':
        return Icons.school;
      case '官方':
        return Icons.public;
      default:
        return Icons.dns_outlined;
    }
  }

  String? _mirrorHint(String label) {
    switch (label) {
      case '华为云':
        return '国内，速度快';
      case '清华':
        return '国内高校源，稳定';
      case '官方':
        return '海外，需良好国际网络';
      default:
        return null;
    }
  }
}

class _MirrorOption {
  final String id;
  final String label;
  final String? subtitle;
  final IconData icon;

  _MirrorOption({
    required this.id,
    required this.label,
    this.subtitle,
    required this.icon,
  });
}