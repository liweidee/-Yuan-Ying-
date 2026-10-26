// lib/modules/plugin_center/widgets/install_progress_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/models/market_entry.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';

/// 下载/安装进度弹窗
Future<void> showInstallProgressDialog({
  required BuildContext context,
  required MarketEntry entry,
  required InstallCancelToken token,
  required Future<void> Function(void Function(InstallProgress) onProgress)
      task,
}) async {
  final progressNotifier = ValueNotifier<InstallProgress>(
    const InstallProgress(stage: InstallStage.idle),
  );

  bool finished = false;
  bool cancelled = false;
  bool dialogClosed = false;

  BuildContext? dialogCtx;

  void closeDialog() {
    if (dialogClosed) return;
    dialogClosed = true;
    final ctx = dialogCtx;
    if (ctx != null && Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: false,
    builder: (ctx) {
      dialogCtx = ctx;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!finished && !cancelled) {
            cancelled = true;
            token.cancel();
            closeDialog();
            SmartDialog.showToast('已取消安装');
          }
        },
        child: _InstallProgressDialogBody(
          entry: entry,
          progressNotifier: progressNotifier,
          onCancel: () {
            if (finished || cancelled) return;
            cancelled = true;
            token.cancel();
            closeDialog();
            SmartDialog.showToast('已取消安装');
          },
        ),
      );
    },
  );

  await Future.delayed(const Duration(milliseconds: 50));

  try {
    await task((p) {
      progressNotifier.value = p;
    });
    finished = true;
    progressNotifier.value = const InstallProgress(stage: InstallStage.done);
    await Future.delayed(const Duration(milliseconds: 600));
    closeDialog();

    // 按类型给不同的成功文案（只弹一次）
    SmartDialog.showToast(_successMessage(entry));
  } catch (e) {
    finished = true;
    progressNotifier.value = const InstallProgress(stage: InstallStage.failed);
    await Future.delayed(const Duration(milliseconds: 400));
    closeDialog();
    if (!cancelled) {
      SmartDialog.showToast('安装失败：$e');
    }
  } finally {
    await Future.delayed(const Duration(milliseconds: 300));
    progressNotifier.dispose();
  }
}

/// 按类型给不同的成功文案
String _successMessage(MarketEntry entry) {
  switch (entry.type) {
    case 'live':
      return '直播配置导入成功，需要手动切换下';
    case 'source':
      return '源码包导入成功';
    case 'server':
      return '${entry.name} 服务已创建';
    default:
      return '${entry.name} 安装完成';
  }
}

class _InstallProgressDialogBody extends StatelessWidget {
  final MarketEntry entry;
  final ValueNotifier<InstallProgress> progressNotifier;
  final VoidCallback onCancel;

  const _InstallProgressDialogBody({
    required this.entry,
    required this.progressNotifier,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: Row(
        children: [
          Icon(Icons.downloading, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '安装 ${entry.name}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: ValueListenableBuilder<InstallProgress>(
          valueListenable: progressNotifier,
          builder: (context, p, _) {
            final showPercent =
                p.stage == InstallStage.downloading && p.total > 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '版本：v${entry.version}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                if (p.stage == InstallStage.downloading)
                  LinearProgressIndicator(
                    value: showPercent ? p.percent : null,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  )
                else
                  const LinearProgressIndicator(
                    minHeight: 6,
                    borderRadius: BorderRadius.all(Radius.circular(3)),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.stage.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (showPercent)
                      Text(
                        '${(p.percent * 100).toStringAsFixed(1)}%'
                        '  (${_fmtBytes(p.received)}/${_fmtBytes(p.total)})',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      )
                    else if (p.stage == InstallStage.downloading &&
                        entry.sizeBytes > 0)
                      Text(
                        '共 ${entry.sizeText}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(
            '取消',
            style: TextStyle(color: colorScheme.outline),
          ),
        ),
      ],
    );
  }

  static String _fmtBytes(int bytes) {
    if (bytes <= 0) return '0B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = bytes.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)}${units[i]}';
  }
}