// lib/modules/sandbox/widgets/sandbox_service_log_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/sandbox/models/sandbox_service.dart';
import 'package:yuanying/modules/sandbox/services/sandbox_service_manager.dart';

Future<void> showSandboxServiceLogSheet(
  BuildContext context,
  SandboxService service,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SandboxServiceLogSheet(service: service),
  );
}

class _SandboxServiceLogSheet extends StatefulWidget {
  final SandboxService service;
  const _SandboxServiceLogSheet({required this.service});

  @override
  State<_SandboxServiceLogSheet> createState() =>
      _SandboxServiceLogSheetState();
}

class _SandboxServiceLogSheetState extends State<_SandboxServiceLogSheet> {
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
                Expanded(
                  child: Text(
                    '运行日志 · ${widget.service.name}',
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
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Obx(() {
                SandboxServiceManager.instance.revision.value;
                final st = SandboxServiceManager.instance
                    .stateOf(widget.service.id);
                final logs = st.logs;

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
                            '暂无日志',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    final st = SandboxServiceManager.instance
                        .stateOf(widget.service.id);
                    if (st.logs.isEmpty) {
                      SmartDialog.showToast('暂无日志');
                      return;
                    }
                    Clipboard.setData(
                        ClipboardData(text: st.logs.join('\n')));
                    SmartDialog.showToast('已复制');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () {
                    SandboxServiceManager.instance
                        .stateOf(widget.service.id)
                        .clearLogs();
                    SandboxServiceManager.instance.revision.value++;
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