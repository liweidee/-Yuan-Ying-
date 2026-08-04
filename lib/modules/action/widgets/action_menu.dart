// lib/modules/action/widgets/action_menu.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/action_config.dart';
import '../models/button_type.dart';
import '../models/action_type.dart';
import 'action_renderer.dart';

class MenuAction extends StatefulWidget {
  const MenuAction({
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
  State<MenuAction> createState() => _MenuActionState();
}

class _MenuActionState extends State<MenuAction> {
  late final ActionRenderer _renderer;

  List<MenuOptionConfig> _options = [];
  List<MenuOptionConfig> _selectedOptions = [];
  String _searchKeyword = '';
  Timer? _timeoutTimer;
  int _timeLeft = 0;

  bool get _isMultiSelect => widget.config.type == ActionType.select;

  List<MenuOptionConfig> get _filteredOptions {
    if (_searchKeyword.isEmpty) return _options;
    final keyword = _searchKeyword.toLowerCase();
    return _options.where((opt) {
      final nameMatch = opt.name.toLowerCase().contains(keyword);
      final descMatch = opt.description?.toLowerCase().contains(keyword) ?? false;
      return nameMatch || descMatch;
    }).toList();
  }

  bool get _showOkButton => widget.config.button.showOk;
  bool get _showCancelButton => widget.config.button.showCancel;

  bool get _isValid {
    if (_isMultiSelect) {
      return _selectedOptions.isNotEmpty;
    } else {
      return _selectedOptions.length == 1;
    }
  }

  @override
  void initState() {
    super.initState();
    _renderer = Get.find<ActionRenderer>();
    _initOptions();
    if (widget.visible) {
      _startTimeout();
    }
  }

  @override
  void didUpdateWidget(MenuAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _startTimeout();
      } else {
        _stopTimeout();
      }
    }
    if (widget.config.options != oldWidget.config.options) {
      _initOptions();
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _initOptions() {
    _options = widget.config.options ?? [];
    _selectedOptions = [];

    if (widget.config.selectedIndex >= 0 &&
        widget.config.selectedIndex < _options.length) {
      final option = _options[widget.config.selectedIndex];
      if (!_isMultiSelect) {
        _selectedOptions = [option];
      } else {
        _selectedOptions.add(option);
      }
    } else {
      for (final option in _options) {
        if (option.selected) {
          if (!_isMultiSelect) {
            _selectedOptions = [option];
            break;
          } else {
            _selectedOptions.add(option);
          }
        }
      }
    }

    if (!_isMultiSelect && _selectedOptions.isEmpty && _options.isNotEmpty) {
      _selectedOptions = [_options.first];
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

  bool _isSelected(MenuOptionConfig option) {
    return _selectedOptions.any((selected) => selected.optionValue == option.optionValue);
  }

  void _toggleOption(MenuOptionConfig option) {
    if (option.disabled) return;

    setState(() {
      if (_isMultiSelect) {
        if (_isSelected(option)) {
          _selectedOptions.removeWhere((selected) => selected.optionValue == option.optionValue);
        } else {
          _selectedOptions.add(option);
        }
      } else {
        _selectedOptions = [option];
        if (widget.config.autoSubmit) {
          Future.delayed(const Duration(milliseconds: 100), _handleSubmit);
        }
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedOptions = List.from(_filteredOptions);
    });
  }

  void _clearAll() {
    setState(() {
      _selectedOptions.clear();
    });
  }

  void _invertSelection() {
    setState(() {
      final currentValues = _selectedOptions.map((opt) => opt.optionValue).toSet();
      _selectedOptions = _filteredOptions.where((opt) {
        return !currentValues.contains(opt.optionValue);
      }).toList();
    });
  }

  void _removeSelection(MenuOptionConfig option) {
    setState(() {
      _selectedOptions.removeWhere((selected) => selected.optionValue == option.optionValue);
    });
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchKeyword = value;
    });
  }

  void _handleSubmit() {
    if (!_isValid) return;

    final result = <String, dynamic>{};

    if (_isMultiSelect) {
      result['selectedValues'] = _selectedOptions.map((opt) => opt.optionValue).toList();
      result['selectedOptions'] = _selectedOptions.map((opt) => opt.name).toList();
      final allStatus = _options.map((opt) => {
        'name': opt.name,
        'action': opt.optionValue,
        'selected': _selectedOptions.any((selected) => selected.optionValue == opt.optionValue),
      }).toList();
      result['allStatus'] = allStatus;
    } else {
      final selected = _selectedOptions.isNotEmpty ? _selectedOptions.first : null;
      result['selectedValue'] = selected?.optionValue ?? '';
      result['selectedOption'] = selected?.name ?? '';
    }

    if (widget.config.actionId.isNotEmpty) {
      final value = _isMultiSelect
          ? _options.map((opt) => {
              'name': opt.name,
              'action': opt.optionValue,
              'selected': _selectedOptions.any((selected) => selected.optionValue == opt.optionValue),
            }).toList()
          : (_selectedOptions.isNotEmpty ? _selectedOptions.first.optionValue : '');

      widget.onAction?.call({
        'actionId': widget.config.actionId,
        'value': value,
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

  Widget _buildOptionIcon(MenuOptionConfig option) {
    if (option.icon == null || option.icon!.isEmpty) {
      return const SizedBox(width: 24, height: 24);
    }

    final icon = option.icon!;

    if (icon.startsWith('http')) {
      return Image.network(
        icon,
        width: 24,
        height: 24,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.image_not_supported, size: 20);
        },
      );
    }

    if (icon.contains('<svg')) {
      return Icon(
        Icons.category,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    return Text(
      icon,
      style: const TextStyle(fontSize: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (_renderer.shouldReset.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _selectedOptions.clear();
          _renderer.shouldReset.value = false;
        });
      }

      final displayMessage = _renderer.currentMessage.value.isNotEmpty
          ? _renderer.currentMessage.value
          : widget.config.msg ?? '';

      // 控制最大高度，与其他弹窗一致（屏幕高度的 65%）
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.65,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (displayMessage.isNotEmpty) _buildMessage(context, displayMessage),
            if (widget.config.imageUrl != null && widget.config.imageUrl!.isNotEmpty)
              _buildImage(context),
            if (widget.config.searchable) _buildSearch(context),
            _buildOptionList(context),
            if (_isMultiSelect && _filteredOptions.isNotEmpty)
              _buildQuickActions(context),
            if (_isMultiSelect && _selectedOptions.isNotEmpty)
              _buildSelectedItems(context),
            if (widget.config.timeout > 0 && _timeLeft > 0) _buildTimeout(context),
            _buildButtons(context),
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

  Widget _buildSearch(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索选项...',
          prefixIcon: Icon(Icons.search, color: colorScheme.outline),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildOptionList(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredOptions;

    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: Text(
          '没有匹配的选项',
          style: TextStyle(fontSize: 14, color: colorScheme.outline),
        ),
      );
    }

    // 使用 LayoutBuilder 获取父级实际宽度
    return Flexible(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 获取可用宽度（减去内边距）
          final availableWidth = constraints.maxWidth;
          
          // 计算列数：
          // 1. 如果用户配置了 column > 1，使用用户配置
          // 2. 否则根据宽度自动计算（每个选项至少 120px，最多 4 列）
          final configuredColumns = widget.config.column;
          int maxColumns;
          if (configuredColumns > 1) {
            maxColumns = configuredColumns.clamp(1, 4);
          } else {
            // 自动计算：每个选项至少 120px 宽
            final autoColumns = (availableWidth / 120).floor();
            maxColumns = autoColumns.clamp(2, 4);  // 至少 2 列，最多 4 列
          }
          
          // 计算每项宽度
          final spacing = 8.0;
          final totalSpacing = (maxColumns - 1) * spacing;
          final itemWidth = (availableWidth - totalSpacing) / maxColumns;

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: filtered.map((option) {
                final isSelected = _isSelected(option);
                return SizedBox(
                  width: itemWidth,
                  child: _buildOptionItem(context, option, isSelected),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOptionItem(
    BuildContext context,
    MenuOptionConfig option,
    bool isSelected,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: option.disabled ? null : () => _toggleOption(option),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              _buildOptionIcon(option),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  option.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: option.disabled
                        ? colorScheme.outline
                        : isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (isSelected)
                Icon(
                  _isMultiSelect ? Icons.check_box : Icons.radio_button_checked,
                  size: 16,
                  color: colorScheme.primary,
                )
              else
                Icon(
                  _isMultiSelect ? Icons.check_box_outline_blank : Icons.radio_button_unchecked,
                  size: 16,
                  color: colorScheme.outline,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
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
            onPressed: _selectedOptions.length == _filteredOptions.length
                ? null
                : _selectAll,
            icon: const Icon(Icons.select_all, size: 18),
            label: const Text('全选'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
          TextButton.icon(
            onPressed: _selectedOptions.isEmpty ? null : _clearAll,
            icon: const Icon(Icons.clear, size: 18),
            label: const Text('全清'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
          TextButton.icon(
            onPressed: _filteredOptions.isEmpty ? null : _invertSelection,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('反选'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedItems(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_selectedOptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '已选择项目',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_selectedOptions.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 限制最大高度 60px（约 2 行），超出可滚动
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 60),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _selectedOptions.map((option) {
                  return Chip(
                    label: Text(
                      option.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    onDeleted: () => _removeSelection(option),
                    deleteIcon: Icon(Icons.close, size: 14, color: colorScheme.outline),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
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