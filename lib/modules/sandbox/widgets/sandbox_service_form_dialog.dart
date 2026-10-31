// lib/modules/sandbox/widgets/sandbox_service_form_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/sandbox/models/sandbox_service.dart';

Future<SandboxService?> showSandboxServiceFormDialog(
  BuildContext context, {
  SandboxService? existing,
}) {
  return showDialog<SandboxService>(
    context: context,
    builder: (_) => _SandboxServiceFormDialog(existing: existing),
  );
}

class _SandboxServiceFormDialog extends StatefulWidget {
  final SandboxService? existing;
  const _SandboxServiceFormDialog({this.existing});

  @override
  State<_SandboxServiceFormDialog> createState() =>
      _SandboxServiceFormDialogState();
}

class _SandboxServiceFormDialogState extends State<_SandboxServiceFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _cmdCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _remarkCtrl;
  late bool _autostart;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _cmdCtrl = TextEditingController(text: widget.existing?.command ?? '');
    _portCtrl =
        TextEditingController(text: widget.existing?.port?.toString() ?? '');
    _remarkCtrl = TextEditingController(text: widget.existing?.remark ?? '');
    _autostart = widget.existing?.autostart ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cmdCtrl.dispose();
    _portCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: Text(
        isEdit ? '编辑沙盒服务' : '添加沙盒服务',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '命令在沙盒内执行（先在终端里装好依赖），'
                '如 node /srv/app.js --port 5757',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '服务名称 *',
                  hintText: '如：my-node-api',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cmdCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '启动命令（沙盒内）*',
                  hintText: 'cd /srv && node app.js --port 5757',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '端口（选填，用于探活与打开 Web）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _remarkCtrl,
                decoration: const InputDecoration(
                  labelText: '备注（选填）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              // 自启动开关
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自启动',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text('App 冷启动时自动拉起',
                    style: TextStyle(fontSize: 12)),
                value: _autostart,
                onChanged: (v) => setState(() => _autostart = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? '保存' : '添加'),
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final cmd = _cmdCtrl.text.trim();
    if (name.isEmpty) {
      SmartDialog.showToast('请输入服务名称');
      return;
    }
    if (cmd.isEmpty) {
      SmartDialog.showToast('请输入启动命令');
      return;
    }
    int? port;
    if (_portCtrl.text.trim().isNotEmpty) {
      port = int.tryParse(_portCtrl.text.trim());
      if (port == null || port <= 0 || port > 65535) {
        SmartDialog.showToast('端口无效（1-65535）');
        return;
      }
    }
    final result = SandboxService(
      id: widget.existing?.id ??
          'sbx-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      command: cmd,
      port: port,
      remark:
          _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
      createdAtMs: widget.existing?.createdAtMs ??
          DateTime.now().millisecondsSinceEpoch,
      autostart: _autostart,
    );
    Navigator.pop(context, result);
  }
}