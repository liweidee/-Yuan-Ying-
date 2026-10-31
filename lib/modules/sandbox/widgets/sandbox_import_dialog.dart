// lib/modules/sandbox/widgets/sandbox_import_dialog.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/sandbox/models/sandbox_service.dart';
import 'package:yuanying/modules/sandbox/services/project_detector.dart';

/// 从本地目录导入项目为沙盒服务
Future<SandboxService?> showSandboxImportDialog(
  BuildContext context, {
  required String distroId,
}) {
  return showDialog<SandboxService>(
    context: context,
    builder: (_) => _SandboxImportDialog(distroId: distroId),
  );
}

class _SandboxImportDialog extends StatefulWidget {
  final String distroId;
  const _SandboxImportDialog({required this.distroId});

  @override
  State<_SandboxImportDialog> createState() => _SandboxImportDialogState();
}

class _SandboxImportDialogState extends State<_SandboxImportDialog> {
  bool _picking = false;
  bool _detecting = false;
  ProjectInfo? _info;
  String? _error;

  Future<void> _pickAndDetect() async {
    setState(() {
      _picking = true;
      _error = null;
      _info = null;
    });
    try {
      final dir = await FilePicker.getDirectoryPath();
      if (dir == null || dir.isEmpty) {
        setState(() => _picking = false);
        return;
      }
      setState(() {
        _picking = false;
        _detecting = true;
      });
      final info = await ProjectDetector.detect(dir);
      if (!mounted) return;
      setState(() {
        _info = info;
        _detecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _detecting = false;
        _picking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: const Text(
        '导入项目为沙盒服务',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择设备存储中的项目目录（如 /storage/emulated/0/myapp）。'
                '自动识别 Node.js / Python / PHP 项目并生成启动命令。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),

              // 选目录按钮
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_picking || _detecting) ? null : _pickAndDetect,
                  icon: _detecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open, size: 18),
                  label: Text(
                    _detecting ? '识别中…' : '选择项目目录',
                  ),
                ),
              ),

              // 错误
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: Style.mdRadius,
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.error,
                      height: 1.5,
                    ),
                  ),
                ),
              ],

              // 识别结果
              if (_info != null) ...[
                const SizedBox(height: 16),
                _infoCard(_info!, colorScheme),
              ],
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
          onPressed: _info == null ? null : () => _save(context),
          child: const Text('创建服务'),
        ),
      ],
    );
  }

  Widget _infoCard(ProjectInfo info, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: Style.mdRadius,
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle,
                  size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '识别结果：${info.type.label} 项目',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _kv('宿主目录', info.hostDir, colorScheme),
          _kv('沙盒路径', info.sandboxDir, colorScheme),
          if (info.entryFile != null)
            _kv('入口文件', info.entryFile!, colorScheme),
          if (info.port != null) _kv('端口', '${info.port}', colorScheme),
          if (info.installCommand != null)
            _kv('依赖安装', info.installCommand!, colorScheme),
          const SizedBox(height: 4),
          _kv('启动命令', info.startCommand, colorScheme, mono: true),

          if (info.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: info.warnings
                    .map((w) => Text(
                          '· $w',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade800,
                            height: 1.5,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],

          if (info.installCommand != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '提示：首次启动前建议先在沙盒终端执行依赖安装命令：\n'
                '${info.installCommand}',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v, ColorScheme colorScheme, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              k,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface,
                fontFamily: mono ? 'monospace' : null,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _save(BuildContext context) {
    final info = _info;
    if (info == null) return;

    final name = info.hostDir.split('/').last;
    final service = SandboxService(
      id: 'sbx-${DateTime.now().millisecondsSinceEpoch}',
      name: name.isEmpty ? 'imported-app' : name,
      command: info.startCommand,
      port: info.port,
      remark: '${info.type.label} 项目（${info.hostDir}）',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      autostart: false,
    );
    Navigator.pop(context, service);
  }
}