// lib/modules/action/widgets/action_input.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../models/action_config.dart';
import '../utils/action_parser.dart';
import '../models/button_type.dart';
import 'action_renderer.dart';

/// 单项输入 Action
/// 严格对应 DrPlayer 的 InputAction.vue
class InputAction extends StatefulWidget {
  const InputAction({
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
  State<InputAction> createState() => _InputActionState();
}

class _InputActionState extends State<InputAction> {
  final TextEditingController _controller = TextEditingController();
  String _inputValue = '';
  String _errorMessage = '';
  Offset? _imageCoords;
  Timer? _timeoutTimer;
  int _timeLeft = 0;
  final FocusNode _focusNode = FocusNode();

  // 获取 ActionRenderer 共享状态
  final ActionRenderer _renderer = Get.find<ActionRenderer>();

  bool get _isMultiLine => widget.config.multiLine > 1;

  String get _inputType {
    switch (widget.config.inputType) {
      case 1:
        return 'password';
      case 2:
        return 'number';
      case 3:
        return 'email';
      case 4:
        return 'url';
      default:
        return 'text';
    }
  }

  List<SelectOption> get _quickSelectOptions {
    return ActionParser.parseSelectData(widget.config.selectData);
  }

  String get _qrcodeUrl {
    if (widget.config.qrcode == null || widget.config.qrcode!.isEmpty) {
      return '';
    }
    return ActionParser.generateQRCodeUrl(
      widget.config.qrcode!,
      widget.config.qrcodeSize ?? '200x200',
    );
  }

  bool get _showOkButton => widget.config.button.showOk;
  bool get _showCancelButton => widget.config.button.showCancel;
  bool get _showResetButton => widget.config.button.showReset;
  bool get _hasError => _errorMessage.isNotEmpty;

  bool get _isValid {
    if (_hasError) return false;
    if (widget.config.required && _inputValue.trim().isEmpty) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _inputValue = widget.config.value ?? '';
    _controller.text = _inputValue;
    if (widget.visible) {
      _startTimeout();
      _focusNode.requestFocus();
    }
  }

  @override
  void didUpdateWidget(InputAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _startTimeout();
        _focusNode.requestFocus();
      } else {
        _stopTimeout();
      }
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _focusNode.dispose();
    _controller.dispose();
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
          _handleCancel();
        }
      });
    });
  }

  void _stopTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _timeLeft = 0;
  }

  void _onInputChanged(String value) {
    setState(() {
      _inputValue = value;
      _errorMessage = '';
    });
    _validateInput();
  }

  void _validateInput() {
    setState(() {
      _errorMessage = '';

      if (widget.config.required && _inputValue.trim().isEmpty) {
        _errorMessage = '此字段为必填项';
        return;
      }

      if (widget.config.validation != null &&
          widget.config.validation!.isNotEmpty &&
          _inputValue.isNotEmpty) {
        try {
          final regex = RegExp(widget.config.validation!);
          if (!regex.hasMatch(_inputValue)) {
            _errorMessage = '输入格式不正确';
            return;
          }
        } catch (_) {}
      }

      if (_inputType == 'email' && _inputValue.isNotEmpty) {
        const emailRegex = r'^[^\s@]+@[^\s@]+\.[^\s@]+$';
        if (!RegExp(emailRegex).hasMatch(_inputValue)) {
          _errorMessage = '请输入有效的邮箱地址';
          return;
        }
      }

      if (_inputType == 'url' && _inputValue.isNotEmpty) {
        try {
          Uri.parse(_inputValue);
        } catch (_) {
          _errorMessage = '请输入有效的URL地址';
          return;
        }
      }
    });
  }

  void _handleSubmit() {
    if (!_isValid) return;

    final result = <String, dynamic>{};

    if (widget.config.imageClickCoord && _imageCoords != null) {
      result['imageCoords'] = {
        'x': _imageCoords!.dx.round(),
        'y': _imageCoords!.dy.round(),
      };
    }

    final id = widget.config.id ?? 'value';
    result[id] = _inputValue;

    if (widget.config.actionId.isNotEmpty) {
      widget.onAction?.call({
        'actionId': widget.config.actionId,
        'value': result,
        'extend': widget.extend,
        'apiUrl': widget.apiUrl,
      });
      return;
    }

    widget.onSubmit?.call(result);
    widget.onClose?.call();
  }

  void _handleCancel() {
    widget.onCancel?.call();
    widget.onClose?.call();
  }

  void _handleReset() {
    setState(() {
      _inputValue = '';
      _controller.text = '';
      _errorMessage = '';
      _imageCoords = null;
    });
    widget.onReset?.call();
    _focusNode.requestFocus();
  }

  void _onImageTap(TapDownDetails details) {
    if (!widget.config.imageClickCoord) return;

    final RenderBox box = context.findRenderObject() as RenderBox;
    final localPos = box.globalToLocal(details.globalPosition);
    final x = localPos.dx.round();
    final y = localPos.dy.round();

    setState(() {
      _imageCoords = Offset(x.toDouble(), y.toDouble());
      final newCoord = '$x,$y';
      if (_inputValue.trim().isNotEmpty) {
        _inputValue = '$_inputValue-$newCoord';
      } else {
        _inputValue = newCoord;
      }
      _controller.text = _inputValue;
      _validateInput();
    });
  }

  void _selectQuickOption(SelectOption option) {
    setState(() {
      _inputValue = option.value;
      _controller.text = option.value;
      _errorMessage = '';
    });
    _validateInput();

    if (widget.config.onlyQuickSelect) {
      Future.delayed(const Duration(milliseconds: 100), _handleSubmit);
    }
  }

  void _openTextEditor() {
    final overlayContext = Overlay.of(context);
    final editorController = TextEditingController(text: _inputValue);
    String tempText = editorController.text;

    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            width: _getEditorWidth(context),
            height: MediaQuery.of(context).size.height * 0.6,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '大文本编辑器',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TextField(
                    controller: editorController,
                    maxLines: null,
                    expands: true,
                    decoration: InputDecoration(
                      hintText: '请输入文本内容...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    onChanged: (value) {
                      tempText = value;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        overlayEntry?.remove();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                      ),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _inputValue = tempText;
                          _controller.text = tempText;
                          _errorMessage = '';
                        });
                        _validateInput();
                        overlayEntry?.remove();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlayContext.insert(overlayEntry!);
  }

  // 添加在类中作为私有方法
  double _getEditorWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    
    if (isMobile) {
      return (screenWidth * 0.85).clamp(300.0, 500.0);
    } else {
      return (560.0).clamp(400.0, screenWidth * 0.8);
    }
  }

  // 响应共享状态：消息更新和重置
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Obx(() {
      // 处理重置信号（来自 __keep__ 的 reset）
      if (_renderer.shouldReset.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _controller.text = '';
          _inputValue = '';
          _errorMessage = '';
          _imageCoords = null;
          _renderer.shouldReset.value = false;
        });
      }

      // 优先使用共享消息（来自 __keep__ 的 msg 更新）
      final displayMessage = _renderer.currentMessage.value.isNotEmpty
          ? _renderer.currentMessage.value
          : widget.config.msg ?? '';

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (displayMessage.isNotEmpty) _buildMessage(context, displayMessage),
          if (widget.config.imageUrl != null && widget.config.imageUrl!.isNotEmpty)
            _buildImage(context),
          if (widget.config.qrcode != null && widget.config.qrcode!.isNotEmpty)
            _buildQrcode(context),
          if (widget.config.qrcode == null || widget.config.qrcode!.isEmpty)
            _buildInput(context),
          if (widget.config.timeout > 0 && _timeLeft > 0) _buildTimeout(context),
          _buildButtons(context),
        ],
      );
    });
  }

  Widget _buildMessage(BuildContext context, String message) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
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
      child: GestureDetector(
        onTapDown: widget.config.imageClickCoord ? _onImageTap : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Align(
            alignment: Alignment.center,
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
        ),
      ),
    );
  }

  Widget _buildQrcode(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.network(
            _qrcodeUrl,
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

  Widget _buildInput(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_quickSelectOptions.isNotEmpty) _buildQuickSelect(context),
        if (_isMultiLine) ...[
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: widget.config.multiLine.clamp(2, 10),
            decoration: InputDecoration(
              hintText: widget.config.tip ?? '请输入内容...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              errorText: _hasError ? _errorMessage : null,
              suffixIcon: IconButton(
                icon: const Icon(Icons.open_in_full),
                onPressed: _openTextEditor,
                tooltip: '打开大文本编辑器',
              ),
            ),
            onChanged: _onInputChanged,
          ),
        ] else ...[
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            obscureText: _inputType == 'password',
            keyboardType: _getKeyboardType(),
            decoration: InputDecoration(
              hintText: widget.config.tip ?? '请输入内容...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              errorText: _hasError ? _errorMessage : null,
              suffixIcon: IconButton(
                icon: const Icon(Icons.open_in_full),
                onPressed: _openTextEditor,
                tooltip: '打开大文本编辑器',
              ),
            ),
            onChanged: _onInputChanged,
          ),
        ],
        if (widget.config.help != null && widget.config.help!.isNotEmpty && !_hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.config.help!,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildQuickSelect(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _quickSelectOptions.map((option) {
          final isSelected = _inputValue == option.value;
          return ChoiceChip(
            label: Text(option.name),
            selected: isSelected,
            onSelected: (_) => _selectQuickOption(option),
            backgroundColor: colorScheme.surfaceContainerHighest,
            selectedColor: colorScheme.primaryContainer,
            labelStyle: TextStyle(
              fontSize: 12,
              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimeout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.errorContainer.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 16, color: colorScheme.error),
          const SizedBox(width: 6),
          Text(
            '$_timeLeft秒后自动关闭',
            style: TextStyle(fontSize: 12, color: colorScheme.error),
          ),
          const Spacer(),
          Container(
            width: 100,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              widthFactor: (_timeLeft / widget.config.timeout).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
          child: const Text('取消'),
        ),
      );
    }

    if (_showResetButton) {
      children.add(
        TextButton(
          onPressed: _handleReset,
          child: const Text('重置'),
        ),
      );
    }

    if (_showOkButton) {
      children.add(
        ElevatedButton(
          onPressed: _isValid ? _handleSubmit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isValid ? colorScheme.primary : colorScheme.outline,
            foregroundColor: _isValid ? colorScheme.onPrimary : colorScheme.onSurface,
          ),
          child: const Text('确定'),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: children,
      ),
    );
  }

  TextInputType _getKeyboardType() {
    switch (_inputType) {
      case 'number':
        return TextInputType.number;
      case 'email':
        return TextInputType.emailAddress;
      case 'url':
        return TextInputType.url;
      default:
        return TextInputType.text;
    }
  }
}