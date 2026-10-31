// lib/modules/sandbox/widgets/rootfs_install_dialog.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/sandbox/models/rootfs_progress.dart';
import 'package:yuanying/modules/sandbox/services/rootfs_manager.dart';

/// 显示 rootfs 安装进度对话框。
///
/// [mirrorLabel] 为 null 表示 auto（全部镜像顺序 fallback）；
///               非 null 表示只用指定镜像（如 '清华'），失败不 fallback。
///
/// 返回 true 表示安装成功；false 表示失败或被取消。
Future<bool> showRootfsInstallDialog({
  required BuildContext context,
  required DistroInfo distro,
  String? mirrorLabel,
}) async {
  final progressNotifier = ValueNotifier<RootfsProgress>(
    const RootfsProgress(stage: RootfsStage.checking),
  );
  final cancelToken = CancelToken();

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

  void doCancel() {
    if (finished || cancelled) return;
    cancelled = true;
    if (!cancelToken.isCancelled) {
      cancelToken.cancel('用户取消');
    }
    closeDialog();
    SmartDialog.showToast('已取消安装');
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: false,
    builder: (ctx) {
      dialogCtx = ctx;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!finished && !cancelled) doCancel();
        },
        child: _RootfsProgressDialog(
          distro: distro,
          progressNotifier: progressNotifier,
          onCancel: doCancel,
        ),
      );
    },
  );

  await Future.delayed(const Duration(milliseconds: 50));

  try {
    await RootfsManager.instance.install(
      distro,
      onProgress: (p) {
        progressNotifier.value = p;
      },
      cancelToken: cancelToken,
      mirrorLabel: mirrorLabel,
    );
    finished = true;
    progressNotifier.value = const RootfsProgress(stage: RootfsStage.done);
    await Future.delayed(const Duration(milliseconds: 600));
    closeDialog();
    SmartDialog.showToast('${distro.name} 安装完成');
    return true;
  } on RootfsCancelledException {
    finished = true;
    closeDialog();
    return false;
  } catch (e) {
    finished = true;
    if (!cancelled) {
      progressNotifier.value = const RootfsProgress(stage: RootfsStage.failed);
      await Future.delayed(const Duration(milliseconds: 300));
      closeDialog();
      SmartDialog.showToast('安装失败：${_humanizeError(e)}');
    }
    return false;
  } finally {
    await Future.delayed(const Duration(milliseconds: 300));
    progressNotifier.dispose();
  }
}

/// 把 dio / network 异常转成人话
String _humanizeError(Object e) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return '网络超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络';
      case DioExceptionType.badResponse:
        return '服务器响应异常（HTTP ${e.response?.statusCode ?? '?'}）';
      case DioExceptionType.cancel:
        return '已取消';
      default:
        return e.message ?? e.toString();
    }
  }
  return e.toString();
}

class _RootfsProgressDialog extends StatefulWidget {
  final DistroInfo distro;
  final ValueNotifier<RootfsProgress> progressNotifier;
  final VoidCallback onCancel;

  const _RootfsProgressDialog({
    required this.distro,
    required this.progressNotifier,
    required this.onCancel,
  });

  @override
  State<_RootfsProgressDialog> createState() => _RootfsProgressDialogState();
}

class _RootfsProgressDialogState extends State<_RootfsProgressDialog> {
  int _lastReceived = 0;
  DateTime _lastTime = DateTime.now();
  double _speedBytesPerSec = 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: Row(
        children: [
          Icon(Icons.downloading, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '安装 ${widget.distro.name} ${widget.distro.version}',
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
        width: 400,
        child: ValueListenableBuilder<RootfsProgress>(
          valueListenable: widget.progressNotifier,
          builder: (context, p, _) {
            if (p.stage == RootfsStage.downloading) {
              final now = DateTime.now();
              final dt = now.difference(_lastTime).inMilliseconds;
              if (dt >= 500) {
                final delta = p.received - _lastReceived;
                if (delta >= 0) {
                  _speedBytesPerSec = delta / (dt / 1000.0);
                }
                _lastReceived = p.received;
                _lastTime = now;
              }
            }

            final showPercent = p.hasDeterminateProgress;
            final isDone = p.stage == RootfsStage.done;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isDone ? Colors.green : colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      p.stageLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDone ? Colors.green : colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    if (showPercent)
                      Text(
                        '${(p.percent * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (p.stage == RootfsStage.downloading)
                  LinearProgressIndicator(
                    value: showPercent ? p.percent : null,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  )
                else if (isDone)
                  LinearProgressIndicator(
                    value: 1,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    color: Colors.green,
                  )
                else
                  LinearProgressIndicator(
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                const SizedBox(height: 12),
                if (showPercent)
                  Row(
                    children: [
                      Text(
                        '${_fmt(p.received)} / ${_fmt(p.total)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: colorScheme.outline,
                        ),
                      ),
                      const Spacer(),
                      if (_speedBytesPerSec > 0)
                        Text(
                          '${_fmt(_speedBytesPerSec.round())}/s',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: colorScheme.outline,
                          ),
                        ),
                    ],
                  )
                else if (p.total > 0)
                  Text(
                    '共 ${_fmt(p.total)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  p.detail ?? p.stageDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                if (p.stage == RootfsStage.extracting) ...[
                  const SizedBox(height: 6),
                  Text(
                    '提示：解压过程在主线程执行，界面可能短暂卡顿，属正常现象',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.outline,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.outline,
          ),
          child: const Text('取消'),
        ),
      ],
    );
  }

  String _fmt(int bytes) {
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