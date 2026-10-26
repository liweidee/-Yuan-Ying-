// lib/modules/plugin_center/views/plugin_center_page.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/controllers/plugin_center_controller.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/modules/plugin_center/views/market_tab.dart';
import 'package:yuanying/modules/plugin_center/views/plugin_tab.dart';
import 'package:yuanying/modules/plugin_center/views/service_tab.dart';
import 'package:yuanying/modules/plugin_center/widgets/import_package_dialog.dart';
import 'package:yuanying/modules/plugin_center/widgets/market_manage_dialog.dart';
import 'package:yuanying/modules/plugin_center/widgets/port_clean_dialog.dart';
import 'package:yuanying/modules/plugin_center/widgets/storage_permission_button.dart';

class PluginCenterPage extends StatefulWidget {
  const PluginCenterPage({super.key});

  @override
  State<PluginCenterPage> createState() => _PluginCenterPageState();
}

class _PluginCenterPageState extends State<PluginCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final PluginCenterController _controller;
  StreamSubscription<ServiceEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _controller = Get.put(PluginCenterController());
    _controller.onJumpToServiceTab = () {
      if (mounted) {
        _tabController.animateTo(1);
      }
    };
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    _eventSub = ServiceManager.instance.onEvent.listen(_onServiceEvent);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _onServiceEvent(ServiceEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case ServiceEventType.started:
        final port = event.message;
        SmartDialog.showToast(
          port != null
              ? '${event.serviceName} 已启动（$port）'
              : '${event.serviceName} 已启动',
        );
        break;
      case ServiceEventType.stopped:
        SmartDialog.showToast('${event.serviceName} 已停止');
        break;
      case ServiceEventType.failed:
        _showServiceErrorDialog(event);
        break;
      case ServiceEventType.portTimeout:
        SmartDialog.showToast(
          '${event.serviceName}：${event.message ?? "端口探活超时"}，请查看运行日志',
        );
        break;
      case ServiceEventType.abnormalExit:
        SmartDialog.showToast(
          '${event.serviceName} 异常退出（${event.message ?? ""}）',
        );
        break;
      case ServiceEventType.restartFailed:
        SmartDialog.showToast(
          '${event.serviceName}：${event.message ?? "重启失败"}',
        );
        break;
    }
  }

  void _showServiceErrorDialog(ServiceEvent event) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        backgroundColor: colorScheme.surface,
        title: Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${event.serviceName} 启动失败',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.message != null && event.message!.isNotEmpty)
                Text(
                  event.message!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (event.detail != null && event.detail!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: Style.mdRadius,
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      event.detail!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentIndex = _tabController.index;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          '插件中心',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        actions: _buildActions(currentIndex),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.outline,
          indicatorColor: colorScheme.primary,
          tabs: const [
            Tab(text: '插件'),
            Tab(text: '服务'),
            Tab(text: '市场'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          PluginTab(),
          ServiceTab(),
          MarketTab(),
        ],
      ),
    );
  }

  List<Widget> _buildActions(int index) {
    switch (index) {
      case 0:
        return [
          const StoragePermissionButton(),
          IconButton(
            tooltip: '导入插件包',
            icon: const Icon(Icons.file_upload_outlined, size: 20),
            onPressed: () => showImportPackageDialog(context),
          ),
          IconButton(
            tooltip: '打开插件目录',
            icon: const Icon(Icons.folder_open, size: 20),
            onPressed: _openPluginDir,
          ),
        ];
      case 1:
        return [
          const StoragePermissionButton(),
          IconButton(
            tooltip: '打开数据目录',
            icon: const Icon(Icons.folder_open, size: 20),
            onPressed: _openServerDir,
          ),
          if (Platform.isWindows)
            IconButton(
              tooltip: '清理端口占用',
              icon: const Icon(Icons.cleaning_services_outlined, size: 20),
              onPressed: () => showPortCleanDialog(context),
            ),
        ];
      case 2:
        return [
          IconButton(
            tooltip: '管理市场',
            icon: const Icon(Icons.settings, size: 20),
            onPressed: () => showMarketManageDialog(context),
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => _controller.loadMarket(forceRefresh: true),
          ),
        ];
      default:
        return const [];
    }
  }

  Future<void> _openPluginDir() async {
    final dir = await PluginPaths.root();
    await _openInExplorer(dir.path);
  }

  Future<void> _openServerDir() async {
    final dir = await PluginPaths.servicesRoot();
    await _openInExplorer(dir.path);
  }

  Future<void> _openInExplorer(String path) async {
    try {
      if (Platform.isAndroid) {
        // Android 私有目录普通文件管理器不可见，仅提示路径
        SmartDialog.showToast('目录：$path');
        return;
      }
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {}
  }
}