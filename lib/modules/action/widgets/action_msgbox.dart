// lib/modules/action/widgets/action_msgbox.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../models/action_config.dart';
import '../models/button_type.dart';
import '../utils/action_parser.dart';

/// 消息弹窗 Action
/// 严格对应 DrPlayer 的 MsgBoxAction.vue
///
/// 功能：
/// - 5种图标类型：info, success, warning, error, question
/// - 消息内容（支持简单 HTML）
/// - 详细信息
/// - 列表展示
/// - 图片展示
/// - 二维码展示
/// - 进度条
/// - 超时自动关闭
class MsgBoxAction extends StatefulWidget {
  const MsgBoxAction({
    super.key,
    required this.config,
    required this.visible,
    this.module = '',
    this.extend,
    this.apiUrl,
    this.onSubmit,
    this.onCancel,
    this.onClose,
    this.onAction,
    this.onSpecialAction,
    this.onToast,
    this.onReset,
  });

  final ActionConfig config;
  final bool visible;
  final String module;
  final dynamic extend;
  final String? apiUrl;

  final void Function(dynamic)? onSubmit;
  final VoidCallback? onCancel;
  final VoidCallback? onClose;
  final void Function(dynamic)? onAction;
  final void Function(String, dynamic)? onSpecialAction;
  final void Function(String, String)? onToast;
  final VoidCallback? onReset;

  @override
  State<MsgBoxAction> createState() => _MsgBoxActionState();
}

class _MsgBoxActionState extends State<MsgBoxAction> {
  Timer? _timeoutTimer;
  int _timeLeft = 0;
  double _progress = 0.0;
  Timer? _progressTimer;

  bool get _showIcon {
    final icon = widget.config.iconType;
    return icon != null && icon.isNotEmpty && icon != 'plain';
  }

  String get _iconType {
    final type = widget.config.iconType?.toLowerCase() ?? 'info';
    if (['info', 'success', 'warning', 'error', 'question'].contains(type)) {
      return type;
    }
    return 'info';
  }

  IconData get _iconData {
    switch (_iconType) {
      case 'success':
        return Icons.check_circle_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'error':
        return Icons.error_outline;
      case 'question':
        return Icons.help_outline;
      default:
        return Icons.info_outline;
    }
  }

  bool get _showOkButton => widget.config.button.showOk;
  bool get _showCancelButton => widget.config.button.showCancel;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      _startTimeout();
      if (widget.config.showProgress) {
        _startProgress();
      }
    }
  }

  @override
  void didUpdateWidget(MsgBoxAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _startTimeout();
        if (widget.config.showProgress) {
          _startProgress();
        }
      } else {
        _stopTimeout();
        _stopProgress();
      }
    }
  }

  @override
  void dispose() {
    _stopTimeout();
    _stopProgress();
    super.dispose();
  }

  void _startTimeout() {
    _stopTimeout();
    if (widget.config.timeout <= 0) return;

    _timeLeft = widget.config.timeout;
    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) {
          timer.cancel();
          _handleClose();
        }
      });
    });
  }

  void _stopTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _timeLeft = 0;
  }

  void _startProgress() {
    _stopProgress();
    if (!widget.config.showProgress) return;

    final duration = widget.config.progressDuration;
    final interval = 50;
    final step = 100 / duration * interval;

    _progress = 0.0;
    _progressTimer = Timer.periodic(Duration(milliseconds: interval), (timer) {
      setState(() {
        _progress += step;
        if (_progress >= 100) {
          _progress = 100;
          timer.cancel();
          _handleSubmit();
        }
      });
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _progress = 0.0;
  }

  String _formatMessage(String? text) {
    if (text == null || text.isEmpty) return '';
    return text
        .replaceAll('\n', '\n')
        .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'<b>$1</b>')
        .replaceAll(RegExp(r'\*(.*?)\*'), r'<i>$1</i>')
        .replaceAll(RegExp(r'`(.*?)`'), r'<code>$1</code>');
  }

  void _handleSubmit() {
    widget.onSubmit?.call({'action': 'ok'});
    widget.onClose?.call();
  }

  void _handleCancel() {
    widget.onCancel?.call();
    widget.onClose?.call();
  }

  void _handleClose() {
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 图标
        if (_showIcon) _buildIcon(context),

        // 消息
        if (widget.config.msg != null && widget.config.msg!.isNotEmpty)
          _buildMessage(context),

        // 详情
        if (widget.config.detail != null && widget.config.detail!.isNotEmpty)
          _buildDetail(context),

        // 列表
        if (widget.config.list != null && widget.config.list!.isNotEmpty)
          _buildList(context),

        // 图片
        if (widget.config.imageUrl != null && widget.config.imageUrl!.isNotEmpty)
          _buildImage(context),

        // 二维码
        if (widget.config.qrcode != null && widget.config.qrcode!.isNotEmpty)
          _buildQrcode(context),

        // 进度条
        if (widget.config.showProgress) _buildProgress(context),

        // 超时
        if (widget.config.timeout > 0 && _timeLeft > 0) _buildTimeout(context),

        // 按钮
        _buildButtons(context),
      ],
    );
  }

  Widget _buildIcon(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color iconColor;
    switch (_iconType) {
      case 'success':
        iconColor = colorScheme.primary;
        break;
      case 'warning':
        iconColor = colorScheme.tertiary;
        break;
      case 'error':
        iconColor = colorScheme.error;
        break;
      case 'question':
        iconColor = colorScheme.secondary;
        break;
      default:
        iconColor = colorScheme.primary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _iconData,
        size: 48,
        color: iconColor,
      ),
    );
  }

  Widget _buildMessage(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final message = _formatMessage(widget.config.msg);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        message.replaceAll(RegExp(r'<[^>]*>'), ''),
        style: TextStyle(
          fontSize: 14,
          color: colorScheme.onSurface,
          height: 1.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              widget.config.detail!,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: widget.config.list!.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6, right: 8),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          widget.config.imageUrl!,
          height: widget.config.imageHeight ?? 200,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              height: widget.config.imageHeight ?? 200,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: widget.config.imageHeight ?? 200,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, size: 48, color: colorScheme.outline),
                  const SizedBox(height: 8),
                  Text('图片加载失败',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildQrcode(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final qrcodeUrl = ActionParser.generateQRCodeUrl(
      widget.config.qrcode!,
      widget.config.qrcodeSize ?? '200x200',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.network(
            qrcodeUrl,
            width: 150,
            height: 150,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 150,
                height: 150,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner, size: 48, color: colorScheme.outline),
                    const SizedBox(height: 8),
                    Text('二维码加载失败',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            widget.config.qrcode!,
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final percent = _progress.clamp(0.0, 100.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.config.progressText ?? '进度',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${percent.round()}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.errorContainer.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: colorScheme.error),
          const SizedBox(width: 4),
          Text(
            '$_timeLeft秒后自动关闭',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final children = <Widget>[];

    if (_showCancelButton) {
      children.add(
        TextButton(
          onPressed: _handleCancel,
          child: Text(widget.config.cancelText ?? '取消'),
        ),
      );
    }

    if (_showOkButton) {
      children.add(
        ElevatedButton(
          onPressed: _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
          child: Text(widget.config.okText ?? '确定'),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: children,
      ),
    );
  }
}