// lib/modules/plugin_center/widgets/plugin_detail_sheet.dart

import 'package:flutter/material.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/models/market_entry.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';

/// 展示插件详情，可带安装动作
/// [onInstall] 为空时只展示（不显示安装按钮）
Future<void> showPluginDetailSheet(
  BuildContext context, {
  required MarketEntry entry,
  VoidCallback? onInstall,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PluginDetailSheet(
      entry: entry,
      onInstall: onInstall,
    ),
  );
}

class _PluginDetailSheet extends StatefulWidget {
  final MarketEntry entry;
  final VoidCallback? onInstall;

  const _PluginDetailSheet({required this.entry, this.onInstall});

  @override
  State<_PluginDetailSheet> createState() => _PluginDetailSheetState();
}

class _PluginDetailSheetState extends State<_PluginDetailSheet> {
  Future<bool>? _installedFuture;

  @override
  void initState() {
    super.initState();
    _installedFuture = InstallManager.instance.isInstalled(widget.entry);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entry = widget.entry;

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
                if (widget.onInstall != null)
                  _buildActionButton(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!widget.entry.supportsWindows &&
        !widget.entry.supportsCurrentPlatform) {
      return const FilledButton(
        onPressed: null,
        child: Text('当前平台不支持'),
      );
    }

    return FutureBuilder<bool>(
      future: _installedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const FilledButton(
            onPressed: null,
            child: Text('检查中…'),
          );
        }
        final installed = snapshot.data ?? false;
        final reg = InstallManager.instance.findInstalled(widget.entry.id);
        final installedSameVersion =
            installed && reg != null && reg.version == widget.entry.version;
        final updatable =
            installed && reg != null && reg.version != widget.entry.version;

        if (installedSameVersion) {
          return const FilledButton(
            onPressed: null,
            child: Text('已安装'),
          );
        }

        if (updatable) {
          return FilledButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onInstall?.call();
            },
            child: const Text('更新'),
          );
        }

        return FilledButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onInstall?.call();
          },
          child: Text(widget.entry.type == 'live' ? '导入' : '安装'),
        );
      },
    );
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