// lib/modules/sandbox/views/sandbox_page.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/sandbox/models/sandbox_service.dart';
import 'package:yuanying/modules/sandbox/models/sandbox_service_state.dart';
import 'package:yuanying/modules/sandbox/services/rootfs_manager.dart';
import 'package:yuanying/modules/sandbox/services/sandbox_service_manager.dart';
import 'package:yuanying/modules/sandbox/services/sandbox_service_store.dart';
import 'package:yuanying/modules/sandbox/services/shell_session.dart';
import 'package:yuanying/modules/sandbox/widgets/sandbox_service_form_dialog.dart';
import 'package:yuanying/modules/sandbox/widgets/sandbox_service_log_sheet.dart';
import 'package:yuanying/modules/webview/views/webview_page.dart';
import 'package:yuanying/modules/sandbox/widgets/sandbox_import_dialog.dart';
import 'package:yuanying/modules/sandbox/widgets/rootfs_install_dialog.dart';

class SandboxPage extends StatefulWidget {
  const SandboxPage({super.key});

  @override
  State<SandboxPage> createState() => _SandboxPageState();
}

class _SandboxPageState extends State<SandboxPage> {
  bool _runtimeReady = false;
  String? _installedDistro;
  bool _installingRootfs = false;
  bool _autoStartTriggered = false;

  /// ShellSession.start 内部有多次 await（resolve + 4 次 chmod
  /// + Process.start），期间 _terminalActive 仍为 false、_session 仍为 null，
  /// 快速双击会创建两个 shell，第一个被覆盖泄漏。
  /// 用独立布尔锁拦截「首次启动期间」的二次点击。
  bool _startingTerminal = false;

  List<SandboxService> _services = [];

  ShellSession? _session;
  bool _terminalActive = false;
  final StringBuffer _terminalBuffer = StringBuffer();
  final TextEditingController _terminalInputCtrl = TextEditingController();
  final ScrollController _terminalScrollCtrl = ScrollController();
  final FocusNode _terminalInputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  @override
  void dispose() {
    _session?.dispose();
    _terminalInputCtrl.dispose();
    _terminalScrollCtrl.dispose();
    _terminalInputFocus.dispose();
    super.dispose();
  }

  Future<void> _refreshState() async {
    if (!Platform.isAndroid) {
      if (mounted) {
        setState(() {
          _runtimeReady = false;
          _installedDistro = null;
          _services = [];
        });
      }
      return;
    }
    final plugin = InstallManager.instance.findInstalled('proot');
    final ready = plugin != null && plugin.enabled;
    String? distro;
    if (ready) {
      distro = await RootfsManager.instance.currentInstalledDistro();
    }
    final services = SandboxServiceStore.getAll();
    if (!mounted) return;
    setState(() {
      _runtimeReady = ready;
      _installedDistro = distro;
      _services = services;
    });

    if (ready && distro != null && !_autoStartTriggered) {
      _autoStartTriggered = true;
      unawaited(SandboxServiceManager.instance.autoStartAll(distro));
    }
  }

  Future<void> _importProject() async {
    final distroId = _installedDistro;
    if (distroId == null) {
      SmartDialog.showToast('请先安装沙盒环境');
      return;
    }
    final svc = await showSandboxImportDialog(context, distroId: distroId);
    if (svc == null) return;
    await SandboxServiceStore.addOrUpdate(svc);
    await _refreshState();
    SmartDialog.showToast('项目已导入，可在下方列表中启动');
  }

  // ============================================================
  // rootfs
  // ============================================================
  Future<void> _installRootfs(DistroInfo distro) async {
    if (_installingRootfs) return;
    setState(() => _installingRootfs = true);

    // 重装当前激活的 distro 时，先停掉所有正在运行的服务
    if (_installedDistro == distro.id) {
      for (final svc in _services) {
        if (SandboxServiceManager.instance.isRunning(svc.id)) {
          await SandboxServiceManager.instance.stop(svc.id);
        }
      }
    }

    try {
      final ok = await showRootfsInstallDialog(
        context: context,
        distro: distro,
      );
      if (ok) {
        await _refreshState();
      }
    } finally {
      if (mounted) setState(() => _installingRootfs = false);
    }
  }

  Future<void> _uninstallRootfs() async {
    final distroId = _installedDistro;
    if (distroId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载环境'),
        content: Text('确定卸载 $distroId？沙盒内所有软件与数据将丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final svc in _services) {
      if (SandboxServiceManager.instance.isRunning(svc.id)) {
        await SandboxServiceManager.instance.stop(svc.id);
      }
    }
    await RootfsManager.instance.uninstall(distroId);
    SmartDialog.showToast('已卸载');
    await _refreshState();
  }

  // ============================================================
  // 终端
  // ============================================================
  Future<void> _startTerminal() async {
    // 启动期间用独立锁拦截双击
    if (_startingTerminal) return;
    if (_terminalActive && _session != null) return;
    final distroId = _installedDistro;
    if (distroId == null) return;

    _startingTerminal = true;
    try {
      final session = await ShellSession.start(
        distroId: distroId,
        onOutput: (chunk) {
          _terminalBuffer.write(chunk);
          _scrollToBottom();
        },
        onExit: (code) {
          if (!mounted) return;
          setState(() {
            _terminalActive = false;
            _session = null;
          });
          _terminalBuffer.write('\n[会话已结束，退出码 $code]\n');
          _scrollToBottom();
        },
      );
      if (!mounted) {
        await session.dispose();
        return;
      }
      setState(() {
        _session = session;
        _terminalActive = true;
        _terminalBuffer.clear();
      });
    } catch (e) {
      SmartDialog.showToast('启动失败：$e');
    } finally {
      _startingTerminal = false;
    }
  }

  Future<void> _endTerminal() async {
    final s = _session;
    if (s == null) return;
    s.write('exit\n');
    await Future.delayed(const Duration(milliseconds: 300));
    s.kill();
    await s.dispose();
    if (!mounted) return;
    setState(() {
      _session = null;
      _terminalActive = false;
    });
  }

  void _sendCommand() {
    final text = _terminalInputCtrl.text;
    if (text.isEmpty || _session == null) return;
    _terminalBuffer.write('> $text\n');
    _session!.write('$text\n');
    _terminalInputCtrl.clear();
    _scrollToBottom();
    _terminalInputFocus.requestFocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_terminalScrollCtrl.hasClients) {
        _terminalScrollCtrl.animateTo(
          _terminalScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
      if (mounted) setState(() {});
    });
  }

  // ============================================================
  // 服务动作
  // ============================================================
  Future<void> _addService() async {
    if (_installedDistro == null) {
      SmartDialog.showToast('请先安装沙盒环境');
      return;
    }
    final svc = await showSandboxServiceFormDialog(context);
    if (svc == null) return;
    await SandboxServiceStore.addOrUpdate(svc);
    await _refreshState();
    SmartDialog.showToast('服务已添加');
  }

  Future<void> _editService(SandboxService existing) async {
    final updated = await showSandboxServiceFormDialog(
      context,
      existing: existing,
    );
    if (updated == null) return;
    if (SandboxServiceManager.instance.isRunning(existing.id)) {
      await SandboxServiceManager.instance.stop(existing.id);
    }
    await SandboxServiceStore.addOrUpdate(updated);
    await _refreshState();
    SmartDialog.showToast('已保存');
  }

  Future<void> _deleteService(SandboxService svc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务'),
        content: Text('确定删除「${svc.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SandboxServiceManager.instance.remove(svc.id);
    await SandboxServiceStore.remove(svc.id);
    await _refreshState();
    SmartDialog.showToast('已删除');
  }

  Future<void> _startService(SandboxService svc) async {
    final distroId = _installedDistro;
    if (distroId == null) {
      SmartDialog.showToast('请先安装沙盒环境');
      return;
    }
    final healthType = (svc.port != null && svc.port! > 0)
        ? SandboxHealthType.tcp
        : SandboxHealthType.process;
    try {
      await SandboxServiceManager.instance.start(
        svc,
        distroId: distroId,
        healthType: healthType,
        healthPath: '/',
        maxRestart: 1,
      );
    } catch (e) {
      SmartDialog.showToast('启动失败：$e');
    }
  }

  Future<void> _stopService(SandboxService svc) async {
    await SandboxServiceManager.instance.stop(svc.id);
  }

  Future<void> _openServiceWeb(SandboxService svc) async {
    if (svc.port == null || svc.port! <= 0) return;
    final url = 'http://localhost:${svc.port}/';
    Get.to(() => WebviewPage(url: url, title: svc.name));
  }

  Future<void> _createSampleService() async {
    if (_installedDistro == null) {
      SmartDialog.showToast('请先安装沙盒环境');
      return;
    }
    final exists = _services.any((s) => s.name == '示例保活服务');
    if (exists) {
      SmartDialog.showToast('已存在「示例保活服务」，请直接查看日志');
      return;
    }
    final svc = SandboxService(
      id: 'sbx-${DateTime.now().millisecondsSinceEpoch}',
      name: '示例保活服务',
      // raw string，避免 $(date) 被当成 Dart 插值
      command:
          r'while true; do echo "[sample] alive $(date)"; sleep 10; done',
      port: null,
      remark: '最小存活示例：每 10 秒输出一次心跳，可在运行日志中查看。',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      autostart: false,
    );
    await SandboxServiceStore.addOrUpdate(svc);
    await _refreshState();
    SmartDialog.showToast('示例服务已创建，可在下方列表中启动');
  }

  // ============================================================
  // build
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Style.safeSpace,
          topInset + Style.safeSpace,
          Style.safeSpace,
          Style.safeSpace + 24,
        ),
        children: [
          _buildHeader(colorScheme),
          const SizedBox(height: 12),
          if (!_runtimeReady) ...[
            _buildRuntimeDependencyCard(colorScheme),
            const SizedBox(height: 12),
          ],
          _buildEnvCard(colorScheme),
          const SizedBox(height: 12),
          _buildTerminalCard(colorScheme),
          const SizedBox(height: 12),
          _buildServiceCard(colorScheme),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
          tooltip: '返回',
        ),
        const SizedBox(width: 4),
        Text(
          'Linux 沙盒',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '实验',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRuntimeDependencyCard(ColorScheme colorScheme) {
    final isAndroid = Platform.isAndroid;
    return _SandboxCard(
      colorScheme: colorScheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.block, color: colorScheme.error, size: 20),
              const SizedBox(width: 8),
              Text(
                isAndroid ? '缺少沙盒运行时' : '当前平台不支持',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isAndroid
                ? 'Linux 沙盒依赖插件「Linux 沙盒运行时（PRoot）」，请先到插件中心安装。'
                : 'Linux 沙盒仅支持 Android 设备。',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          if (isAndroid) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await Get.toNamed(AppPages.pluginCenter);
                  await _refreshState();
                },
                icon: const Icon(Icons.download, size: 18),
                label: const Text('去插件中心安装'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnvCard(ColorScheme colorScheme) {
    final enabled = _runtimeReady && !_installingRootfs;

    return _SandboxCard(
      colorScheme: colorScheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.inventory_2_outlined, '沙盒环境', colorScheme),
          const SizedBox(height: 8),
          Text(
            '安装一个完整 Linux 环境到应用私有目录（免 root，PRoot 用户态隔离）',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kDistros
                .map((d) => _distroChip(
                      label: '${d.name} ${d.version}'
                          '（${(d.sizeBytes / 1024 / 1024).toStringAsFixed(1)}MB）',
                      distro: d,
                      enabled: enabled,
                      colorScheme: colorScheme,
                    ))
                .toList(),
          ),
          if (_installedDistro != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.check_circle,
                    size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '已就绪：$_installedDistro',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    final distro = kDistros.firstWhere(
                      (d) => d.id == _installedDistro,
                      orElse: () => kDistros.first,
                    );
                    _installRootfs(distro);
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重装'),
                ),
                OutlinedButton.icon(
                  onPressed: _uninstallRootfs,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('卸载'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _distroChip({
    required String label,
    required DistroInfo distro,
    required bool enabled,
    required ColorScheme colorScheme,
  }) {
    final selected = _installedDistro == distro.id;
    return InkWell(
      onTap: enabled
          ? () {
              if (selected) return;
              _installRootfs(distro);
            }
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: !enabled
              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.2)
              : selected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: !enabled
                ? colorScheme.outline
                : selected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalCard(ColorScheme colorScheme) {
    final enabled = _runtimeReady && _installedDistro != null;
    final active = _terminalActive;

    return _SandboxCard(
      colorScheme: colorScheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _cardHeader(Icons.terminal, '沙盒终端', colorScheme),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                active ? '会话中' : '未启动',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '进入沙盒环境持续执行命令：cd 生效、装完即用、环境变量保持',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          if (!active) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: enabled ? _startTerminal : null,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('启动终端'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              height: 260,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: Style.mdRadius,
              ),
              padding: const EdgeInsets.all(10),
              child: Scrollbar(
                controller: _terminalScrollCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _terminalScrollCtrl,
                  child: SelectableText(
                    _terminalBuffer.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                      color: Color(0xFFD4D4D4),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _terminalInputCtrl,
                    focusNode: _terminalInputFocus,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '输入命令（如 apk add nodejs）…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendCommand(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sendCommand,
                  child: const Text('发送'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _endTerminal,
                  child: const Text('结束'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServiceCard(ColorScheme colorScheme) {
    final enabled = _runtimeReady && _installedDistro != null;

    return _SandboxCard(
      colorScheme: colorScheme,
      child: Obx(() {
        SandboxServiceManager.instance.revision.value;

        final services = _services;
        final runningCount = services
            .where((s) => SandboxServiceManager.instance.isRunning(s.id))
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _cardHeader(Icons.dns_outlined, '沙盒服务', colorScheme),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '运行中 $runningCount · 共 ${services.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '把沙盒内装的软件注册为常驻服务（服务页统一启停/探活/自启）',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: enabled ? _addService : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('自定义'),
                ),
                // 导入项目
                OutlinedButton.icon(
                  onPressed: enabled ? _importProject : null,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('导入项目'),
                ),
                FilledButton.icon(
                  onPressed: enabled ? _createSampleService : null,
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('一键创建示例服务'),
                ),
              ],
            ),
            if (services.isEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.2),
                  borderRadius: Style.mdRadius,
                ),
                child: Text(
                  '暂无服务。可以点「一键创建示例服务」体验，也可以点「自定义」添加。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                    height: 1.5,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              ...services.map(
                (svc) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildServiceTile(svc, colorScheme, enabled),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  Widget _buildServiceTile(
    SandboxService svc,
    ColorScheme colorScheme,
    bool envReady,
  ) {
    final st = SandboxServiceManager.instance.stateOf(svc.id);
    final running = st.status == SandboxServiceStatus.running;
    final starting = st.status == SandboxServiceStatus.starting;
    final hasPort = svc.port != null && svc.port! > 0;

    Color statusColor;
    switch (st.status) {
      case SandboxServiceStatus.running:
        statusColor = Colors.green;
        break;
      case SandboxServiceStatus.starting:
        statusColor = Colors.orange;
        break;
      case SandboxServiceStatus.error:
        statusColor = colorScheme.error;
        break;
      case SandboxServiceStatus.stopped:
        statusColor = colorScheme.outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: Style.mdRadius,
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined,
                  size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  svc.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  starting ? '启动中' : st.status.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            svc.command,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasPort) ...[
            const SizedBox(height: 4),
            Text(
              '端口 ${svc.port}',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.outline,
              ),
            ),
          ],
          if (svc.remark != null && svc.remark!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              svc.remark!,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.outline,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!running && !starting)
                _smallBtn(
                  icon: Icons.play_arrow,
                  label: '启动',
                  onTap: envReady ? () => _startService(svc) : null,
                  color: colorScheme.primary,
                )
              else
                _smallBtn(
                  icon: Icons.stop,
                  label: '停止',
                  onTap: () => _stopService(svc),
                  color: colorScheme.error,
                ),
              _smallBtn(
                icon: Icons.description_outlined,
                label: '日志',
                onTap: () => showSandboxServiceLogSheet(context, svc),
              ),
              if (hasPort)
                _smallBtn(
                  icon: Icons.open_in_browser,
                  label: '打开 Web',
                  onTap: running ? () => _openServiceWeb(svc) : null,
                ),
              _smallBtn(
                icon: Icons.edit_outlined,
                label: '编辑',
                onTap: () => _editService(svc),
              ),
              _smallBtn(
                icon: Icons.delete_outline,
                label: '删除',
                onTap: () => _deleteService(svc),
                color: colorScheme.error,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final c = onTap == null
        ? colorScheme.outline.withValues(alpha: 0.4)
        : (color ?? colorScheme.outline);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 12, color: c)),
          ],
        ),
      ),
    );
  }

  Widget _cardHeader(IconData icon, String title, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _SandboxCard extends StatelessWidget {
  final Widget child;
  final ColorScheme colorScheme;
  const _SandboxCard({required this.child, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: Style.mdRadius,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}