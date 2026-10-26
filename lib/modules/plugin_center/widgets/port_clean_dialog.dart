// lib/modules/plugin_center/widgets/port_clean_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/services/port_cleaner.dart';

Future<void> showPortCleanDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _PortCleanDialog(),
  );
}

class _PortCleanDialog extends StatefulWidget {
  const _PortCleanDialog();

  @override
  State<_PortCleanDialog> createState() => _PortCleanDialogState();
}

class _PortCleanDialogState extends State<_PortCleanDialog> {
  bool _scanning = true;
  List<PortOccupant> _occupants = [];
  bool _autoCleanEnabled = false;

  @override
  void initState() {
    super.initState();
    _autoCleanEnabled = PortCleaner.isAutoCleanEnabled();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final list = await PortCleaner.scan();
    if (!mounted) return;
    setState(() {
      _occupants = list;
      _scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final residual =
        _occupants.where((o) => o.type == PortOccupancyType.residual).toList();
    final running =
        _occupants.where((o) => o.type == PortOccupancyType.running).toList();
    final conflicts =
        _occupants.where((o) => o.type == PortOccupancyType.conflict).toList();
    final others =
        _occupants.where((o) => o.type == PortOccupancyType.others).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: const Text(
        '清理端口占用',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 480,
        child: _scanning
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '自动检测已添加服务的端口占用情况。'
                      '「清理残留」只清理「服务已停止但进程仍在」的残留进程，'
                      '不会影响正在运行的服务。',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_occupants.isEmpty)
                      _buildEmptyState(colorScheme)
                    else ...[
                      if (residual.isNotEmpty)
                        _buildGroup(
                          title: '残留进程（会被清理）',
                          subtitle: '服务已停止，但进程仍在占用端口',
                          color: colorScheme.error,
                          items: residual,
                        ),
                      if (running.isNotEmpty)
                        _buildGroup(
                          title: '运行中（不会被清理）',
                          subtitle: '服务正常，如需停止请到服务 Tab 操作',
                          color: Colors.green,
                          items: running,
                        ),
                      if (conflicts.isNotEmpty)
                        _buildGroup(
                          title: '端口冲突（不会被清理）',
                          subtitle: '端口被其他进程占用，需手动处理',
                          color: Colors.orange,
                          items: conflicts,
                        ),
                      if (others.isNotEmpty)
                        _buildGroup(
                          title: '其他应用占用（会被忽略）',
                          subtitle: '非插件中心启动的进程',
                          color: colorScheme.outline,
                          items: others,
                        ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '自动清理',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        Switch(
                          value: _autoCleanEnabled,
                          onChanged: (v) async {
                            await PortCleaner.setAutoCleanEnabled(v);
                            setState(() => _autoCleanEnabled = v);
                          },
                        ),
                      ],
                    ),
                    Text(
                      '开启后下次 App 启动时自动清理「残留进程」，不影响运行中的服务。',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
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
          onPressed: residual.isNotEmpty
              ? () async {
                  Navigator.pop(context);
                  final n = await PortCleaner.killAllOurs(_occupants);
                  SmartDialog.showToast('已清理 $n 个残留进程');
                }
              : null,
          child: const Text('清理残留'),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: Style.mdRadius,
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.check_circle_outline,
                size: 32, color: colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              '没有端口占用',
              style: TextStyle(fontSize: 13, color: colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup({
    required String title,
    required String subtitle,
    required Color color,
    required List<PortOccupant> items,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: Style.mdRadius,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.outline,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          ...items.map((o) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      o.type == PortOccupancyType.residual
                          ? Icons.warning_amber
                          : o.type == PortOccupancyType.running
                              ? Icons.check_circle_outline
                              : o.type == PortOccupancyType.conflict
                                  ? Icons.error_outline
                                  : Icons.info_outline,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '端口 ${o.port}（${o.serviceName}）'
                        '${o.processName != null ? ' · ${o.processName}' : ''}'
                        '${o.pid != null ? ' · PID ${o.pid}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}