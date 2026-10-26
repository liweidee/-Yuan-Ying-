// lib/modules/plugin_center/widgets/service_log_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';

Future<void> showServiceLogSheet(
  BuildContext context,
  ServiceConfig config,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ServiceLogSheet(config: config),
  );
}

class _ServiceLogSheet extends StatefulWidget {
  final ServiceConfig config;

  const _ServiceLogSheet({required this.config});

  @override
  State<_ServiceLogSheet> createState() => _ServiceLogSheetState();
}

class _ServiceLogSheetState extends State<_ServiceLogSheet> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: Style.bottomSheetRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖拽条
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '运行日志 · ${widget.config.name}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 日志区
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Obx(() {
                // 订阅此服务的日志版本号
                ServiceManager.instance.logVersionOf(widget.config.id).value;
                final logs =
                    ServiceManager.instance.getLogs(widget.config.id);

                // 新日志到达时自动滚到底部
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollCtrl.hasClients) {
                    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                  }
                });

                return Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: Style.mdRadius,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: logs.isEmpty
                      ? Center(
                          child: Text(
                            '暂无日志（启动服务后此处显示 stdout/stderr）',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollCtrl,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _scrollCtrl,
                            child: SelectableText(
                              logs.join('\n'),
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Color(0xFFD4D4D4),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                );
              }),
            ),
          ),
          const Divider(height: 1),
          // 底部操作栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    final logs =
                        ServiceManager.instance.getLogs(widget.config.id);
                    if (logs.isEmpty) {
                      SmartDialog.showToast('暂无日志');
                      return;
                    }
                    Clipboard.setData(ClipboardData(text: logs.join('\n')));
                    SmartDialog.showToast('已复制');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () {
                    ServiceManager.instance.clearLogs(widget.config.id);
                    SmartDialog.showToast('已清空');
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('清空'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}