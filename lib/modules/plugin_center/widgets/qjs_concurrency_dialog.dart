// lib/modules/plugin_center/widgets/qjs_concurrency_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';

/// QJS 引擎并发设置弹窗
/// 只做 UI + 存储（extras['qjsConcurrency']），不改 qjs_ultra 引擎池
Future<void> showQjsConcurrencyDialog(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _QjsConcurrencyDialog(plugin: plugin),
  );
}

class _QjsConcurrencyDialog extends StatefulWidget {
  final InstalledPlugin plugin;

  const _QjsConcurrencyDialog({required this.plugin});

  @override
  State<_QjsConcurrencyDialog> createState() => _QjsConcurrencyDialogState();
}

class _QjsConcurrencyDialogState extends State<_QjsConcurrencyDialog> {
  late int _concurrency;

  @override
  void initState() {
    super.initState();
    final v = widget.plugin.extras['qjsConcurrency'];
    _concurrency = (v is int) ? v.clamp(1, 32) : 8;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: const Text(
        'qjs 引擎源并发',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 当前值
            Row(
              children: [
                Text(
                  '当前：',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '$_concurrency 路',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 说明
            Text(
              '作用于：聚合搜索并发 + 源检测引擎桶并发 + 引擎池常驻容量。\n'
              '参考：默认 8（qjs 真机压测 8/16 路存活，32 触崩溃边界）',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            // 滑块
            Row(
              children: [
                Text(
                  '1',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
                Expanded(
                  child: Slider(
                    value: _concurrency.toDouble(),
                    min: 1,
                    max: 32,
                    divisions: 31,
                    label: '$_concurrency',
                    onChanged: (v) =>
                        setState(() => _concurrency = v.round()),
                  ),
                ),
                Text(
                  '32',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
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
          onPressed: _save,
          child: const Text('确定'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final extras = Map<String, dynamic>.from(widget.plugin.extras);
    extras['qjsConcurrency'] = _concurrency;
    await InstallManager.instance.updateExtras(widget.plugin.id, extras);
    if (mounted) Navigator.pop(context);
    SmartDialog.showToast('已保存（$_concurrency 路）');
  }
}