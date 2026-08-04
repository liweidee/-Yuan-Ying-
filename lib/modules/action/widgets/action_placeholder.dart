// lib/modules/action/widgets/action_placeholder.dart
import 'package:flutter/material.dart';

/// 占位 Action 组件
/// 当具体 Action 组件尚未实现时使用
class ActionPlaceholder extends StatelessWidget {
  const ActionPlaceholder({
    super.key,
    required this.actionType,
    this.onSubmit,
    this.onCancel,
    this.onClose,
    this.onAction,
    this.onSpecialAction,
    this.onToast,
    this.onReset,
  });

  final String actionType;
  final VoidCallback? onSubmit;
  final VoidCallback? onCancel;
  final VoidCallback? onClose;
  final void Function(dynamic)? onAction;
  final void Function(String, dynamic)? onSpecialAction;
  final void Function(String, String)? onToast;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction,
                size: 48,
                color: colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Action 类型尚未实现',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'type: $actionType',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: onCancel,
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onSubmit,
              child: const Text('确定'),
            ),
          ],
        ),
      ],
    );
  }
}