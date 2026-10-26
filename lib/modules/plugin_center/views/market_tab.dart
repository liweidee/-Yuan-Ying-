// lib/modules/plugin_center/views/market_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/controllers/plugin_center_controller.dart';
import 'package:yuanying/modules/plugin_center/models/market_entry.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/modules/plugin_center/widgets/install_progress_dialog.dart';
import 'package:yuanying/modules/plugin_center/widgets/plugin_detail_sheet.dart';
import 'package:yuanying/modules/plugin_center/widgets/plugin_icon.dart';

class MarketTab extends StatefulWidget {
  const MarketTab({super.key});

  @override
  State<MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<MarketTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showSearch = false;

  final PluginCenterController _controller = Get.find<PluginCenterController>();

  @override
  void initState() {
    super.initState();
    if (_controller.marketEntries.isEmpty) {
      _controller.loadMarket();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            children: [
              Obx(() => Text(
                    '${_controller.marketEntries.length} 个插件'
                    ' · ${_controller.updatableCount} 个可更新',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  )),
              const Spacer(),
              IconButton(
                tooltip: '搜索',
                icon: Icon(
                  _showSearch ? Icons.search_off : Icons.search,
                  size: 20,
                  color: colorScheme.outline,
                ),
                onPressed: () {
                  setState(() => _showSearch = !_showSearch);
                  if (!_showSearch) {
                    _searchCtrl.clear();
                    _controller.marketSearch.value = '';
                  }
                },
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ),
        if (_showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索插件...',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => _controller.marketSearch.value = v,
            ),
          ),
        _buildFilterChips(colorScheme),
        const SizedBox(height: 4),
        Expanded(child: _buildList(colorScheme)),
      ],
    );
  }

  Widget _buildFilterChips(ColorScheme colorScheme) {
    return Obx(() {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            _buildFilterChip(
              label: '全部',
              selected: _controller.marketFilter.value == MarketFilter.all,
              onTap: () => _controller.marketFilter.value = MarketFilter.all,
            ),
            _buildFilterChip(
              label: '可更新 ${_controller.updatableCount}',
              selected:
                  _controller.marketFilter.value == MarketFilter.updatable,
              onTap: () =>
                  _controller.marketFilter.value = MarketFilter.updatable,
            ),
            _buildFilterChip(
              label: '已安装 ${_controller.installedCount}',
              selected:
                  _controller.marketFilter.value == MarketFilter.installed,
              onTap: () =>
                  _controller.marketFilter.value = MarketFilter.installed,
            ),
            _buildFilterChip(
              label: '未安装',
              selected:
                  _controller.marketFilter.value == MarketFilter.notInstalled,
              onTap: () =>
                  _controller.marketFilter.value = MarketFilter.notInstalled,
            ),
            const SizedBox(width: 12),
            Container(
              width: 1,
              height: 20,
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
            const SizedBox(width: 12),
            _buildFilterChip(
              label: '全类别',
              selected:
                  _controller.marketCategory.value == MarketCategory.all,
              onTap: () =>
                  _controller.marketCategory.value = MarketCategory.all,
            ),
            _buildFilterChip(
              label: '环境',
              selected:
                  _controller.marketCategory.value == MarketCategory.env,
              onTap: () =>
                  _controller.marketCategory.value = MarketCategory.env,
            ),
            _buildFilterChip(
              label: '应用',
              selected:
                  _controller.marketCategory.value == MarketCategory.app,
              onTap: () =>
                  _controller.marketCategory.value = MarketCategory.app,
            ),
          ],
        ),
      );
    });
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(ColorScheme colorScheme) {
    return Obx(() {
      if (_controller.marketLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_controller.marketError.value.isNotEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  '加载失败：${_controller.marketError.value}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.outline),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _controller.loadMarket(forceRefresh: true),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        );
      }

      final list = _controller.filteredEntries;
      if (list.isEmpty) {
        return Center(
          child: Text(
            _controller.marketSearch.value.isNotEmpty
                ? '没有匹配的插件'
                : '没有符合条件的插件',
            style: TextStyle(color: colorScheme.outline),
          ),
        );
      }

      // 用 installRevision 作为列表的整体 key 前缀，保证注册表变更时
      // 所有卡片都会以最新状态重建（卡片本身是 StatelessWidget，靠 Obx 派生，
      // 这里 key 的作用只是让列表在筛选结果变化时正确复用/重建）。
      final revision = _controller.installRevision.value;

      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          Style.safeSpace,
          4,
          Style.safeSpace,
          Style.safeSpace,
        ),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: Style.cardSpace),
        itemBuilder: (context, index) {
          final entry = list[index];
          return _MarketCard(
            key: ValueKey('${entry.id}@${entry.version}@$revision'),
            entry: entry,
            controller: _controller,
            onInstall: _install,
          );
        },
      );
    });
  }

  /// 安装/更新。成功/失败 Toast 由 [showInstallProgressDialog] 统一处理。
  ///
  /// 安装完成（无论成功与否）后统一走 controller.reloadInstalled()，
  /// 由 installRevision 驱动市场卡片与插件卡片同步刷新，
  /// 不再依赖卡片内部的 Future 缓存。
  Future<void> _install(MarketEntry entry) async {
    // 1. 检查关联服务是否在运行（含 running + starting）
    final runningServices = <String, String>{};
    for (final svc in ServiceManager.instance.getAll()) {
      if (svc.runtime != entry.id) continue;
      final st = ServiceManager.instance.getStatus(svc.id);
      if (st == ServiceStatus.running || st == ServiceStatus.starting) {
        runningServices[svc.id] = svc.name;
      }
    }

    if (runningServices.isNotEmpty && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('服务运行中'),
          content: Text(
            '以下服务正在运行，更新插件需要先停止服务：\n'
            '${runningServices.values.map((n) => '· $n').join('\n')}\n\n'
            '是否停止这些服务并继续更新？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('停止并更新'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      for (final id in runningServices.keys) {
        await ServiceManager.instance.stop(id);
      }
    }

    // 2. 下载 + 安装
    final token = InstallCancelToken();
    await showInstallProgressDialog(
      context: context,
      entry: entry,
      token: token,
      task: (onProgress) => InstallManager.instance.install(
        entry,
        indexBaseUrl: _controller.getCurrentIndexBaseUrl(),
        marketName: _controller.getCurrentMarketName(),
        cancelToken: token,
        onProgress: onProgress,
      ),
    );

    // 3. 刷新注册表 —— installRevision 自增，市场卡片与插件卡片同步更新
    _controller.reloadInstalled();
    _controller.reloadServices();
  }
}

/// 市场卡片：纯 StatelessWidget + Obx 派生安装状态。
/// 不持有任何 Future 缓存，安装状态完全由 controller.installedList 派生。
class _MarketCard extends StatelessWidget {
  final MarketEntry entry;
  final PluginCenterController controller;
  final void Function(MarketEntry entry) onInstall;

  const _MarketCard({
    super.key,
    required this.entry,
    required this.controller,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Obx(() {
      // 订阅安装变更版本号，保证注册表变更时按钮态重建
      controller.installRevision.value;
      final state = controller.installStateOf(entry);
      final disabled = state == MarketInstallState.unsupported;

      return Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: Material(
          color: Colors.transparent,
          borderRadius: Style.mdRadius,
          child: InkWell(
            borderRadius: Style.mdRadius,
            onTap: disabled
                ? null
                : () => showPluginDetailSheet(
                      context,
                      entry: entry,
                      onInstall: () => onInstall(entry),
                    ),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: Style.mdRadius,
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.shadowColor.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PluginIcon(
                        id: entry.id,
                        icon: entry.icon,
                        indexBaseUrl: controller.getCurrentIndexBaseUrl(),
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (disabled)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '当前平台不支持',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${entry.author ?? ''} · v${entry.version}'
                              ' · ${entry.sizeText}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (entry.desc != null && entry.desc!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.desc!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _tag(entry.type, colorScheme),
                      const SizedBox(width: 6),
                      _tag(entry.category, colorScheme),
                      const Spacer(),
                      if (disabled)
                        Text(
                          '不可安装',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        )
                      else
                        _buildActionButton(context, state),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildActionButton(
    BuildContext context,
    MarketInstallState state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (state) {
      case MarketInstallState.installed:
        return Text(
          '已安装',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        );

      case MarketInstallState.updatable:
        return TextButton(
          onPressed: () => onInstall(entry),
          child: const Text('更新'),
        );

      case MarketInstallState.notInstalled:
        return TextButton(
          onPressed: () => onInstall(entry),
          child: Text(
            entry.type == 'live' || entry.type == 'source'
                ? '导入'
                : '安装',
          ),
        );

      case MarketInstallState.unsupported:
        return Text(
          '不可安装',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.outline,
          ),
        );
    }
  }

  Widget _tag(String text, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: colorScheme.outline),
      ),
    );
  }
}