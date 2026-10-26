// lib/modules/local_php_t4/views/php_t4_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/local_php_t4/controllers/php_t4_controller.dart';
import 'package:yuanying/modules/local_php_t4/models/php_t4_source.dart';
import 'package:yuanying/modules/local_php_t4/services/php_t4_service.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';

class PhpT4Page extends StatefulWidget {
  const PhpT4Page({super.key});

  @override
  State<PhpT4Page> createState() => _PhpT4PageState();
}

class _PhpT4PageState extends State<PhpT4Page> {
  final _ctrl = Get.put(PhpT4Controller());
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'PHP-T4 本地服务',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          Obx(() => _ctrl.loading.value
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh, size: 22),
                  onPressed: _ctrl.refresh,
                )),
          Obx(() {
            final canUpload = !_ctrl.uploading.value && _ctrl.hasSkeleton.value;
            return IconButton(
              tooltip: _ctrl.hasSkeleton.value
                  ? '上传 .php 文件'
                  : '骨架未安装，无法上传',
              icon: _ctrl.uploading.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.file_upload_outlined,
                      size: 22,
                      color: canUpload
                          ? colorScheme.onSurface
                          : colorScheme.outline.withValues(alpha: 0.4),
                    ),
              onPressed: canUpload ? _ctrl.pickAndUpload : null,
            );
          }),
          IconButton(
            tooltip: '打开源目录',
            icon: const Icon(Icons.folder_open, size: 22),
            onPressed: _ctrl.openDir,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildServiceCard(colorScheme),
          _buildDirBar(colorScheme),
          _buildSearchBar(colorScheme),
          _buildHeader(colorScheme),
          Expanded(child: _buildList(colorScheme)),
        ],
      ),
    );
  }

  // ===== 服务控制卡片 =====
  Widget _buildServiceCard(ColorScheme colorScheme) {
    return Obx(() {
      // 订阅服务状态变更
      ServiceManager.instance.revision.value;

      final status = PhpT4Service.status;
      final running = status == ServiceStatus.running;
      final port = PhpT4Service.currentPort;
      final runtimeError = PhpT4Service.checkRuntime();
      final missing = _ctrl.missingFiles;
      final canStart = runtimeError == null && missing.isEmpty;

      Color statusColor = colorScheme.outline;
      String statusLabel = '已停止';
      switch (status) {
        case ServiceStatus.running:
          statusColor = Colors.green;
          statusLabel = '运行中';
          break;
        case ServiceStatus.starting:
          statusColor = Colors.orange;
          statusLabel = '启动中';
          break;
        case ServiceStatus.error:
          statusColor = colorScheme.error;
          statusLabel = '异常';
          break;
        case ServiceStatus.stopped:
        default:
          statusColor = colorScheme.outline;
          statusLabel = '已停止';
          break;
      }

      // 端口显示
      final preferred = _ctrl.preferredPort.value;
      final String portText;
      if (running && port != null) {
        portText = '端口 $port';
      } else if (preferred > 0) {
        portText = '指定端口 $preferred';
      } else {
        portText = '端口自动（${PhpT4Service.defaultPort}+）';
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: Style.mdRadius,
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== 状态行 =====
              Row(
                children: [
                  Icon(Icons.dns_outlined,
                      size: 18, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  const Text('服务状态',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      portText,
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.outline),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (runtimeError != null) ...[
                const SizedBox(height: 8),
                _errorBox(colorScheme, runtimeError),
              ],
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 8),
                _skeletonMissingBox(colorScheme, missing),
              ],
              const SizedBox(height: 10),
              // ===== 操作按钮 =====
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (!running)
                    _actionButton(
                      icon: _ctrl.starting.value ? null : Icons.play_arrow,
                      label: '启动',
                      color: colorScheme.primary,
                      onTap: (canStart && !_ctrl.starting.value)
                          ? _ctrl.startService
                          : null,
                      loading: _ctrl.starting.value,
                    )
                  else
                    _actionButton(
                      icon: _ctrl.stopping.value ? null : Icons.stop,
                      label: '停止',
                      color: colorScheme.error,
                      onTap: !_ctrl.stopping.value ? _ctrl.stopService : null,
                      loading: _ctrl.stopping.value,
                    ),
                  _actionButton(
                    icon: Icons.copy,
                    label: '复制配置地址',
                    color: colorScheme.primary,
                    onTap: (running && port != null)
                        ? _ctrl.copyConfigUrl
                        : null,
                  ),
                  _actionButton(
                    icon: Icons.tune,
                    label: preferred > 0 ? '端口 $preferred' : '端口自动',
                    color: colorScheme.primary,
                    onTap: running ? null : _showPortDialog,
                  ),
                  _actionButton(
                    icon: Icons.description_outlined,
                    label: '运行日志',
                    color: colorScheme.primary,
                    onTap: _ctrl.showLogs,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _errorBox(ColorScheme colorScheme, String msg) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 14, color: colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(fontSize: 11, color: colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonMissingBox(ColorScheme colorScheme, List<String> missing) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 14, color: colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PHP-T4 骨架包缺失 ${missing.length} 个文件：',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  missing.join('、'),
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '请把完整骨架放入源目录后再上传/启动',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData? icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    final enabled = onTap != null;
    final effectiveColor = enabled
        ? color
        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: effectiveColor, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: effectiveColor),
              )
            else if (icon != null)
              Icon(icon, size: 16, color: effectiveColor),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: effectiveColor)),
          ],
        ),
      ),
    );
  }

  // ===== 端口设置弹窗 =====
  Future<void> _showPortDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    final current = _ctrl.preferredPort.value;
    final ctrl = TextEditingController(text: current > 0 ? '$current' : '');
    bool auto = current == 0;
    String? error;

    final result = await showDialog<({bool auto, int? port})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
          backgroundColor: colorScheme.surface,
          title: const Text(
            '端口设置',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '自动分配：从 ${PhpT4Service.defaultPort} 开始依次尝试 +1，共 10 个'
                  '（${PhpT4Service.defaultPort}~${PhpT4Service.defaultPort + 9}）。\n'
                  '指定端口：优先使用，被占用时会启动失败并提示。',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动分配'),
                  value: auto,
                  onChanged: (v) => setState(() {
                    auto = v;
                    error = null;
                  }),
                ),
                if (!auto) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '端口（1-65535）',
                      hintText: '例如 5788',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: error,
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
              onPressed: () {
                if (auto) {
                  Navigator.pop(ctx, (auto: true, port: null));
                } else {
                  final v = int.tryParse(ctrl.text.trim());
                  if (v == null || v <= 0 || v > 65535) {
                    setState(() => error = '端口必须为 1~65535 的整数');
                    return;
                  }
                  Navigator.pop(ctx, (auto: false, port: v));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    await _ctrl.setPreferredPort(result.auto ? null : result.port);
    if (mounted) {
      final newValue = _ctrl.preferredPort.value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue > 0 ? '端口已设为 $newValue' : '端口已改为自动分配',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ===== 目录提示 =====
  Widget _buildDirBar(ColorScheme colorScheme) {
    return FutureBuilder<String>(
      future: _ctrl.dirPath(),
      builder: (context, snap) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        child: Text(
          '目录 ${snap.data ?? '...'}',
          style: TextStyle(fontSize: 11, color: colorScheme.outline),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  // ===== 搜索 =====
  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索源名称 / 文件名',
          prefixIcon: const Icon(Icons.search, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) => _ctrl.search.value = v,
      ),
    );
  }

  // ===== 头部统计 =====
  Widget _buildHeader(ColorScheme colorScheme) {
    return Obx(() {
      final count = _ctrl.filtered.length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            Text('本地源',
                style: TextStyle(fontSize: 12, color: colorScheme.outline)),
            const SizedBox(width: 8),
            Text('$count 个',
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    });
  }

  // ===== 列表 =====
  Widget _buildList(ColorScheme colorScheme) {
    return Obx(() {
      if (_ctrl.loading.value && _ctrl.sources.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      final list = _ctrl.filtered;
      if (list.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description_outlined,
                  size: 64, color: colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                _ctrl.hasSkeleton.value ? '暂无 PHP-T4 源' : '骨架未安装',
                style: TextStyle(color: colorScheme.outline),
              ),
              const SizedBox(height: 8),
              Text(
                _ctrl.hasSkeleton.value
                    ? '点击右上角上传按钮添加 *.php 文件'
                    : '请先把完整骨架包放入源目录',
                style:
                    TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
            ],
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(Style.safeSpace),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: Style.cardSpace),
        itemBuilder: (context, i) => _buildCard(context, list[i]),
      );
    });
  }

  Widget _buildCard(BuildContext context, PhpT4Source s) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: Style.mdRadius,
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.15),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                borderRadius: Style.mdRadius,
              ),
              child: Icon(Icons.code, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.sizeText} · ${s.fileName}',
                    style: TextStyle(
                        fontSize: 11, color: colorScheme.outline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '删除',
              icon: Icon(Icons.delete_outline,
                  size: 20, color: colorScheme.error),
              onPressed: () => _confirmDelete(s),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(PhpT4Source s) async {
    final colorScheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        backgroundColor: colorScheme.surface,
        title: const Text('删除源文件'),
        content: Text('确定删除 ${s.fileName} 吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await _ctrl.deleteSource(s);
  }
}