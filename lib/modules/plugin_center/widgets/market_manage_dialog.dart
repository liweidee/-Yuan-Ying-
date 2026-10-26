// lib/modules/plugin_center/widgets/market_manage_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/controllers/plugin_center_controller.dart';
import 'package:yuanying/modules/plugin_center/models/market_source.dart';

Future<void> showMarketManageDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _MarketManageDialog(),
  );
}

/// 全局代理选项（所有市场源共用）
const _globalProxyOptions = <(String, String)>[
  ('直连', ''),
  ('gh-proxy.com', 'https://gh-proxy.com/'),
  ('gh-proxy.playdreamer.cn', 'https://gh-proxy.playdreamer.cn/'),
  ('github.catvod.com', 'https://github.catvod.com/'),
];

class _MarketManageDialog extends StatefulWidget {
  const _MarketManageDialog();

  @override
  State<_MarketManageDialog> createState() => _MarketManageDialogState();
}

class _MarketManageDialogState extends State<_MarketManageDialog> {
  late List<MarketSource> _sources;
  late String _globalProxy;
  final _controller = Get.find<PluginCenterController>();

  @override
  void initState() {
    super.initState();
    _sources = List.from(_controller.getSources());
    // 取第一个源的 proxy 作为全局代理（所有源共用）
    _globalProxy = _sources.isNotEmpty ? _sources.first.proxy : '';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: const Text(
        '管理市场',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '停用的市场不参与拉取与归并；删除仅移除列表项与缓存。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              ..._sources.map((s) => _buildSourceTile(s, colorScheme)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addSource,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加市场源'),
                ),
              ),
              const Divider(height: 24),
              Text(
                'GitHub 加速代理（作用于 GitHub 域直链）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _globalProxyOptions.map((opt) {
                  final label = opt.$1;
                  final value = opt.$2;
                  final selected = _globalProxy == value;
                  return _buildProxyChip(
                    label: label,
                    selected: selected,
                    onTap: () => setState(() => _globalProxy = value),
                  );
                }).toList()
                  ..add(
                    _buildProxyChip(
                      label: '自定义...',
                      selected: _globalProxy.isNotEmpty &&
                          !_globalProxyOptions.any((o) => o.$2 == _globalProxy),
                      onTap: _showCustomProxyDialog,
                    ),
                  ),
              ),
              if (_globalProxy.isNotEmpty &&
                  !_globalProxyOptions.any((o) => o.$2 == _globalProxy)) ...[
                const SizedBox(height: 8),
                Text(
                  '自定义：$_globalProxy',
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
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
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildSourceTile(MarketSource source, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: Style.mdRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  source.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                value: source.enabled,
                onChanged: (v) {
                  setState(() {
                    final i = _sources.indexWhere((e) => e.id == source.id);
                    if (i >= 0) {
                      _sources[i] = _sources[i].copyWith(enabled: v);
                    }
                  });
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: colorScheme.error,
                ),
                onPressed: () {
                  setState(() {
                    _sources.removeWhere((e) => e.id == source.id);
                  });
                },
              ),
            ],
          ),
          Text(
            source.url,
            style: TextStyle(fontSize: 11, color: colorScheme.outline),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildProxyChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.15)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 12, color: colorScheme.primary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomProxyDialog() {
    final ctrl = TextEditingController(
      text: _globalProxyOptions.any((o) => o.$2 == _globalProxy)
          ? ''
          : _globalProxy,
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        title: const Text('自定义代理'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '代理前缀 URL',
            hintText: '如：https://gh-proxy.com/',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(ctx);
              setState(() {
                _globalProxy = v;
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _addSource() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        title: const Text('添加市场源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '仓库名称',
                hintText: '如：我的市场',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '仓库 URL',
                hintText: 'https://example.com/market.json',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isEmpty || url.isEmpty) {
                SmartDialog.showToast('请填写完整');
                return;
              }
              Navigator.pop(ctx);
              setState(() {
                _sources.add(MarketSource(
                  id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  url: url,
                  enabled: true,
                  proxy: _globalProxy,
                ));
              });
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // 把所有源的 proxy 统一更新为全局代理
    final updated = _sources
        .map((s) => s.copyWith(proxy: _globalProxy))
        .toList();
    await _controller.saveSources(updated);
    if (mounted) Navigator.pop(context);
    await _controller.loadMarket(forceRefresh: true);
    SmartDialog.showToast('已保存并刷新');
  }
}