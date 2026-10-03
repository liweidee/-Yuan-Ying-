// lib/common/widgets/dialog/ordered_multi_select_dialog.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/theme/style.dart';

/// 有序多选对话框
///
/// 与 [MultiSelectDialog] 的区别：
/// - 选中项显示序号（1、2、3...），序号代表优先级
/// - 取消选中时后续序号自动前移
/// - 返回值顺序即用户选择的顺序
///
/// 典型用途：硬解模式回退链（mpv 的 --hwdec=mediacodec,auto-safe）
class OrderedMultiSelectDialog<T> extends StatefulWidget {
  final Iterable<T> initValues;
  final String title;
  final Map<T, String> values;

  const OrderedMultiSelectDialog({
    super.key,
    required this.initValues,
    required this.values,
    required this.title,
  });

  @override
  State<OrderedMultiSelectDialog<T>> createState() =>
      _OrderedMultiSelectDialogState<T>();
}

class _OrderedMultiSelectDialogState<T>
    extends State<OrderedMultiSelectDialog<T>> {
  late Map<T, int> _tempValues;

  @override
  void initState() {
    super.initState();
    // 键的顺序即优先级（index + 1 = 序号）
    _tempValues = {for (final (i, j) in widget.initValues.indexed) j: i + 1};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      title: Text(widget.title, style: theme.textTheme.titleMedium),
      contentPadding: const EdgeInsets.only(top: 12),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.values.entries.map((i) {
                return Builder(
                  builder: (context) {
                    return _OrderedCheckboxListTile(
                      dense: true,
                      value: _tempValues[i.key],
                      title: Text(
                        i.value,
                        style: theme.textTheme.titleMedium,
                      ),
                      onChanged: (value) {
                        if (value == null) {
                          // 未选中 → 选中，追加到末尾
                          _tempValues[i.key] = _tempValues.length + 1;
                          (context as Element).markNeedsBuild();
                        } else {
                          // 已选中 → 取消，后续序号前移
                          final pos = _tempValues.remove(i.key)!;
                          if (pos == _tempValues.length + 1) {
                            // 取消的是最后一个，直接刷新
                            (context as Element).markNeedsBuild();
                          } else {
                            _tempValues.updateAll(
                              (key, value) => value > pos ? value - 1 : value,
                            );
                            setState(() {});
                          }
                        }
                      },
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: () => Get.back(result: _tempValues.keys.toList()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 带序号的复选框（对应 PiliPlus 的 OrderedCheckbox）
class _OrderedCheckbox extends StatelessWidget {
  const _OrderedCheckbox({
    required this.value,
    required this.onChanged,
  });

  /// 序号，null 表示未选中
  final int? value;
  final ValueChanged<int?>? onChanged;
  bool get selected => value != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final child = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(2)),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
          width: 1.6,
          strokeAlign: BorderSide.strokeAlignCenter,
        ),
        color: selected ? theme.colorScheme.primary : null,
      ),
      child: selected
          ? SizedBox.square(
              dimension: 18,
              child: Center(
                child: Text(
                  value.toString(),
                  style: TextStyle(
                    inherit: false,
                    color: theme.colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
            )
          : const SizedBox.square(dimension: 18),
    );
    if (onChanged != null) {
      return InkWell(
        onTap: () => onChanged!(value),
        child: child,
      );
    }
    return child;
  }
}

/// 带序号的复选框列表项
class _OrderedCheckboxListTile extends StatelessWidget {
  const _OrderedCheckboxListTile({
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.dense,
  });

  final int? value;
  final ValueChanged<int?>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final bool? dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MergeSemantics(
      child: ListTile(
        leading: _OrderedCheckbox(
          value: value,
          onChanged: null, // 整个 tile 的 onTap 处理
        ),
        title: title,
        subtitle: subtitle,
        dense: dense,
        enabled: onChanged != null,
        onTap: onChanged != null ? () => onChanged!(value) : null,
        selected: value != null,
        selectedColor: colorScheme.primary,
      ),
    );
  }
}