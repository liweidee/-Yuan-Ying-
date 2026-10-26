// lib/modules/action/widgets/action_input.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/action_config.dart';
import '../utils/action_parser.dart';
import '../models/button_type.dart';
import 'action_renderer.dart';
import 'action_button_bar.dart';
import 'action_chip_style.dart';

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

  /// 图片点击回调：接收"图片原始像素坐标"
  void _handleImageTap(int x, int y) {
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

  // 响应共享状态：消息更新和重置
  @override
  Widget build(BuildContext context) {
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

      // 收集所有内容组件（不包含底部固定的超时和按钮）
      final contentChildren = <Widget>[
        // 消息
        if (displayMessage.isNotEmpty) _buildMessage(context, displayMessage),
        // 图片
        if (widget.config.imageUrl != null && widget.config.imageUrl!.isNotEmpty)
          _buildImage(context),
        // 二维码
        if (widget.config.qrcode != null && widget.config.qrcode!.isNotEmpty)
          _buildQrcode(context),
        // 输入框（当没有二维码时显示）
        if (widget.config.qrcode == null || widget.config.qrcode!.isEmpty)
          _buildInput(context),
      ];

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 内容区域 - 自适应高度，不会强制拉伸，内容多时可滚动
          Flexible(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              shrinkWrap: true,
              children: contentChildren,
            ),
          ),
          // 超时提示（固定在底部）
          if (widget.config.timeout > 0 && _timeLeft > 0) _buildTimeout(context),
          // 按钮区（固定在底部）
          _buildButtons(context),
        ],
      );
    });
  }

  Widget _buildMessage(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;

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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: _ClickableImage(
        url: widget.config.imageUrl!,
        displayHeight: (widget.config.imageHeight ?? 200).toDouble(),
        clickCoord: widget.config.imageClickCoord,
        onTap: _handleImageTap,
      ),
    );
  }

  Widget _buildQrcode(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
    final colorScheme = Theme.of(context).colorScheme;

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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _quickSelectOptions.map((option) {
          final isSelected = _inputValue == option.value;
          return buildActionSelectChip(
            context: context,
            label: option.name,
            isSelected: isSelected,
            onTap: () => _selectQuickOption(option),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimeout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
    return ActionButtonBar(
      showCancel: _showCancelButton,
      showReset: _showResetButton,
      showOk: _showOkButton,
      okEnabled: _isValid,
      onCancel: _handleCancel,
      onReset: _handleReset,
      onOk: _handleSubmit,
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

// ============================================================
// 支持"点击坐标"的图片组件
// ============================================================

/// 场景：验证码点击、图片坐标采集
///
/// - 坐标输出为"图片原始像素坐标"（服务端期望的坐标系）
/// - 无论图片被 `imageHeight` 缩放成什么尺寸，坐标都会换算回原始像素
/// - `BoxFit.contain` 的居中留白会被自动扣除
/// - 点击落在留白区域会被忽略
class _ClickableImage extends StatefulWidget {
  const _ClickableImage({
    required this.url,
    required this.displayHeight,
    required this.clickCoord,
    required this.onTap,
  });

  final String url;

  /// 显示高度（对应 config.imageHeight）
  final double displayHeight;
  final bool clickCoord;

  /// 回调返回"图片原始像素坐标"
  final void Function(int x, int y) onTap;

  @override
  State<_ClickableImage> createState() => _ClickableImageState();
}

class _ClickableImageState extends State<_ClickableImage> {
  final GlobalKey _boxKey = GlobalKey();

  /// 图片原始像素尺寸（从 ImageStream 拿到）
  Size? _originalImageSize;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void didUpdateWidget(_ClickableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _originalImageSize = null;
      _loadImageSize();
    }
  }

  /// 通过 ImageStream 拿到图片原始尺寸
  void _loadImageSize() {
    final stream = NetworkImage(widget.url).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _originalImageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
        stream.removeListener(listener);
      },
      onError: (_, __) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.clickCoord) return;

    final renderBox = _boxKey.currentContext?.findRenderObject();
    if (renderBox is! RenderBox) return;

    final imgSize = _originalImageSize;
    if (imgSize == null || imgSize.width == 0 || imgSize.height == 0) {
      // 尺寸未加载完，忽略
      return;
    }

    // 1. 布局框尺寸（显示框，固定 height）
    final boxSize = renderBox.size;

    // 2. 图片原始宽高比
    final imageRatio = imgSize.width / imgSize.height;
    final boxRatio = boxSize.width / boxSize.height;

    // 3. BoxFit.contain 的实际显示尺寸（等比例缩放后的显示像素）
    double displayWidth;
    double displayHeight;
    double scale;

    if (imageRatio > boxRatio) {
      // 图片更宽 → 宽度撑满，上下留白
      displayWidth = boxSize.width;
      displayHeight = boxSize.width / imageRatio;
      scale = displayWidth / imgSize.width;
    } else {
      // 图片更高 → 高度撑满，左右留白
      displayHeight = boxSize.height;
      displayWidth = boxSize.height * imageRatio;
      scale = displayHeight / imgSize.height;
    }

    // 4. 显示区域相对布局框的偏移（居中）
    final offsetX = (boxSize.width - displayWidth) / 2;
    final offsetY = (boxSize.height - displayHeight) / 2;

    // 5. 点击位置相对布局框
    final localPos = renderBox.globalToLocal(details.globalPosition);

    // 6. 相对显示区域
    final displayX = localPos.dx - offsetX;
    final displayY = localPos.dy - offsetY;

    // 7. 边界检查：点击落在留白区域
    if (displayX < 0 ||
        displayY < 0 ||
        displayX > displayWidth ||
        displayY > displayHeight) {
      return;
    }

    // 8. 换算到"图片原始像素坐标"
    final originalX = (displayX / scale).round();
    final originalY = (displayY / scale).round();

    widget.onTap(originalX, originalY);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTapDown: widget.clickCoord ? _handleTapDown : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          key: _boxKey,
          width: double.infinity,
          height: widget.displayHeight,
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image,
                        size: 48, color: colorScheme.outline),
                    const SizedBox(height: 8),
                    Text(
                      '图片加载失败',
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.outline),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}