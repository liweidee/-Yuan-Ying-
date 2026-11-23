// lib/modules/plugin_center/widgets/plugin_detail_sheet.dart

import 'package:flutter/material.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/controllers/plugin_center_controller.dart';
import 'package:yuanying/modules/plugin_center/models/market_entry.dart';

/// 展示插件详情，可带安装动作
/// [onInstall] 为空时只展示（不显示安装按钮）
Future<void> showPluginDetailSheet(
  BuildContext context, {
  required MarketEntry entry,
  required MarketInstallState installState,
  VoidCallback? onInstall,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PluginDetailSheet(
      entry: entry,
      installState: installState,
      onInstall: onInstall,
    ),
  );
}

class _PluginDetailSheet extends StatelessWidget {
  final MarketEntry entry;
  final MarketInstallState installState;
  final VoidCallback? onInstall;

  const _PluginDetailSheet({
    required this.entry,
    required this.installState,
    this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entry = this.entry;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: Style.bottomSheetRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: Style.mdRadius,
                  ),
                  child: Icon(
                    Icons.extension,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.author ?? ''} · v${entry.version}'
                        ' · ${entry.sizeText}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip(entry.type, colorScheme),
                      _chip(entry.category, colorScheme),
                      for (final t in entry.tags) _chip(t, colorScheme),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '详情',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.desc ?? '（无描述）',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  if (entry.changelog != null &&
                      entry.changelog!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '更新日志',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.changelog!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
                const Spacer(),
                if (onInstall != null) _buildActionButton(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (installState == MarketInstallState.unsupported) {
      return const FilledButton(
        onPressed: null,
        child: Text('当前平台不支持'),
      );
    }

    switch (installState) {
      case MarketInstallState.installed:
        if (_supportsReinstall) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(onPressed: null, child: const Text('已安装')),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _runInstall(context),
                child: const Text('重装'),
              ),
            ],
          );
        }
        return const FilledButton(
          onPressed: null,
          child: Text('已安装'),
        );

      case MarketInstallState.updatable:
        return FilledButton(
          onPressed: () => _runInstall(context),
          child: const Text('更新'),
        );

      case MarketInstallState.notInstalled:
        return FilledButton(
          onPressed: () => _runInstall(context),
          child: Text(entry.type == 'live' ? '导入' : '安装'),
        );

      case MarketInstallState.unsupported:
        return const FilledButton(
          onPressed: null,
          child: Text('当前平台不支持'),
        );
    }
  }

  bool get _supportsReinstall => entry.type == 'source' || entry.type == 'live';

  void _runInstall(BuildContext context) {
    Navigator.pop(context);
    onInstall?.call();
  }

  Widget _chip(String text, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: colorScheme.outline),
      ),
    );
  }
}
