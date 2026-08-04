// lib/common/widgets/dialog/select_dialog.dart
import 'package:flutter/material.dart';
import 'package:yuanying/core/theme/style.dart';

class SelectDialog<T> extends StatelessWidget {
  final T? value;
  final String title;
  final List<(T, String)> values;
  final bool toggleable;

  const SelectDialog({
    super.key,
    this.value,
    required this.values,
    required this.title,
    this.toggleable = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: Style.mdRadius,
      ),
      title: Text(title, style: theme.textTheme.titleMedium),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      // ===== 只限制最大高度，宽度由 AlertDialog 自动控制 =====
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                values.length,
                (index) {
                  final item = values[index];
                  final isSelected = value == item.$1;
                  return RadioListTile<T>(
                    toggleable: toggleable,
                    dense: true,
                    value: item.$1,
                    groupValue: value,
                    title: Text(
                      item.$2,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                    ),
                    onChanged: (v) => Navigator.of(context).pop(v ?? value),
                    activeColor: theme.colorScheme.primary,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}