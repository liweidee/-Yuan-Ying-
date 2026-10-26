// lib/modules/action/widgets/action_chip_style.dart
import 'package:flutter/material.dart';

/// 统一的 Action 选择 Chip 样式。
///
/// - 选中：`secondaryContainer` 底 + 首部对勾
/// - 未选中：淡灰底 + 透明对勾占位（保持宽度稳定）
/// - 小圆角（8），比胶囊更贴合列表/网格布局
/// - 支持 [maxWidth] 限制，超长文字自动省略
Widget buildActionSelectChip({
  required BuildContext context,
  required String label,
  required bool isSelected,
  required VoidCallback onTap,
  double fontSize = 12,
  double? maxWidth,
}) {
  final cs = Theme.of(context).colorScheme;

  final chip = ChoiceChip(
    avatar: Icon(
      Icons.check,
      size: fontSize + 2,
      color: isSelected ? cs.onSecondaryContainer : Colors.transparent,
    ),
    label: Text(
      label,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
        color: isSelected ? cs.onSecondaryContainer : cs.onSurface,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    selected: isSelected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
    selectedColor: cs.secondaryContainer,
    side: BorderSide(
      color: isSelected
          ? cs.secondary.withValues(alpha: 0.4)
          : cs.outlineVariant.withValues(alpha: 0.5),
      width: 1,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  if (maxWidth != null) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: chip,
    );
  }
  return chip;
}

/// 统一的 Action 单选行样式。
///
/// - 选中：`secondaryContainer` 高亮整行 + 实心圆
/// - 未选中：淡灰底 + 空心圆
Widget buildActionSelectRadio({
  required BuildContext context,
  required String label,
  required bool isSelected,
  required VoidCallback onTap,
  double fontSize = 14,
}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: isSelected
          ? cs.secondaryContainer
          : cs.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: isSelected ? cs.primary : cs.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.normal,
                    color:
                        isSelected ? cs.onSecondaryContainer : cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}