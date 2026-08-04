// lib/modules/action/widgets/action_multi_input.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../models/action_config.dart';
import '../models/button_type.dart';
import '../utils/action_parser.dart';
import '../models/action_type.dart';
import 'action_renderer.dart';

class MultiInputAction extends StatefulWidget {
  const MultiInputAction({
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
  State<MultiInputAction> createState() => _MultiInputActionState();
}

class _MultiInputActionState extends State<MultiInputAction> {
  late final ActionRenderer _renderer;

  List<InputItemConfig> _inputItems = [];
  List<TextEditingController> _controllers = [];
  List<String> _errors = [];

  Timer? _timeoutTimer;
  int _timeLeft = 0;

  // ===== 选项弹窗状态（保留，使用 OverlayEntry 实现） =====
  bool _showOptionsDialog = false;
  int _optionsIndex = -1;
  List<SelectOption> _options = [];
  String _selectedRadioValue = '';
  List<String> _selectedCheckboxValues = [];
  bool _isMultiSelect = false;
  int _selectColumn = 4;

  bool get _isEnhanced => widget.config.type == ActionType.multiInputX;

  bool get _showOkButton => widget.config.button.showOk;
  bool get _showCancelButton => widget.config.button.showCancel;
  bool get _showResetButton => widget.config.button.showReset;

  bool get _isValid {
    for (int i = 0; i < _inputItems.length; i++) {
      if (_errors[i].isNotEmpty) return false;
      final item = _inputItems[i];
      if (item.required && _controllers[i].text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _renderer = Get.find<ActionRenderer>();
    _initInputs();
    if (widget.visible) {
      _startTimeout();
    }
  }

  @override
  void didUpdateWidget(MultiInputAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _startTimeout();
      } else {
        _stopTimeout();
      }
    }
    if (widget.config.inputs != oldWidget.config.inputs) {
      _initInputs();
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initInputs() {
    final inputs = widget.config.inputs ?? [];
    if (inputs.isEmpty) {
      _inputItems = [
        InputItemConfig(
          id: 'default',
          name: '输入内容',
          tip: '请输入内容',
          required: false,
        ),
      ];
    } else {
      _inputItems = inputs;
    }

    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers.clear();
    _errors.clear();

    for (final item in _inputItems) {
      _controllers.add(TextEditingController(text: item.value ?? ''));
      _errors.add('');
    }
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

  void _validateInput(int index) {
    setState(() {
      _errors[index] = '';
      final item = _inputItems[index];
      final value = _controllers[index].text;

      if (item.required && value.trim().isEmpty) {
        _errors[index] = '${item.name ?? "此字段"}为必填项';
        return;
      }

      if (item.validation != null &&
          item.validation!.isNotEmpty &&
          value.isNotEmpty) {
        try {
          final regex = RegExp(item.validation!);
          if (!regex.hasMatch(value)) {
            _errors[index] = '${item.name ?? "输入"}格式不正确';
            return;
          }
        } catch (_) {}
      }

      final inputType = _getInputType(item);
      if (inputType == 'email' && value.isNotEmpty) {
        const emailRegex = r'^[^\s@]+@[^\s@]+\.[^\s@]+$';
        if (!RegExp(emailRegex).hasMatch(value)) {
          _errors[index] = '请输入有效的邮箱地址';
          return;
        }
      }

      if (inputType == 'url' && value.isNotEmpty) {
        try {
          Uri.parse(value);
        } catch (_) {
          _errors[index] = '请输入有效的URL地址';
          return;
        }
      }
    });
  }

  String _getInputType(InputItemConfig item) {
    switch (item.inputType) {
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

  String? _getSpecialType(InputItemConfig item) {
    if (item.selectData == null) return null;
    final options = ActionParser.parseSelectData(item.selectData!);
    for (final option in options) {
      if (option.isSpecial) {
        final value = option.value;
        if (value.startsWith('[') && value.endsWith(']')) {
          final type = value.substring(1, value.length - 1).toLowerCase();
          if (['calendar', 'file', 'folder', 'image'].contains(type)) {
            return type;
          }
        }
      }
    }
    return null;
  }

  bool _hasNonSpecialOptions(InputItemConfig item) {
    if (item.selectData == null) return false;
    final options = ActionParser.parseSelectData(item.selectData!);
    return options.any((opt) => !opt.isSpecial);
  }

  List<SelectOption> _getNonSpecialOptions(InputItemConfig item) {
    if (item.selectData == null) return [];
    return ActionParser.parseSelectData(item.selectData!)
        .where((opt) => !opt.isSpecial)
        .toList();
  }

  void _handleSubmit() {
    if (!_isValid) return;

    final result = <String, dynamic>{};

    for (int i = 0; i < _inputItems.length; i++) {
      final item = _inputItems[i];
      final key = item.id ?? item.name ?? 'input_$i';
      result[key] = _controllers[i].text;
    }

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
      for (int i = 0; i < _controllers.length; i++) {
        _controllers[i].text = '';
        _errors[i] = '';
      }
    });
    widget.onReset?.call();
  }

  void _addInputItem() {
    setState(() {
      final newItem = InputItemConfig(
        id: 'dynamic_${DateTime.now().millisecondsSinceEpoch}',
        name: '输入项 ${_inputItems.length + 1}',
        tip: '请输入内容',
        required: false,
      );
      _inputItems.add(newItem);
      _controllers.add(TextEditingController());
      _errors.add('');
    });
  }

  void _removeInputItem(int index) {
    if (_inputItems.length <= 1) return;
    setState(() {
      _controllers[index].dispose();
      _inputItems.removeAt(index);
      _controllers.removeAt(index);
      _errors.removeAt(index);
    });
  }

  void _clearAll() {
    setState(() {
      for (int i = 0; i < _controllers.length; i++) {
        _controllers[i].text = '';
        _errors[i] = '';
      }
    });
  }

  void _fillExample() {
    setState(() {
      for (int i = 0; i < _inputItems.length; i++) {
        _controllers[i].text = '示例${i + 1}';
        _errors[i] = '';
        _validateInput(i);
      }
    });
  }

  void _selectQuickOption(int index, SelectOption option) {
    setState(() {
      _controllers[index].text = option.value;
      _errors[index] = '';
    });
    _validateInput(index);
  }

  // ============================================================
  // 日期选择器 → 使用 Flutter 原生 showDatePicker
  // ============================================================
  Future<void> _showDatePickerDialog(int index) async {
    final overlay = Overlay.of(context);
    OverlayEntry? overlayEntry;

    DateTime selectedDate = DateTime.now();

    overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            width: 360,
            constraints: const BoxConstraints(maxWidth: 360),
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
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '选择日期',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: CalendarDatePicker(
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    onDateChanged: (date) {
                      selectedDate = date;
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        overlayEntry?.remove();
                      },
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        // 保存日期到对应的输入框
                        if (index >= 0 && index < _controllers.length) {
                          setState(() {
                            _controllers[index].text =
                                '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                            _errors[index] = '';
                          });
                          _validateInput(index);
                        }
                        overlayEntry?.remove();
                      },
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

    overlay.insert(overlayEntry!);
  }

  // ============================================================
  // 帮助对话框 → 使用 showDialog 独立弹出
  // ============================================================
  void _showHelp(String content) {
    final overlay = Overlay.of(context);
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            width: 400, // 固定最大宽度
            constraints: const BoxConstraints(maxWidth: 400),
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
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '帮助信息',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  child: Text(
                    content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
                      child: Text(
                        '确定',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry!);
  }

  void _handleSpecialInput(int index, String type) {
    switch (type) {
      case 'calendar':
        _showDatePickerDialog(index);
        break;
      case 'file':
        _pickFile(index);
        break;
      case 'folder':
        _pickFolder(index);
        break;
      case 'image':
        _pickImage(index);
        break;
    }
  }

  void _pickFile(int index) {
    setState(() {
      _controllers[index].text = 'selected_file.txt';
      _errors[index] = '';
    });
    _validateInput(index);
  }

  void _pickFolder(int index) {
    setState(() {
      _controllers[index].text = 'selected_folder';
      _errors[index] = '';
    });
    _validateInput(index);
  }

  void _pickImage(int index) {
    setState(() {
      _controllers[index].text = 'image_base64_data';
      _errors[index] = '';
    });
    _validateInput(index);
  }

  // ============================================================
  // 选项弹窗（保留，使用 OverlayEntry 实现）
  // ============================================================
  void _openOptionsDialog(int index) {
    final item = _inputItems[index];
    if (item.selectData == null) return;

    final options = ActionParser.parseSelectData(item.selectData!);
    final isMultiSelect = item.multiSelect;
    final selectColumn = item.selectColumn ?? 4;

    String selectedRadioValue = _controllers[index].text;
    List<String> selectedCheckboxValues = [];
    if (isMultiSelect) {
      selectedCheckboxValues = _controllers[index].text.isNotEmpty
          ? _controllers[index].text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
          : [];
    }

    final overlayContext = Overlay.of(context);
    final int optionsIndex = index;

    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            width: isMultiSelect
                ? (selectColumn.clamp(1, 4) * 120 + 60).toDouble().clamp(300.0, MediaQuery.of(context).size.width * 0.85)
                : 400,
            height: MediaQuery.of(context).size.height * 0.55,
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
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                return Column(
                  children: [
                    Text(
                      isMultiSelect ? '请选择（多选）' : '请选择',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: isMultiSelect
                            ? options.map((option) {
                                final isSelected = selectedCheckboxValues.contains(option.value);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: ChoiceChip(
                                    label: Text(
                                      option.name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isSelected
                                            ? Theme.of(context).colorScheme.onPrimary
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setStateDialog(() {
                                        if (selected) {
                                          if (!selectedCheckboxValues.contains(option.value)) {
                                            selectedCheckboxValues.add(option.value);
                                          }
                                        } else {
                                          selectedCheckboxValues.remove(option.value);
                                        }
                                      });
                                    },
                                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    selectedColor: Theme.of(context).colorScheme.primary,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                );
                              }).toList()
                            : options.map((option) {
                                final isSelected = selectedRadioValue == option.value;
                                return RadioListTile<String>(
                                  title: Text(
                                    option.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  value: option.value,
                                  groupValue: selectedRadioValue,
                                  onChanged: (value) {
                                    setStateDialog(() {
                                      selectedRadioValue = value ?? '';
                                    });
                                  },
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                );
                              }).toList(),
                      ),
                    ),
                    if (isMultiSelect)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () {
                              setStateDialog(() {
                                selectedCheckboxValues = options.map((opt) => opt.value).toList();
                              });
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.onSurface,
                            ),
                            child: const Text('全选'),
                          ),
                          TextButton(
                            onPressed: () {
                              setStateDialog(() {
                                selectedCheckboxValues = [];
                              });
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.onSurface,
                            ),
                            child: const Text('全清'),
                          ),
                          TextButton(
                            onPressed: () {
                              setStateDialog(() {
                                final allValues = options.map((opt) => opt.value).toList();
                                selectedCheckboxValues = allValues
                                    .where((value) => !selectedCheckboxValues.contains(value))
                                    .toList();
                              });
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.onSurface,
                            ),
                            child: const Text('反选'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
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
                              if (isMultiSelect) {
                                _controllers[optionsIndex].text = selectedCheckboxValues.join(',');
                              } else {
                                _controllers[optionsIndex].text = selectedRadioValue;
                              }
                              _errors[optionsIndex] = '';
                            });
                            _validateInput(optionsIndex);
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
                );
              },
            ),
          ),
        ),
      ),
    );

    overlayContext.insert(overlayEntry!);
  }

  void _confirmOptions() {
    if (_optionsIndex >= 0) {
      setState(() {
        if (_isMultiSelect) {
          _controllers[_optionsIndex].text = _selectedCheckboxValues.join(',');
        } else {
          _controllers[_optionsIndex].text = _selectedRadioValue;
        }
        _errors[_optionsIndex] = '';
        _showOptionsDialog = false;
        _optionsIndex = -1;
        _options = [];
        _selectedCheckboxValues = [];
        _selectedRadioValue = '';
      });
      _validateInput(_optionsIndex);
    }
  }

  void _cancelOptions() {
    setState(() {
      _showOptionsDialog = false;
      _optionsIndex = -1;
      _options = [];
      _selectedCheckboxValues = [];
      _selectedRadioValue = '';
    });
  }

  void _selectAll() {
    setState(() {
      _selectedCheckboxValues = _options.map((opt) => opt.value).toList();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedCheckboxValues = [];
    });
  }

  void _invertSelection() {
    setState(() {
      final allValues = _options.map((opt) => opt.value).toList();
      _selectedCheckboxValues = allValues
          .where((value) => !_selectedCheckboxValues.contains(value))
          .toList();
    });
  }

  void _openTextEditor(int index) {
    final overlayContext = Overlay.of(context);
    final currentIndex = index;
    final editorController = TextEditingController(text: _controllers[currentIndex].text);
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
                          _controllers[currentIndex].text = tempText;
                          _errors[currentIndex] = '';
                        });
                        _validateInput(currentIndex);
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

  double _getEditorWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    
    if (isMobile) {
      return (screenWidth * 0.85).clamp(300.0, 500.0);
    } else {
      return (560.0).clamp(400.0, screenWidth * 0.8);
    }
  }

  // ============================================================
  // 构建方法
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (_renderer.shouldReset.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (int i = 0; i < _controllers.length; i++) {
            _controllers[i].text = '';
            _errors[i] = '';
          }
          _renderer.shouldReset.value = false;
        });
      }

      final displayMessage = _renderer.currentMessage.value.isNotEmpty
          ? _renderer.currentMessage.value
          : widget.config.msg ?? '';

      final screenHeight = MediaQuery.sizeOf(context).height;

      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.65,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== 顶部固定 =====
            if (displayMessage.isNotEmpty) _buildMessage(context, displayMessage),
            if (widget.config.imageUrl != null && widget.config.imageUrl!.isNotEmpty)
              _buildImage(context),

            // ===== 中间滚动区域 =====
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInputList(context),
                    if (widget.config.timeout > 0 && _timeLeft > 0) _buildTimeout(context),
                  ],
                ),
              ),
            ),

            // ===== 底部固定区域 =====
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isEnhanced) _buildEnhancedControls(context),
                _buildButtons(context),
              ],
            ),
          ],
        ),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        // 添加 Align 实现居中，不添加任何 onTapDown
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
    );
  }

  // ============================================================
  // 输入列表 - 描述行使用 Expanded + Wrap + softWrap
  // ============================================================
  Widget _buildInputList(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      child: SingleChildScrollView(
        child: Column(
          children: List.generate(_inputItems.length, (index) {
            final item = _inputItems[index];
            final controller = _controllers[index];
            final error = _errors[index];
            final isEnhanced = _isEnhanced;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: error.isNotEmpty
                      ? colorScheme.error.withValues(alpha: 0.3)
                      : colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== 描述行（使用 Expanded + Wrap + softWrap） =====
                  if (item.name != null && item.name!.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Wrap(
                            alignment: WrapAlignment.start,
                            spacing: 4,
                            runSpacing: 2,
                            children: [
                              Text(
                                item.name!,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurface,
                                ),
                                softWrap: true, // 允许换行
                              ),
                              if (item.required)
                                Text(
                                  ' *',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.error,
                                  ),
                                ),
                              if (item.help != null && item.help!.isNotEmpty)
                                IconButton(
                                  icon: Icon(
                                    Icons.help_outline,
                                    size: 16,
                                    color: colorScheme.outline,
                                  ),
                                  onPressed: () => _showHelp(item.help!), // 使用独立的 showDialog
                                  padding: const EdgeInsets.all(2),
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ),
                        if (isEnhanced && _inputItems.length > 1)
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: colorScheme.error,
                            ),
                            onPressed: () => _removeInputItem(index),
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),

                  const SizedBox(height: 6),

                  // ===== 快速选择 Chip =====
                  if (_hasNonSpecialOptions(item))
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _getNonSpecialOptions(item).map((option) {
                        final isSelected = controller.text == option.value;
                        return ChoiceChip(
                          label: Text(
                            option.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) => _selectQuickOption(index, option),
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          selectedColor: colorScheme.primaryContainer,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      }).toList(),
                    ),

                  // ===== 输入行 =====
                  Row(
                    children: [
                      Expanded(
                        child: _buildInputField(context, index),
                      ),
                      if (_getSpecialType(item) != null)
                        IconButton(
                          icon: _getSpecialIcon(_getSpecialType(item)!),
                          onPressed: () => _handleSpecialInput(
                            index,
                            _getSpecialType(item)!,
                          ),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                        ),
                      if (item.selectData != null &&
                          _getSpecialType(item) == null &&
                          _hasNonSpecialOptions(item))
                        IconButton(
                          icon: Icon(
                            Icons.arrow_drop_down,
                            size: 20,
                            color: colorScheme.outline,
                          ),
                          onPressed: () => _openOptionsDialog(index),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                        ),
                      IconButton(
                        icon: Icon(
                          Icons.open_in_full,
                          size: 18,
                          color: colorScheme.outline,
                        ),
                        onPressed: () => _openTextEditor(index),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),

                  // ===== 错误信息 =====
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 14,
                            color: colorScheme.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            error,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildInputField(BuildContext context, int index) {
    final item = _inputItems[index];
    final controller = _controllers[index];
    final isMultiLine = item.multiLine > 1;

    if (isMultiLine) {
      return TextField(
        controller: controller,
        maxLines: item.multiLine.clamp(2, 8),
        decoration: InputDecoration(
          hintText: item.tip ?? '请输入内容...',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onChanged: (_) => _validateInput(index),
      );
    } else {
      final inputType = _getInputType(item);
      return TextField(
        controller: controller,
        obscureText: inputType == 'password',
        keyboardType: _getKeyboardType(inputType),
        decoration: InputDecoration(
          hintText: item.tip ?? '请输入内容...',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onChanged: (_) => _validateInput(index),
      );
    }
  }

  Widget _getSpecialIcon(String type) {
    switch (type) {
      case 'calendar':
        return Icon(Icons.calendar_today, size: 18, color: Colors.blue);
      case 'file':
        return Icon(Icons.attach_file, size: 18, color: Colors.green);
      case 'folder':
        return Icon(Icons.folder_open, size: 18, color: Colors.orange);
      case 'image':
        return Icon(Icons.image, size: 18, color: Colors.purple);
      default:
        return Icon(Icons.help, size: 18, color: Colors.grey);
    }
  }

  TextInputType _getKeyboardType(String inputType) {
    switch (inputType) {
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

  Widget _buildEnhancedControls(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton.icon(
            onPressed: _addInputItem,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加项目'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
          TextButton.icon(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('清空全部'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
          TextButton.icon(
            onPressed: _fillExample,
            icon: const Icon(Icons.edit_note, size: 18),
            label: const Text('填充示例'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          Text('$_timeLeft秒后自动关闭',
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

  // ============================================================
  // 选项弹窗（保留，使用 OverlayEntry 实现）
  // ============================================================
  Widget _buildOptionsDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);

    double dialogWidth = 400;
    if (_isMultiSelect) {
      final columns = _selectColumn.clamp(1, 4);
      dialogWidth = (columns * 120 + 60).toDouble().clamp(300.0, screenSize.width * 0.85);
    }

    final double dialogHeight = screenSize.height * 0.55;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: colorScheme.surface,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                _isMultiSelect ? '请选择（多选）' : '请选择',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                children: _isMultiSelect
                    ? _options.map((option) {
                        final isSelected = _selectedCheckboxValues.contains(option.value);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: ChoiceChip(
                            label: Text(
                              option.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                              ),
                            ),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  if (!_selectedCheckboxValues.contains(option.value)) {
                                    _selectedCheckboxValues.add(option.value);
                                  }
                                } else {
                                  _selectedCheckboxValues.remove(option.value);
                                }
                              });
                            },
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            selectedColor: colorScheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        );
                      }).toList()
                    : _options.map((option) {
                        final isSelected = _selectedRadioValue == option.value;
                        return RadioListTile<String>(
                          title: Text(
                            option.name,
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          value: option.value,
                          groupValue: _selectedRadioValue,
                          onChanged: (value) {
                            setState(() {
                              _selectedRadioValue = value ?? '';
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (_isMultiSelect)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(onPressed: _selectAll, child: const Text('全选')),
                        TextButton(onPressed: _clearSelection, child: const Text('全清')),
                        TextButton(onPressed: _invertSelection, child: const Text('反选')),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: _cancelOptions, child: const Text('取消')),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: _confirmOptions, child: const Text('确定')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 底部按钮
  // ============================================================
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
}