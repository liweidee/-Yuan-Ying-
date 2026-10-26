// lib/modules/action/widgets/action_button_bar.dart
import 'package:flutter/material.dart';

/// Action 弹窗统一底部按钮栏。
///
/// - 颜色全部来自 [Theme.of] 的 colorScheme，自动适配亮色/暗色/动态色主题。
/// - 本组件只负责按钮区域自身的内边距与布局，左右外边距由父级容器负责。
class ActionButtonBar extends StatelessWidget {
  const ActionButtonBar({
    super.key,
    this.showCancel = true,
    this.showReset = false,
    this.showOk = true,
    this.okEnabled = true,
    this.cancelText = '取消',
    this.resetText = '重置',
    this.okText = '确定',
    this.onCancel,
    this.onReset,
    this.onOk,
    this.leadingActions = const <Widget>[],
  });

  final bool showCancel;
  final bool showReset;
  final bool showOk;
  final bool okEnabled;
  final String cancelText;
  final String resetText;
  final String okText;

  final VoidCallback? onCancel;
  final VoidCallback? onReset;
  final VoidCallback? onOk;

  /// 位于左侧的附加操作（例如 Help 的"复制内容"）。
  final List<Widget> leadingActions;

  @override
  Widget build(BuildContext context) {
    if (!showCancel && !showReset && !showOk && leadingActions.isEmpty) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;

    final trailing = <Widget>[];

    if (showCancel) {
      trailing.add(
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            foregroundColor: cs.onSurfaceVariant,
            minimumSize: const Size(64, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // 与确认按钮保持视觉一致：胶囊形
            shape: const StadiumBorder(),
          ),
          child: Text(cancelText),
        ),
      );
    }

    if (showReset) {
      if (trailing.isNotEmpty) trailing.add(const SizedBox(width: 6));
      trailing.add(
        TextButton(
          onPressed: onReset,
          style: TextButton.styleFrom(
            foregroundColor: cs.onSurfaceVariant,
            minimumSize: const Size(64, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: const StadiumBorder(),
          ),
          child: Text(resetText),
        ),
      );
    }

    if (showOk) {
      if (trailing.isNotEmpty) trailing.add(const SizedBox(width: 8));
      trailing.add(
        FilledButton(
          onPressed: okEnabled ? onOk : null,
          style: FilledButton.styleFrom(
            // 高度保持 40，宽度去掉固定最小值，靠 padding 撑开
            minimumSize: const Size(88, 40),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            // ===== 胶囊圆角 =====
            shape: const StadiumBorder(),
            disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
            disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
          ),
          child: Text(okText),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          ...leadingActions,
          const Spacer(),
          ...trailing,
        ],
      ),
    );
  }
}