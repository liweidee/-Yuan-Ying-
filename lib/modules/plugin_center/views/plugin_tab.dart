// lib/modules/plugin_center/views/plugin_tab.dart

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart' show MethodChannel;

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/plugin_center/controllers/plugin_center_controller.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/models/market_entry.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/modules/plugin_center/widgets/media_proxy_actions.dart';
import 'package:yuanying/modules/plugin_center/widgets/plugin_icon.dart';
import 'package:yuanying/modules/plugin_center/widgets/python_deps_sheet.dart';
import 'package:yuanying/modules/plugin_center/widgets/qjs_concurrency_dialog.dart';
import 'package:yuanying/modules/plugin_center/widgets/py_keep_alive_dialog.dart';
import 'package:yuanying/modules/setting/controllers/ai_config_controller.dart';

class PluginTab extends StatefulWidget {
  const PluginTab({super.key});

  @override
  State<PluginTab> createState() => _PluginTabState();
}

class _PluginTabState extends State<PluginTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showSearch = false;

  /// 系统安装的直装型插件（待固化）
  final RxList<SystemInstalledPlugin> _systemPlugins =
      <SystemInstalledPlugin>[].obs;

  /// 是否正在扫描
  final RxBool _scanning = false.obs;

  @override
  void initState() {
    super.initState();
    // 首次进入自动扫描一次
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanSystemPlugins());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanSystemPlugins() async {
    if (!Platform.isAndroid) return;
    if (_scanning.value) return;
    _scanning.value = true;
    try {
      final list = await InstallManager.instance.scanSystemImportPlugins();
      _systemPlugins.assignAll(list);
    } catch (e) {
      debugPrint('[PluginTab] scan failed: $e');
    } finally {
      _scanning.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PluginCenterController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ===== 头部：统计 + 搜索 + 扫描按钮 =====
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            children: [
              Obx(() => Text(
                    '已装 ${controller.filteredPlugins.length} 个插件',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  )),
              const Spacer(),
              // 扫描按钮（仅 Android）
              if (Platform.isAndroid)
                Obx(() {
                  if (_scanning.value) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  return IconButton(
                    tooltip: '扫描系统安装的直装型插件',
                    icon: Icon(
                      Icons.system_update_alt,
                      size: 20,
                      color: colorScheme.outline,
                    ),
                    onPressed: _scanSystemPlugins,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(8),
                  );
                }),
              // 搜索图标（右侧）
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
                    controller.pluginSearch.value = '';
                  }
                },
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ),
        // ===== 置顶提示（常驻，左对齐） =====
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '长按插件卡或点「置顶」按钮可置顶/取消置顶',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.outline,
                height: 1.3,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ),
        // ===== 搜索框（点击图标后展开） =====
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
              onChanged: (v) => controller.pluginSearch.value = v,
            ),
          ),
        const SizedBox(height: 4),
        // ===== 列表 =====
        Expanded(
          child: Obx(() {
            final list = controller.filteredPlugins;
            final sysList = _systemPlugins;
            if (list.isEmpty && sysList.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.extension_outlined,
                        size: 64, color: colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      controller.pluginSearch.value.isNotEmpty
                          ? '没有匹配的插件'
                          : '暂无已安装插件',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    if (controller.pluginSearch.value.isEmpty)
                      Text(
                        '前往「市场」标签页安装',
                        style: TextStyle(
                            fontSize: 12, color: colorScheme.outline),
                      ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(Style.safeSpace),
              itemCount: sysList.length + list.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: Style.cardSpace),
              itemBuilder: (context, index) {
                // 系统安装的直装型插件卡片优先
                if (index < sysList.length) {
                  return _SystemInstalledPluginCard(
                    info: sysList[index],
                    controller: controller,
                    onSolidified: () {
                      _systemPlugins.removeWhere(
                          (e) => e.pluginId == sysList[index].pluginId);
                      controller.reloadInstalled();
                    },
                    onUninstalled: () {
                      _systemPlugins.removeWhere(
                          (e) => e.pluginId == sysList[index].pluginId);
                    },
                  );
                }
                final plugin = list[index - sysList.length];
                return _InstalledPluginCard(
                  plugin: plugin,
                  controller: controller,
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

/// ============================================================
/// 系统安装的直装型插件卡片（待固化）
/// ============================================================
class _SystemInstalledPluginCard extends StatelessWidget {
  final SystemInstalledPlugin info;
  final PluginCenterController controller;
  final VoidCallback onSolidified;
  final VoidCallback onUninstalled;

  const _SystemInstalledPluginCard({
    required this.info,
    required this.controller,
    required this.onSolidified,
    required this.onUninstalled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: Style.mdRadius,
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== 头部：图标 + 标题 + 禁用开关 =====
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: Style.mdRadius,
                  ),
                  child: Icon(
                    Icons.smart_toy_outlined,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    info.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 禁用态开关（视觉为开，不可点击）
                IgnorePointer(
                  child: Switch(
                    value: true,
                    onChanged: null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ===== 来源行 =====
            Text(
              '来源：已安装应用 · 插件版本 ${info.version.isEmpty ? '未知' : info.version}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            // ===== 详细描述 =====
            Text(
              _descriptionFor(info.pluginId),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            // ===== 高亮固化按钮 =====
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _onSolidify(context),
                icon: const Icon(Icons.save_alt, size: 18),
                label: Text(
                  info.pluginId == 'py'
                      ? '登记为已安装（系统安装型）'
                      : '固化 APK 资源到应用内并卸载 APK',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFCE9E9),
                  foregroundColor: const Color(0xFF6B3F1F),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Divider(
                height: 1,
                color: colorScheme.outline.withValues(alpha: 0.1)),
            const SizedBox(height: 4),
            // ===== 底部操作栏 =====
            Row(
              children: [
                // 置顶（禁用，无实际作用，仅视觉一致）
                _ActionBtn(
                  icon: Icons.push_pin_outlined,
                  label: '置顶',
                  onTap: () {},
                  color: colorScheme.outline.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 12),
                // 打开（agent 才有，qjs 无界面）
                if (info.pluginId == 'agent')
                  _ActionBtn(
                    icon: Icons.open_in_new_outlined,
                    label: '打开 AI 助手',
                    onTap: () {
                      SmartDialog.showToast('请先固化后从插件卡打开');
                    },
                  ),
                const Spacer(),
                // 卸载（仅拉起系统卸载，不删本地）
                _ActionBtn(
                  icon: Icons.delete_outline,
                  label: '卸载',
                  color: colorScheme.error,
                  onTap: () => _onUninstallSystem(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _descriptionFor(String pluginId) {
    switch (pluginId) {
      case 'qjs':
        return '本地 JS 爬虫源执行引擎（QuickJS）：drpy2 与 drpy3 源统一由本插件执行。'
            '当前已通过系统安装器安装；固化后资源将提取到应用内，不再依赖系统应用。';
      case 'agent':
        return '提供 AI 助手对话界面（NextChat 静态包）：经本地网关（动态端口 / agent-ui）托管，'
            '由应用内置 Agent 运行时驱动，支持「写脚本 → 本地执行 → 自检修正」任务闭环。'
            '需在设置「AI」页配置模型接口。';
      default:
        return '系统安装的直装型插件，固化后资源将提取到应用内。';
    }
  }

  Future<void> _onSolidify(BuildContext context) async {
    // 系统安装型插件（py）只能"登记"，不能"固化"（需保持 APK 形态以维持 AIDL/Service 桥接）
    final isSystemApk = info.pluginId == 'py';
    SmartDialog.showLoading(
      msg: isSystemApk ? '正在登记…' : '正在固化资源…',
    );
    try {
      final ok = await InstallManager.instance.solidifySystemPlugin(info);
      SmartDialog.dismiss();
      if (!ok) {
        SmartDialog.showToast('操作失败，请重试');
        return;
      }
      if (isSystemApk) {
        // 系统安装型：只登记，不卸载 APK
        onSolidified();
        SmartDialog.showToast('已登记为已安装（卸载请走插件卡卸载按钮）');
        return;
      }
      // import 型（qjs/agent）：固化后拉起系统卸载
      await InstallManager.instance.uninstallSystemPackage(info.packageName);
      onSolidified();
      SmartDialog.showToast('资源已固化；若未卸载系统应用，可稍后在插件卡卸载');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('操作失败：$e');
    }
  }

  Future<void> _onUninstallSystem(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        backgroundColor: colorScheme.surface,
        title: const Text('卸载系统应用',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text('确定要卸载系统安装的「${info.title}」吗？\n'
            '卸载后该卡片将不再显示，资源不会提取到应用内。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await InstallManager.instance.uninstallSystemPackage(info.packageName);
    onUninstalled();
  }
}

/// ============================================================
/// 普通已装插件卡片
/// ============================================================
class _InstalledPluginCard extends StatelessWidget {
  final InstalledPlugin plugin;
  final PluginCenterController controller;

  const _InstalledPluginCard({
    required this.plugin,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onLongPress: () async {
        await controller.togglePinned(plugin.id, !plugin.pinned);
        SmartDialog.showToast(plugin.pinned ? '已取消置顶' : '已置顶');
      },
      child: Material(
        color: Colors.transparent,
        borderRadius: Style.mdRadius,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: Style.mdRadius,
            border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PluginIcon(
                    id: plugin.id,
                    icon: plugin.icon,
                    indexBaseUrl: controller.getCurrentIndexBaseUrl(),
                    size: 48,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _titleForPlugin(plugin.id),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${plugin.id} · v${plugin.version} · ${plugin.source}',
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
                  if (plugin.pinned) ...[
                    Icon(Icons.push_pin,
                        size: 16, color: colorScheme.primary),
                    const SizedBox(width: 12),
                  ],
                  Obx(() {
                    InstalledPlugin? latest;
                    for (final p in controller.installedList) {
                      if (p.id == plugin.id) {
                        latest = p;
                        break;
                      }
                    }
                    final enabled = latest?.enabled ?? plugin.enabled;
                    return Switch(
                      value: enabled,
                      onChanged: (v) => _onToggleEnabled(context, v),
                    );
                  }),
                ],
              ),
              if (plugin.desc != null && plugin.desc!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  plugin.desc!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Divider(
                  height: 1,
                  color: colorScheme.outline.withValues(alpha: 0.1)),
              const SizedBox(height: 4),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onToggleEnabled(BuildContext context, bool enable) async {
    if (enable) {
      await controller.toggleEnabled(plugin.id, true);
      final allServices = ServiceManager.instance
          .getAll()
          .where((s) => s.runtime == plugin.id)
          .toList();
      for (final s in allServices) {
        ServiceManager.instance.resetToStopped(s.id);
      }
      return;
    }

    final allServices = ServiceManager.instance
        .getAll()
        .where((s) => s.runtime == plugin.id)
        .toList();
    final activeServices = allServices
        .where((s) {
          final st = ServiceManager.instance.getStatus(s.id);
          return st == ServiceStatus.running || st == ServiceStatus.starting;
        })
        .toList();

    if (!context.mounted) return;
    final colorScheme = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        backgroundColor: colorScheme.surface,
        title: const Text('关闭插件',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确定要关闭「${_titleForPlugin(plugin.id)}」吗？'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: activeServices.isNotEmpty
                      ? colorScheme.errorContainer.withValues(alpha: 0.3)
                      : colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                  borderRadius: Style.mdRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (activeServices.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.warning_amber,
                              size: 16, color: colorScheme.error),
                          const SizedBox(width: 6),
                          Text(
                            '关闭后将停止以下正在运行的服务：',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...activeServices.map((s) => Padding(
                            padding:
                                const EdgeInsets.only(left: 22, top: 2),
                            child: Text('· ${s.name}',
                                style: const TextStyle(fontSize: 12)),
                          )),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      activeServices.isNotEmpty
                          ? '关闭后，这些服务将无法启动，直到重新开启此插件。已创建的服务配置会保留。'
                          : '关闭后，引用此插件的服务将无法启动，直到重新开启。',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(
              activeServices.isNotEmpty ? '关闭插件并停止服务' : '关闭插件',
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    for (final s in activeServices) {
      await ServiceManager.instance.stop(s.id);
    }
    await controller.toggleEnabled(plugin.id, false);
  }

  Widget _buildActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final actions = <Widget>[
      _ActionBtn(
        icon: plugin.pinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: plugin.pinned ? '取消置顶' : '置顶',
        onTap: () => controller.togglePinned(plugin.id, !plugin.pinned),
      ),
    ];

    switch (plugin.id) {
      case 'nodejs':
      case 'nodejs-win':
      case 'php':
      case 'php-win':
        actions.add(_ActionBtn(
          icon: Icons.dns_outlined,
          label: '查看服务',
          onTap: () => controller.jumpToServiceTabFiltered(
            plugin.id,
            _titleForPlugin(plugin.id),
          ),
        ));
        break;

      case 'python':
      case 'python-win':
        actions.add(_ActionBtn(
          icon: Icons.dns_outlined,
          label: '查看服务',
          onTap: () => controller.jumpToServiceTabFiltered(
            plugin.id,
            _titleForPlugin(plugin.id),
          ),
        ));
        actions.add(_ActionBtn(
          icon: Icons.inventory_2_outlined,
          label: '依赖管理',
          onTap: () => showPythonDepsSheet(context, plugin),
        ));
        break;

      case 'qjs':
      case 'qjs-win':
        actions.add(_ActionBtn(
          icon: Icons.speed_outlined,
          label: '引擎并发',
          onTap: () => showQjsConcurrencyDialog(context, plugin),
        ));
        break;

      case 'py':
        // 引擎并发 / py 写入守卫 / 抗杀保活：暂不接入（语义待确认）
        actions.add(_ActionBtn(
          icon: Icons.settings_outlined,
          label: '自启动设置',
          onTap: () => _openAppDetails('com.dsplayer.plugin.python'),
        ));
        actions.add(_ActionBtn(
          icon: Icons.folder_shared_outlined,
          label: '所有文件权限',
          onTap: () => _openAllFilesAccessForApp('com.dsplayer.plugin.python'),
        ));
        actions.add(_ActionBtn(
          icon: Icons.search_outlined,
          label: 'py 源管理',
          onTap: () => Get.toNamed(AppPages.pySource),
        ));
        // 保活开关：从 extras['pyKeepAlive'] 读状态，label 上带状态标识
        actions.add(_ActionBtn(
          icon: plugin.extras['pyKeepAlive'] == true
              ? Icons.favorite
              : Icons.favorite_border,
          label: plugin.extras['pyKeepAlive'] == true
              ? '保活(已开)'
              : '保活设置',
          onTap: () => showPyKeepAliveDialog(context, plugin),
        ));
        break;

      case 'agent':
        actions.add(_ActionBtn(
          icon: Icons.smart_toy_outlined,
          label: '打开 AI 助手',
          onTap: () async {
            // 先检查 AI 配置是否就绪
            if (!Get.isRegistered<AiConfigController>()) {
              Get.put(AiConfigController());
            }
            final ctrl = Get.find<AiConfigController>();
            if (!ctrl.isReady) {
              // 未配置 → 引导去设置页
              Get.toNamed(AppPages.aiConfig);
              SmartDialog.showToast('请先填写 API 基址和 Key');
              return;
            }
            Get.toNamed(AppPages.agentUi);
          },
        ));
        break;

      case 'proot':
        actions.add(_ActionBtn(
          icon: Icons.terminal,
          label: '打开沙盒',
          onTap: () => Get.toNamed(AppPages.sandbox),
        ));
        break;

      case 'mediaProxy':
      case 'mediaProxy-win':
        actions.add(_ActionBtn(
          icon: Icons.settings_outlined,
          label: '编辑配置',
          onTap: () => showMediaProxyConfigDialog(context, plugin),
        ));
        actions.add(_ActionBtn(
          icon: Icons.open_in_new_outlined,
          label: '打开 Web',
          onTap: () => openMediaProxyWeb(context, plugin),
        ));
        actions.add(
          Obx(() {
            ServiceManager.instance.revision.value;
            final status = ServiceManager.instance
                .getStatus('svc-mkt-${plugin.id}');
            if (status == ServiceStatus.running) {
              return _ActionBtn(
                icon: Icons.stop_circle_outlined,
                label: '停止服务',
                onTap: () async {
                  await ServiceManager.instance
                      .stop('svc-mkt-${plugin.id}');
                },
              );
            }
            return _ActionBtn(
              icon: Icons.play_arrow_outlined,
              label: '启动服务',
              onTap: () => startMediaProxyService(context, plugin),
            );
          }),
        );
        break;

      default:
        break;
    }

    return Row(
      children: [
        Expanded(
          child: Wrap(spacing: 4, runSpacing: 4, children: actions),
        ),
        _ActionBtn(
          icon: Icons.delete_outline,
          label: '卸载',
          color: colorScheme.error,
          onTap: () => _confirmUninstall(context),
        ),
      ],
    );
  }

  static const _pkgChannel = MethodChannel('com.example.yuanying/storage');

  Future<void> _openAppDetails(String pkgName) async {
    try {
      final ok = await _pkgChannel.invokeMethod<bool>('openAppDetails', {
        'packageName': pkgName,
      });
      if (ok != true) {
        SmartDialog.showToast('无法打开应用详情页');
      }
    } catch (e) {
      SmartDialog.showToast('跳转失败：$e');
    }
  }

  Future<void> _openAllFilesAccessForApp(String pkgName) async {
    try {
      final ok = await _pkgChannel
          .invokeMethod<bool>('openAllFilesAccessForApp', {
        'packageName': pkgName,
      });
      if (ok != true) {
        SmartDialog.showToast('无法打开权限页');
      }
    } catch (e) {
      SmartDialog.showToast('跳转失败：$e');
    }
  }

  Future<void> _confirmUninstall(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    final installMode = plugin.extras['installMode']?.toString();
    final isSystemApk = Platform.isAndroid &&
        plugin.type == 'apk' &&
        installMode == 'apk';

    final allServices = ServiceManager.instance
        .getAll()
        .where((s) => s.runtime == plugin.id)
        .toList();
    final activeServices = allServices
        .where((s) {
          final st = ServiceManager.instance.getStatus(s.id);
          return st == ServiceStatus.running || st == ServiceStatus.starting;
        })
        .toList();

    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        backgroundColor: colorScheme.surface,
        title: Text(isSystemApk ? '卸载系统应用' : '卸载插件',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('确定要卸载「${_titleForPlugin(plugin.id)}」吗？'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: Style.mdRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber,
                              size: 16, color: colorScheme.error),
                          const SizedBox(width: 6),
                          Text(
                            isSystemApk ? '将拉起系统卸载界面：' : '卸载将：',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (isSystemApk)
                        Text(
                          '系统卸载由系统弹窗完成，取消不影响当前状态。',
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4),
                        )
                      else ...[
                        if (activeServices.isNotEmpty) ...[
                          Text(
                            '1. 停止以下正在运行的服务：',
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          ...activeServices.map((s) => Padding(
                                padding:
                                    const EdgeInsets.only(left: 20, top: 2),
                                child: Text('· ${s.name}',
                                    style: const TextStyle(fontSize: 12)),
                              )),
                          const SizedBox(height: 6),
                          Text(
                            '2. 删除插件文件夹：',
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant),
                          ),
                        ] else
                          Text(
                            '删除插件文件夹：',
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant),
                          ),
                        const SizedBox(height: 2),
                        SelectableText(
                          plugin.installPath,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.outline,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isSystemApk && allServices.isNotEmpty) ...[
                  const SizedBox(height: 10),
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
                        Text(
                          '卸载后，以下已创建的服务将无法启动（依赖此插件）：',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...allServices.map((s) => Padding(
                              padding: const EdgeInsets.only(left: 6, top: 2),
                              child: Text('· ${s.name}',
                                  style: const TextStyle(fontSize: 12)),
                            )),
                        const SizedBox(height: 6),
                        Text(
                          '如需恢复，请重新从市场安装此插件。',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(isSystemApk ? '卸载应用' : '卸载插件'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // ===== 系统安装型：拉起系统卸载框 + 立即清注册表 =====
    // 不等待卸载结果：用户点确定/取消/直接关掉都不阻塞 UI，
    // 卸载成功与否下次打开插件中心会自动重新扫描（成功→不再出现，失败→重新出现为待固化卡片）
    if (isSystemApk) {
      final pkg = plugin.extras['apkPackage']?.toString();
      if (pkg == null || pkg.isEmpty) {
        SmartDialog.showToast('找不到 APK 包名，无法拉起系统卸载');
        return;
      }
      await InstallManager.instance.uninstallSystemPackage(pkg);
      await controller.uninstall(plugin);
      SmartDialog.showToast('已弹出系统卸载框，请完成卸载操作');
      return;
    }

    // ===== 非系统安装型：原有流程（停服务 + 卸载）=====
    for (final s in activeServices) {
      await ServiceManager.instance.stop(s.id);
    }
    await controller.uninstall(plugin);
  }

  String _titleForPlugin(String id) {
    switch (id) {
      case 'nodejs':
        return 'Node.js 运行时';
      case 'nodejs-win':
        return 'Node.js 运行时（Windows）';
      case 'php':
        return 'PHP 运行时';
      case 'php-win':
        return 'PHP 运行时（Windows）';
      case 'python':
        return 'Python 运行时';
      case 'python-win':
        return 'Python 运行时（Windows）';
      case 'qjs':
        return 'QJS 爬虫引擎';
      case 'qjs-win':
        return 'QJS 爬虫引擎（Windows）';
      case 'mediaProxy':
        return '媒体代理服务';
      case 'mediaProxy-win':
        return '媒体代理服务（Windows）';
      case 'proot':
        return 'Linux 沙盒运行时（PRoot）';
      default:
        return id;
    }
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final c = color ?? colorScheme.outline;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 13, color: c)),
          ],
        ),
      ),
    );
  }
}