// lib/modules/plugin_center/widgets/media_proxy_actions.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/controllers/plugin_center_controller.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/modules/webview/views/webview_page.dart';

/// mediaProxy 服务固定 id（插件卡启动服务时由本文件创建）
const String _serviceId = 'svc-mkt-mediaProxy-win';

/// 读取媒体代理端口。
///
/// 从 Hive 注册表读最新 extras，而不是从传入的 plugin 快照读。
/// 原因：用户可能刚在配置对话框里改了端口保存，但插件卡片的
/// plugin 对象尚未刷新（updateExtras 不回传新对象），
/// 直接用 plugin.extras 会拿到过期端口。
int _getProxyPort(InstalledPlugin plugin) {
  final latest = InstallManager.instance.findInstalled(plugin.id);
  final extras = latest?.extras ?? plugin.extras;
  final v = extras['mediaProxyPort'];
  if (v is int) return v;
  return 5575;
}

/// 读取额外启动参数（同样从 Hive 读最新值）
String _getExtraArgs(InstalledPlugin plugin) {
  final latest = InstallManager.instance.findInstalled(plugin.id);
  final extras = latest?.extras ?? plugin.extras;
  return extras['mediaProxyExtraArgs']?.toString() ?? '';
}

/// 打开 Web：先探一次端口再打开
Future<void> openMediaProxyWeb(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  final port = _getProxyPort(plugin);

  bool alive = false;
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: const Duration(milliseconds: 800),
    );
    await socket.close();
    alive = true;
  } catch (_) {
    alive = false;
  }

  if (!alive) {
    SmartDialog.showToast('服务未运行或端口 $port 不可达');
    return;
  }

  final url = 'http://localhost:$port/';
  debugPrint('[openMediaProxyWeb] open url: $url');
  Get.to(() => WebviewPage(url: url, title: '媒体代理服务'));
}

/// 编辑配置
Future<void> showMediaProxyConfigDialog(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _MediaProxyConfigDialog(plugin: plugin),
  );
}

class _MediaProxyConfigDialog extends StatefulWidget {
  final InstalledPlugin plugin;

  const _MediaProxyConfigDialog({required this.plugin});

  @override
  State<_MediaProxyConfigDialog> createState() =>
      _MediaProxyConfigDialogState();
}

class _MediaProxyConfigDialogState extends State<_MediaProxyConfigDialog> {
  late TextEditingController _portCtrl;
  late TextEditingController _extraArgsCtrl;

  @override
  void initState() {
    super.initState();
    // 从 Hive 读最新值，保证打开对话框时展示的是最新保存的端口
    final port = _getProxyPort(widget.plugin);
    _portCtrl = TextEditingController(text: '$port');
    _extraArgsCtrl = TextEditingController(
      text: _getExtraArgs(widget.plugin),
    );
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _extraArgsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: const Text(
        '媒体代理服务配置',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'mediaProxy 支持的启动参数（来自 plugin.json）：\n'
              '-port 端口，-dns DNS，-auth 密钥，-threads 线程，'
              '-window 预读窗口(MB)，-seg 分片大小\n'
              '默认端口 5575。',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.outline,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '端口（-port）',
                hintText: '默认 5575',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _extraArgsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '额外参数（选填，空格分隔）',
                hintText: '如：-dns 8.8.8.8 -threads 16',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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

  Future<void> _save() async {
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      SmartDialog.showToast('端口无效（1-65535）');
      return;
    }

    // 从 Hive 读最新 extras，避免基于旧 plugin 快照覆盖其他字段
    final latest = InstallManager.instance.findInstalled(widget.plugin.id);
    final extras = Map<String, dynamic>.from(
      latest?.extras ?? widget.plugin.extras,
    );
    extras['mediaProxyPort'] = port;
    extras['mediaProxyExtraArgs'] = _extraArgsCtrl.text.trim();
    await InstallManager.instance.updateExtras(widget.plugin.id, extras);

    // 关键修复：通知插件中心刷新 installedList。
    // 否则本页内的后续操作（点启动服务 / 再次编辑）仍读到旧 extras。
    if (Get.isRegistered<PluginCenterController>()) {
      Get.find<PluginCenterController>().reloadInstalled();
    }

    // 检查服务是否正在运行：端口变更必须重启服务才能生效
    final currentStatus = ServiceManager.instance.getStatus(_serviceId);
    final wasRunning = currentStatus == ServiceStatus.running ||
        currentStatus == ServiceStatus.starting;

    if (mounted) Navigator.pop(context);

    if (wasRunning) {
      SmartDialog.showToast('已保存，需停止并重新启动服务才能生效');
    } else {
      SmartDialog.showToast('已保存');
    }
  }
}

/// 启动服务：创建/更新服务配置并启动
Future<void> startMediaProxyService(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  final controller = Get.find<PluginCenterController>();
  // 从 Hive 读最新端口与参数，避免 plugin 是旧快照时用错端口启动
  final port = _getProxyPort(plugin);

  final exePath = _resolveMediaProxyExe(plugin);
  if (exePath == null) {
    SmartDialog.showToast('找不到 mediaProxy 可执行文件');
    return;
  }

  final extra = _getExtraArgs(plugin);
  final argsList = <String>['-port', '$port'];
  if (extra.trim().isNotEmpty) {
    argsList.addAll(extra.trim().split(RegExp(r'\s+')));
  }

  final serverDir = await PluginPaths.serverDir(_serviceId);

  final config = ServiceConfig(
    id: _serviceId,
    name: '媒体代理服务',
    port: port,
    runtime: plugin.id,
    args: argsList,
    cwd: serverDir.path,
    autostart: false,
    keepForeground: true,
  );
  await ServiceManager.instance.addOrUpdate(config);
  controller.reloadServices();

  // 关键修复：如果服务已在运行（端口可能已变更），先停止再启动。
  // 否则 ServiceManager.start 检测到 running 状态会直接 return，
  // 导致 Hive 里配置端口已改、但实际运行进程还在用旧端口。
  final currentStatus = ServiceManager.instance.getStatus(_serviceId);
  if (currentStatus == ServiceStatus.running ||
      currentStatus == ServiceStatus.starting) {
    await ServiceManager.instance.stop(_serviceId);
  }

  try {
    await ServiceManager.instance.start(_serviceId);
    // 成功/失败提示由 ServiceManager.onEvent 统一处理
  } catch (_) {
    // 错误由 ServiceManager.onEvent 统一处理
  }
}

String? _resolveMediaProxyExe(InstalledPlugin plugin) {
  final candidates = [
    p.join(plugin.installPath, 'bin', 'mediaProxy-win.exe'),
    p.join(plugin.installPath, 'bin', 'mediaProxy.exe'),
    p.join(plugin.installPath, 'mediaProxy-win.exe'),
    p.join(plugin.installPath, 'mediaProxy.exe'),
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}