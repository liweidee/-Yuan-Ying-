// lib/modules/action/widgets/action_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, KeyDownEvent;
import 'package:get/get.dart';

/// Action 弹窗容器
/// 严格对应 DrPlayer 的 ActionDialog.vue
class ActionDialog extends StatefulWidget {
  const ActionDialog({
    super.key,
    required this.visible,
    this.title,
    this.width,
    this.height,
    this.bottom,
    this.canceledOnTouchOutside = true,
    this.dimAmount = 0.45,
    this.showClose = true,
    this.escapeToClose = true,
    this.child,
    this.footer,
    this.onClose,
    this.onOpen,
    this.onOpened,
    this.onClosed,
  });

  final bool visible;
  final String? title;
  final double? width;
  final double? height;
  final double? bottom;
  final bool canceledOnTouchOutside;
  final double dimAmount;
  final bool showClose;
  final bool escapeToClose;
  final Widget? child;
  final Widget? footer;
  final VoidCallback? onClose;
  final VoidCallback? onOpen;
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;

  @override
  State<ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<ActionDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  bool _isVisible = false;
  bool _isClosing = false;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    if (widget.visible) {
      _show();
    }
  }

  @override
  void didUpdateWidget(ActionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _show();
      } else {
        _hide();
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _show() {
    if (_isVisible) return;
    setState(() {
      _isVisible = true;
      _isClosing = false;
    });
    widget.onOpen?.call();
    _controller.forward().then((_) {
      widget.onOpened?.call();
    });
  }

  void _hide() {
    if (_isClosing) return;
    setState(() {
      _isClosing = true;
    });
    // 先执行反向动画，动画完成后再触发 onClose（与 DrPlayer 一致）
    _controller.reverse().then((_) {
      setState(() {
        _isVisible = false;
        _isClosing = false;
      });
      widget.onClosed?.call();
      // 在动画完成后调用 onClose，确保外层可以安全移除 Overlay
      widget.onClose?.call();
    });
  }

  void _handleMaskTap() {
    if (widget.canceledOnTouchOutside && !_isClosing) {
      _hide();
    }
  }

  void _handleKeyDown(KeyEvent event) {
    if (widget.escapeToClose &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        widget.visible &&
        !_isClosing) {
      _hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && !_isVisible) {
      return const SizedBox.shrink();
    }

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyDown,
      child: Stack(
        children: [
          // 遮罩层
          FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              onTap: _handleMaskTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: Colors.black.withOpacity(widget.dimAmount),
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          // 弹窗
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: _buildDialogContent(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final screenSize = MediaQuery.sizeOf(context);
    final isMobile = screenSize.width < 600;

    // 宽度计算
    double dialogWidth;
    if (widget.width != null && widget.width! > 0) {
      dialogWidth = widget.width!;
      if (dialogWidth > screenSize.width * 0.9) {
        dialogWidth = screenSize.width * 0.9;
      }
      if (dialogWidth < 300) {
        dialogWidth = 300;
      }
    } else if (isMobile) {
      dialogWidth = screenSize.width * 0.92;
      if (dialogWidth > 500) {
        dialogWidth = 500;
      }
      if (dialogWidth < 300) {
        dialogWidth = 300;
      }
    } else {
      dialogWidth = 400.0;
      if (dialogWidth > screenSize.width * 0.9) {
        dialogWidth = screenSize.width * 0.9;
      }
    }

    final bottomPadding = widget.bottom ?? 0.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.85,
          minHeight: 100.0,
        ),
        child: Container(
          width: dialogWidth,
          margin: EdgeInsets.only(bottom: bottomPadding),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.25),
                blurRadius: 50,
                spreadRadius: -12,
                offset: const Offset(0, 25),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_shouldShowHeader) _buildHeader(context, colorScheme),
              if (widget.child != null) Flexible(child: _buildContent(context, colorScheme)),
              if (widget.footer != null) _buildFooter(context, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  bool get _shouldShowHeader {
    return widget.title != null && widget.title!.isNotEmpty;
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withOpacity(0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title!,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (widget.showClose) _buildCloseButton(context, colorScheme),
        ],
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context, ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _hide,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.close,
            size: 18,
            color: colorScheme.outline,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: widget.child,
    );
  }

  Widget _buildFooter(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withOpacity(0.08),
            width: 1,
          ),
        ),
      ),
      child: widget.footer,
    );
  }
}