// lib/modules/plugin_center/views/service_tab.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/controllers/plugin_center_controller.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/modules/plugin_center/widgets/service_form.dart';
import 'package:yuanying/modules/plugin_center/widgets/service_import_export.dart';
import 'package:yuanying/modules/plugin_center/widgets/service_log_sheet.dart';
import 'package:yuanying/modules/webview/views/webview_page.dart';
import 'package:yuanying/utils/platform_utils.dart';

class ServiceTab extends StatefulWidget {
  const ServiceTab({super.key});

  @override
  State<ServiceTab> createState() => _ServiceTabState();
}

class _ServiceTabState extends State<ServiceTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PluginCenterController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Column(
          children: [
            // ===== 头部：运行中 N · 共 N + 操作按钮 =====
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Obx(() => Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '运行中 ${controller.runningServiceCount}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            TextSpan(
                              text: ' · 共 ${controller.serviceCount} 个服务',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      )),
                  const Spacer(),
                  // 搜索
                  IconButton(
                    tooltip: '搜索',
                    icon: Icon(
                      _showSearch ? Icons.search_off : Icons.search,
                      size: 18,
                      color: colorScheme.outline,
                    ),
                    onPressed: () {
                      setState(() => _showSearch = !_showSearch);
                      if (!_showSearch) {
                        _searchCtrl.clear();
                        controller.serviceSearch.value = '';
                      }
                    },
                  ),
                  // 示例
                  TextButton.icon(
                    onPressed: () => _showSampleMenu(context),
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('示例',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                  // 导入
                  TextButton.icon(
                    onPressed: () async {
                      await importServices();
                      controller.reloadServices();
                    },
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('导入',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                  // 导出
                  TextButton(
                    onPressed: exportAllServices,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('导出',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            // ===== 搜索框（点击搜索后展开） =====
            if (_showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索服务...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) => controller.serviceSearch.value = v,
                ),
              ),
            // ===== 筛选 chip =====
            Obx(() {
              final hasFilter =
                  controller.serviceTabFilterRuntime.value.isNotEmpty;
              if (!hasFilter) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(
                  children: [
                    Icon(Icons.filter_alt,
                        size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '筛选：${controller.serviceTabFilterLabel.value}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => controller.clearServiceTabFilter(),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close,
                            size: 16, color: colorScheme.outline),
                      ),
                    ),
                  ],
                ),
              );
            }),
            // ===== 服务列表 =====
            Expanded(
              child: Obx(() {
                final ids = controller.filteredServiceIds;
                if (ids.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          controller.serviceCount == 0
                              ? Icons.dns_outlined
                              : Icons.filter_alt_off_outlined,
                          size: 64,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          controller.serviceCount == 0
                              ? '暂无服务'
                              : '没有匹配的服务',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                        const SizedBox(height: 8),
                        if (controller.serviceCount == 0)
                          Text(
                            '点击右下角 + 添加服务',
                            style: TextStyle(
                                fontSize: 12, color: colorScheme.outline),
                          ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    Style.safeSpace,
                    Style.safeSpace,
                    Style.safeSpace,
                    Style.safeSpace + 80,
                  ),
                  itemCount: ids.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: Style.cardSpace),
                  itemBuilder: (context, index) {
                    final config =
                        ServiceManager.instance.find(ids[index]);
                    if (config == null) return const SizedBox.shrink();
                    return _ServiceCard(
                        config: config, controller: controller);
                  },
                );
              }),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () => showServiceForm(context),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  /// 示例菜单
  void _showSampleMenu(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        title: const Text('选择示例服务'),
        children: [
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('T4-PHP'),
            subtitle: const Text('PHP 示例站点'),
            onTap: () {
              Navigator.pop(ctx);
              _createSample('T4-PHP', 'php-win', 5787,
                  '-S 0.0.0.0:5787 -t {cwd}', 'php-t4');
            },
          ),
          ListTile(
            leading: const Icon(Icons.javascript),
            title: const Text('drpys (Node)'),
            subtitle: const Text('Node.js 示例服务'),
            onTap: () {
              Navigator.pop(ctx);
              _createSample('drpys', 'nodejs-win', 5757,
                  '--port 5757 index.js', 'drpys');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createSample(String name, String runtime, int port,
      String args, String cwdSuffix) async {
    try {
      final id = 'svc-${DateTime.now().millisecondsSinceEpoch}';
      final config = ServiceConfig(
        id: id,
        name: name,
        port: port,
        runtime: runtime,
        args: args.split(' '),
        cwd: '__filesDir__/services/$cwdSuffix',
        autostart: false,
        keepForeground: false,
        healthType: 'tcp',
        healthPath: '/',
      );
      await ServiceManager.instance.addOrUpdate(config);
      final controller = Get.find<PluginCenterController>();
      controller.reloadServices();
      SmartDialog.showToast('已创建示例：$name');
    } catch (e) {
      SmartDialog.showToast('创建失败：$e');
    }
  }
}

class _ServiceCard extends StatelessWidget {
  final ServiceConfig config;
  final PluginCenterController controller;

  const _ServiceCard({required this.config, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Obx(() {
      ServiceManager.instance.revision.value;
      final status = ServiceManager.instance.getStatus(config.id);
      final running = status == ServiceStatus.running;
      final hasPort = config.port != null && config.port! > 0;

      return Material(
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
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer
                          .withValues(alpha: 0.2),
                      borderRadius: Style.mdRadius,
                    ),
                    child: Icon(Icons.dns,
                        color: colorScheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        _buildTags(colorScheme),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: status),
                  _buildMoreMenu(context),
                ],
              ),
              const SizedBox(height: 8),
              Divider(
                  height: 1,
                  color: colorScheme.outline.withValues(alpha: 0.1)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  running
                      ? _ActionBtn(
                          icon: Icons.stop,
                          label: '停止',
                          onTap: () async {
                            await ServiceManager.instance.stop(config.id);
                          },
                        )
                      : _ActionBtn(
                          icon: Icons.play_arrow,
                          label: '启动',
                          onTap: () async {
                            try {
                              await ServiceManager.instance.start(config.id);
                            } catch (_) {}
                          },
                        ),
                  _ActionBtn(
                    icon: Icons.open_in_browser,
                    label: '打开 Web',
                    enabled: running && hasPort,
                    onTap: () {
                      if (!hasPort) return;
                      Get.to(() => WebviewPage(
                            url: 'http://localhost:${config.port}/',
                            title: config.name,
                          ));
                    },
                  ),
                  _ActionBtn(
                    // icon: Icons.receipt_long_outlined,
                    icon: Icons.description_outlined,
                    label: '运行日志',
                    onTap: () => showServiceLogSheet(context, config),
                  ),
                  _ActionBtn(
                    icon: Icons.edit_outlined,
                    label: '编辑',
                    onTap: () => showServiceForm(context, existing: config),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildMoreMenu(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: Icon(Icons.more_vert, size: 20, color: colorScheme.outline),
      offset: const Offset(0, 36),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            showServiceForm(context, existing: config);
            break;
          case 'log':
            showServiceLogSheet(context, config);
            break;
          case 'copy':
            _copyService(context);
            break;
          case 'export':
            _exportConfigToFile(context);
            break;
          case 'delete':
            _confirmDelete(context);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
            value: 'edit',
            child: Row(children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('编辑'),
            ])),
        const PopupMenuItem(
            value: 'log',
            child: Row(children: [
              Icon(Icons.receipt_long_outlined, size: 18),
              SizedBox(width: 8),
              Text('运行日志'),
            ])),
        const PopupMenuItem(
            value: 'copy',
            child: Row(children: [
              Icon(Icons.copy_outlined, size: 18),
              SizedBox(width: 8),
              Text('复制服务'),
            ])),
        const PopupMenuItem(
            value: 'export',
            child: Row(children: [
              Icon(Icons.file_upload_outlined, size: 18),
              SizedBox(width: 8),
              Text('导出配置'),
            ])),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.red)),
            ])),
      ],
    );
  }

  Future<void> _copyService(BuildContext context) async {
    try {
      final all = ServiceManager.instance.getAll();
      final baseName = config.name;
      final existingNames = all.map((s) => s.name).toSet();
      int n = 1;
      String newName = '$baseName-$n';
      while (existingNames.contains(newName)) {
        n++;
        newName = '$baseName-$n';
      }
      final newId = 'svc-${DateTime.now().millisecondsSinceEpoch}';
      final newPort = config.port != null ? config.port! + 1 : null;
      var newArgs = List<String>.from(config.args);
      if (config.port != null && newPort != null) {
        newArgs = newArgs
            .map((a) => a.replaceAll('${config.port}', '$newPort'))
            .toList();
      }
      final copy = ServiceConfig(
        id: newId,
        name: newName,
        port: newPort,
        runtime: config.runtime,
        args: newArgs,
        cwd: config.cwd,
        autostart: false,
        keepForeground: false,
        env: config.env,
        maxRestart: config.maxRestart,
        executable: config.executable,
        healthType: config.healthType,
        healthPath: config.healthPath,
        pidFile: null,
      );
      await ServiceManager.instance.addOrUpdate(copy);
      controller.reloadServices();
      SmartDialog.showToast('已创建副本：$newName');
    } catch (e) {
      SmartDialog.showToast('复制失败：$e');
    }
  }

  Future<void> _exportConfigToFile(BuildContext context) async {
    try {
      final json = const JsonEncoder.withIndent('  ')
          .convert(config.toJson());
      final bytes = Uint8List.fromList(utf8.encode(json));
      final safeName = config.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final uri = await FilePicker.saveFile(
        fileName: '$safeName.json',
        bytes: PlatformUtils.isDesktop ? Uint8List(0) : bytes,
      );
      if (uri == null) return;
      if (PlatformUtils.isDesktop) {
        await File(uri.toFilePath()).writeAsBytes(bytes, flush: true);
      }
      SmartDialog.showToast('配置已导出：$safeName.json');
    } catch (e) {
      SmartDialog.showToast('导出失败：$e');
    }
  }

  Widget _buildTags(ColorScheme colorScheme) {
    final tags = <Widget>[];
    if (config.port != null && config.port! > 0) {
      tags.add(_Tag(
        text: '端口 ${config.port}',
        color: colorScheme.primary,
        icon: Icons.link,
      ));
    }
    tags.add(_Tag(
      text: _runtimeLabel(config.runtime),
      color: colorScheme.tertiary,
      icon: Icons.memory,
    ));
    if (config.autostart) {
      tags.add(const _Tag(
        text: '自启动',
        color: Colors.orange,
        icon: Icons.autorenew,
      ));
    }
    if (config.keepForeground) {
      tags.add(const _Tag(
        text: '常驻',
        color: Colors.purple,
        icon: Icons.push_pin,
      ));
    }
    return Wrap(spacing: 4, runSpacing: 4, children: tags);
  }

  String _runtimeLabel(String runtime) {
    switch (runtime) {
      case 'nodejs':
        return 'Node.js';
      case 'nodejs-win':
        return 'Node.js（Windows）';
      case 'php':
        return 'PHP';
      case 'php-win':
        return 'PHP（Windows）';
      case 'python':
        return 'Python';
      case 'python-win':
        return 'Python（Windows）';
      case 'qjs':
        return 'QJS';
      case 'qjs-win':
        return 'QJS（Windows）';
      case 'mediaProxy':
        return '媒体代理';
      case 'mediaProxy-win':
        return '媒体代理（Windows）';
      case 'custom':
        return '自定义';
      default:
        return runtime;
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final isServerPackage = config.id.startsWith('svc-mkt-');
    final colorScheme = Theme.of(context).colorScheme;

    bool cwdIsServicesRoot = false;
    try {
      final servicesRoot = await PluginPaths.servicesRoot();
      cwdIsServicesRoot =
          p.normalize(config.cwd) == p.normalize(servicesRoot.path);
    } catch (_) {}

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        backgroundColor: colorScheme.surface,
        title: const Text('删除服务',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确定要删除「${config.name}」吗？'),
              const SizedBox(height: 10),
              if (isServerPackage) ...[
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
                            '该服务由市场服务包自动创建',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '删除会一并删除本地目录：',
                        style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        config.cwd,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.outline,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '目录内的用户数据将丢失。',
                        style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.error,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ] else ...[
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
                              size: 16, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            '仅删除服务配置，不会删除任何本地文件',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      if (cwdIsServicesRoot) ...[
                        const SizedBox(height: 6),
                        Text(
                          '该服务未指定独立工作目录，本地文件不受影响。',
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4),
                        ),
                      ] else if (config.cwd.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '工作目录（不会被删除）：',
                          style: TextStyle(
                              fontSize: 11, color: colorScheme.outline),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          config.cwd,
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
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (isServerPackage) {
                await ServiceManager.instance.removeWithDir(config.id);
              } else {
                await ServiceManager.instance.remove(config.id);
              }
              controller.reloadServices();
            },
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _Tag({
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w500,
                height: 1.2),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ServiceStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Color color;
    switch (status) {
      case ServiceStatus.running:
        color = Colors.green;
        break;
      case ServiceStatus.starting:
        color = Colors.orange;
        break;
      case ServiceStatus.error:
        color = colorScheme.error;
        break;
      case ServiceStatus.stopped:
        color = colorScheme.outline;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.label,
        style:
            TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final c = !enabled
        ? colorScheme.outline.withValues(alpha: 0.4)
        : (color ?? colorScheme.outline);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: enabled ? onTap : null,
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