// lib/modules/plugin_center/widgets/py_keep_alive_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/controllers/plugin_center_controller.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/t4/services/python_runtime.dart';

/// 打开 py 插件保活设置对话框
Future<void> showPyKeepAliveDialog(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _PyKeepAliveDialog(plugin: plugin),
  );
}

class _PyKeepAliveDialog extends StatefulWidget {
  final InstalledPlugin plugin;

  const _PyKeepAliveDialog({required this.plugin});

  @override
  State<_PyKeepAliveDialog> createState() => _PyKeepAliveDialogState();
}

class _PyKeepAliveDialogState extends State<_PyKeepAliveDialog> {
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.plugin.extras['pyKeepAlive'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: const Text(
        'py 引擎保活',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 当前状态
            Row(
              children: [
                Icon(
                  _enabled ? Icons.favorite : Icons.favorite_border,
                  size: 20,
                  color: _enabled ? colorScheme.primary : colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Text(
                  _enabled ? '已开启' : '已关闭',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _enabled ? colorScheme.primary : colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 开关
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '启用保活',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                '提升 py 插件进程优先级，减少被系统回收',
                style: TextStyle(fontSize: 12),
              ),
              value: _enabled,
              onChanged:
                  _saving ? null : (v) => setState(() => _enabled = v),
            ),

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: Style.mdRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        '作用',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '· 开启后 py 源响应更快（复用已初始化引擎状态）\n'
                    '· 代价：py 插件进程常驻内存（约 40-80MB）\n'
                    '· 低内存设备建议关闭\n'
                    '· 切换后立即生效，正在进行的请求可能中断一次',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final extras = Map<String, dynamic>.from(widget.plugin.extras);
      extras['pyKeepAlive'] = _enabled;
      await InstallManager.instance.updateExtras(widget.plugin.id, extras);
      await PythonRuntime.androidSetKeepAlive(_enabled);

      // 通知插件中心重载注册表，刷新卡片按钮状态
      if (Get.isRegistered<PluginCenterController>()) {
        Get.find<PluginCenterController>().reloadInstalled();
      }

      if (!mounted) return;
      Navigator.pop(context);
      SmartDialog.showToast(_enabled ? 'py 保活已开启' : 'py 保活已关闭');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SmartDialog.showToast('保存失败：$e');
    }
  }
}