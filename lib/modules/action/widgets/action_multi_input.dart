// lib/modules/action/widgets/action_multi_input.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/action_config.dart';
import '../models/button_type.dart';
import '../utils/action_parser.dart';
import 'action_renderer.dart';
import 'action_button_bar.dart';
import 'action_chip_style.dart';

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
  /// 内联 chip 的选项数量上限。超过则只显示下拉弹窗按钮，
  /// 避免 chip 撑高输入卡片、破坏布局。
  static const int _inlineChipLimit = 5;

  /// 图片 base64 编码上限（避免超长字符串导致 UI 卡顿/提交超时）
  static const int _maxImageBytes = 2 * 1024 * 1024; // 2MB

  late final ActionRenderer _renderer;

  List<InputItemConfig> _inputItems = [];
  List<TextEditingController> _controllers = [];
  List<String> _errors = [];

  Timer? _timeoutTimer;
  int _timeLeft = 0;

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
    return _getNonSpecialOptions(item).isNotEmpty;
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

  // ============================================================
  // 快速选择 chip 点击
  //
  // - 单选：直接覆盖 controller.text
  // - 多选：在逗号分隔的列表里 toggle
  //
  // 统一走这个方法后，chip 与下拉弹窗在语义上完全一致。
  // ============================================================
  void _onQuickOptionTap(int index, SelectOption option, bool isMulti) {
    if (!isMulti) {
      setState(() {
        _controllers[index].text = option.value;
        _errors[index] = '';
      });
    } else {
      final current = _controllers[index].text;
      final values = current.isEmpty
          ? <String>[]
          : current
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

      if (values.contains(option.value)) {
        values.remove(option.value);
      } else {
        values.add(option.value);
      }

      setState(() {
        _controllers[index].text = values.join(',');
        _errors[index] = '';
      });
    }
    _validateInput(index);
  }

  /// 判断当前 chip 是否处于"被选中"状态
  bool _isQuickOptionSelected(String text, String value, bool isMulti) {
    if (!isMulti) return text == value;
    if (text.isEmpty) return false;
    return text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .contains(value);
  }

  // ============================================================
  // 日期选择器
  // ============================================================
  Future<void> _showDatePickerDialog(int index) async {
    final overlay = Overlay.of(context);
    OverlayEntry? overlayEntry;

    DateTime selectedDate = DateTime.now();
    final cs = Theme.of(context).colorScheme;

    overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: cs.scrim.withValues(alpha: 0.5),
        child: Center(
          child: Container(
            width: 360,
            constraints: const BoxConstraints(maxWidth: 360),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.2),
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
                    color: cs.onSurface,
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
  // 帮助对话框
  // ============================================================
  void _showHelp(String content) {
    final overlay = Overlay.of(context);
    OverlayEntry? overlayEntry;
    final cs = Theme.of(context).colorScheme;

    overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: cs.scrim.withValues(alpha: 0.5),
        child: Center(
          child: Container(
            width: 400,
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.2),
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
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  child: Text(
                    content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: cs.onSurfaceVariant,
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
                        style: TextStyle(color: cs.primary),
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

  // ============================================================
  // 文件 / 文件夹 / 图片选择（file_picker 13.1.0）
  // ============================================================

  /// 选择单个文件（返回文件绝对路径）
  Future<void> _pickFile(int index) async {
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final path = file.path ?? file.name;

      if (!mounted) return;
      setState(() {
        _controllers[index].text = path;
        _errors[index] = '';
      });
      _validateInput(index);
    } catch (e) {
      debugPrint('文件选择失败: $e');
      widget.onToast?.call('文件选择失败: $e', 'error');
    }
  }

  /// 选择文件夹（返回文件夹绝对路径）
  Future<void> _pickFolder(int index) async {
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path == null || path.isEmpty) return;

      if (!mounted) return;
      setState(() {
        _controllers[index].text = path;
        _errors[index] = '';
      });
      _validateInput(index);
    } catch (e) {
      debugPrint('文件夹选择失败: $e');
      widget.onToast?.call('文件夹选择失败: $e', 'error');
    }
  }

  /// 选择图片（读取为 base64 data URL，与 Vue 版 FileReader.readAsDataURL 输出格式一致）
  Future<void> _pickImage(int index) async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final path = file.path;
      if (path == null) return;

      // 读取文件并转 base64
      final bytes = await File(path).readAsBytes();

      // 文件过大提示（避免 base64 超长字符串导致 UI 卡顿/提交超时）
      if (bytes.length > _maxImageBytes) {
        widget.onToast?.call(
          '图片过大（>${(_maxImageBytes / 1024 / 1024).toStringAsFixed(1)}MB），请选择更小的图片',
          'error',
        );
        return;
      }

      final base64Str = base64Encode(bytes);
      final mime = _guessMimeType(file.extension);
      final dataUrl = 'data:$mime;base64,$base64Str';

      if (!mounted) return;
      setState(() {
        _controllers[index].text = dataUrl;
        _errors[index] = '';
      });
      _validateInput(index);
    } catch (e) {
      debugPrint('图片选择失败: $e');
      widget.onToast?.call('图片选择失败: $e', 'error');
    }
  }

  /// 根据扩展名推断 MIME 类型
  String _guessMimeType(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/png';
    }
  }

  // ============================================================
  // 选项弹窗（选项数超过 _inlineChipLimit 时使用）
  // ============================================================
  void _openOptionsDialog(int index) {
    final item = _inputItems[index];
    if (item.selectData == null) return;

    final options = ActionParser.parseSelectData(item.selectData!);
    final isMultiSelect = item.multiSelect;
    final selectColumn = item.selectColumn;

    String selectedRadioValue = _controllers[index].text;
    List<String> selectedCheckboxValues = [];
    if (isMultiSelect) {
      selectedCheckboxValues = _controllers[index].text.isNotEmpty
          ? _controllers[index].text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
          : [];
    }

    final overlayContext = Overlay.of(context);
    final int optionsIndex = index;

    OverlayEntry? overlayEntry;

    // 弹窗宽度
    final double dialogWidth = isMultiSelect
        ? (MediaQuery.of(context).size.width * 0.8).clamp(320.0, 460.0)
        : 400.0;

    overlayEntry = OverlayEntry(
      builder: (overlayCtx) => Material(
        color: Theme.of(overlayCtx).colorScheme.scrim.withValues(alpha: 0.5),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(overlayCtx).size.height * 0.55,
            ),
            child: Container(
              width: dialogWidth,
              decoration: BoxDecoration(
                color: Theme.of(overlayCtx).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(overlayCtx)
                        .colorScheme
                        .shadow
                        .withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setStateDialog) {
                  final cs = Theme.of(context).colorScheme;

                  // ---- 多选内容区（按 selectColumn 决定布局）----
                  Widget buildMultiSelectContent() {
                    final columns = (selectColumn ?? 0).clamp(0, 4);

                    Widget chipFor(SelectOption opt) {
                      final isSelected =
                          selectedCheckboxValues.contains(opt.value);
                      return buildActionSelectChip(
                        context: context,
                        label: opt.name,
                        isSelected: isSelected,
                        maxWidth: 200,   // ← 长选项自动省略
                        onTap: () {
                          setStateDialog(() {
                            if (!isSelected) {
                              if (!selectedCheckboxValues
                                  .contains(opt.value)) {
                                selectedCheckboxValues.add(opt.value);
                              }
                            } else {
                              selectedCheckboxValues.remove(opt.value);
                            }
                          });
                        },
                      );
                    }

                    // 单列
                    if (columns == 1) {
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: options.map((opt) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: chipFor(opt),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }

                    // 固定列数网格
                    if (columns >= 2) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          const spacing = 8.0;
                          final itemWidth = (constraints.maxWidth -
                                  spacing * (columns - 1)) /
                              columns;
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            child: Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: options.map((opt) {
                                return SizedBox(
                                  width: itemWidth,
                                  child: chipFor(opt),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      );
                    }

                    // 自动流式（默认）
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: options.map(chipFor).toList(),
                      ),
                    );
                  }

                  // ---- 单选内容区 ----
                  Widget buildSingleSelectContent() {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: options.map((option) {
                          final isSelected =
                              selectedRadioValue == option.value;
                          return buildActionSelectRadio(
                            context: context,
                            label: option.name,
                            isSelected: isSelected,
                            onTap: () {
                              setStateDialog(() {
                                selectedRadioValue = option.value;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isMultiSelect ? '请选择（多选）' : '请选择',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: isMultiSelect
                            ? buildMultiSelectContent()
                            : buildSingleSelectContent(),
                      ),
                      if (isMultiSelect)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () {
                                setStateDialog(() {
                                  selectedCheckboxValues =
                                      options.map((opt) => opt.value).toList();
                                });
                              },
                              child: const Text('全选'),
                            ),
                            TextButton(
                              onPressed: () {
                                setStateDialog(() {
                                  selectedCheckboxValues = [];
                                });
                              },
                              child: const Text('全清'),
                            ),
                            TextButton(
                              onPressed: () {
                                setStateDialog(() {
                                  final allValues =
                                      options.map((opt) => opt.value).toList();
                                  selectedCheckboxValues = allValues
                                      .where((value) => !selectedCheckboxValues
                                          .contains(value))
                                      .toList();
                                });
                              },
                              child: const Text('反选'),
                            ),
                          ],
                        ),
                      // 底部按钮：与其它 Action 弹窗保持一致
                      ActionButtonBar(
                        showCancel: true,
                        showOk: true,
                        onCancel: () {
                          overlayEntry?.remove();
                        },
                        onOk: () {
                          setState(() {
                            if (isMultiSelect) {
                              _controllers[optionsIndex].text =
                                  selectedCheckboxValues.join(',');
                            } else {
                              _controllers[optionsIndex].text =
                                  selectedRadioValue;
                            }
                            _errors[optionsIndex] = '';
                          });
                          _validateInput(optionsIndex);
                          overlayEntry?.remove();
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    overlayContext.insert(overlayEntry!);
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
            if (displayMessage.isNotEmpty)
              _buildMessage(context, displayMessage),
            if (widget.config.imageUrl != null &&
                widget.config.imageUrl!.isNotEmpty)
              _buildImage(context),

            // ===== 中间滚动区域 =====
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInputList(context),
                    if (widget.config.timeout > 0 && _timeLeft > 0)
                      _buildTimeout(context),
                  ],
                ),
              ),
            ),

            // ===== 底部固定区域 =====
            _buildButtons(context),
          ],
        ),
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

  // ============================================================
  // 输入列表
  //
  // 每个卡片内部布局：
  //   [描述行 + 帮助]
  //   [内联 chip]  ← 仅当选项 ≤ _inlineChipLimit 时显示
  //   [输入框 + 图标按钮（特殊类型 / 下拉按钮）]
  //   [错误信息]
  //
  // 内联 chip 与下拉按钮互斥，避免功能重复。
  // ============================================================
  Widget _buildInputList(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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

            final specialType = _getSpecialType(item);
            final nonSpecialOptions = _getNonSpecialOptions(item);
            final hasNonSpecial = nonSpecialOptions.isNotEmpty;

            // 内联 chip：非特殊 + 有普通选项 + 选项数 ≤ 上限
            final showInlineChips = specialType == null &&
                hasNonSpecial &&
                nonSpecialOptions.length <= _inlineChipLimit;

            // 下拉按钮：非特殊 + 有普通选项 + 不显示 chip
            final showDropdown =
                specialType == null && hasNonSpecial && !showInlineChips;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                  // ===== 描述行 =====
                  if (item.name != null && item.name!.isNotEmpty) ...[
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
                                softWrap: true,
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
                              if (item.help != null &&
                                  item.help!.isNotEmpty)
                                IconButton(
                                  icon: Icon(
                                    Icons.help_outline,
                                    size: 16,
                                    color: colorScheme.outline,
                                  ),
                                  onPressed: () => _showHelp(item.help!),
                                  padding: const EdgeInsets.all(2),
                                  constraints: const BoxConstraints(
                                      minWidth: 28, minHeight: 28),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],

                  // ===== 内联 chip（含与输入框的间距）=====
                  if (showInlineChips)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: nonSpecialOptions.map((option) {
                          final isSelected = _isQuickOptionSelected(
                            controller.text,
                            option.value,
                            item.multiSelect,
                          );
                          return buildActionSelectChip(
                            context: context,
                            label: option.name,
                            isSelected: isSelected,
                            fontSize: 11,
                            onTap: () => _onQuickOptionTap(
                              index,
                              option,
                              item.multiSelect,
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // ===== 输入行 =====
                  Row(
                    children: [
                      Expanded(
                        child: _buildInputField(context, index),
                      ),
                      if (specialType != null) ...[
                        const SizedBox(width: 8),
                        _buildRoundIconButton(
                          context: context,
                          icon: _getSpecialIconData(specialType),
                          background:
                              _getSpecialIconColors(context, specialType).$1,
                          foreground:
                              _getSpecialIconColors(context, specialType).$2,
                          onPressed: () =>
                              _handleSpecialInput(index, specialType),
                        ),
                      ],
                      if (showDropdown) ...[
                        const SizedBox(width: 8),
                        _buildRoundIconButton(
                          context: context,
                          icon: Icons.expand_more,
                          background: colorScheme.surfaceContainerHighest,
                          foreground: colorScheme.onSurfaceVariant,
                          onPressed: () => _openOptionsDialog(index),
                        ),
                      ],
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
        maxLines: item.multiLine.clamp(2, 10),
        decoration: InputDecoration(
          hintText: item.tip ?? '请输入内容...',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onChanged: (_) => _validateInput(index),
      );
    }
  }

  /// 圆形图标按钮
  Widget _buildRoundIconButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? background,
    Color? foreground,
    double size = 36,
  }) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: Size(size, size),
        maximumSize: Size(size, size),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
        backgroundColor: background ?? cs.surfaceContainerHighest,
        foregroundColor: foreground ?? cs.onSurfaceVariant,
        iconSize: size * 0.5,
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  IconData _getSpecialIconData(String type) {
    switch (type) {
      case 'calendar':
        return Icons.calendar_today;
      case 'file':
        return Icons.attach_file;
      case 'folder':
        return Icons.folder_open;
      case 'image':
        return Icons.image;
      default:
        return Icons.help_outline;
    }
  }

  /// 返回 (背景色, 图标色) 元组，全部走 colorScheme 保证主题适配
  (Color, Color) _getSpecialIconColors(BuildContext context, String type) {
    final cs = Theme.of(context).colorScheme;
    switch (type) {
      case 'calendar':
        return (cs.tertiaryContainer, cs.onTertiaryContainer);
      case 'file':
        return (cs.primaryContainer, cs.onPrimaryContainer);
      case 'folder':
        return (cs.secondaryContainer, cs.onSecondaryContainer);
      case 'image':
        return (cs.tertiaryContainer, cs.onTertiaryContainer);
      default:
        return (cs.surfaceContainerHighest, cs.onSurfaceVariant);
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
}