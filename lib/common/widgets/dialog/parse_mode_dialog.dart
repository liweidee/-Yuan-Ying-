import 'package:flutter/material.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

enum ParseMode {
  sequential, // 顺序解析
  concurrent, // 并发解析
}

extension ParseModeExtension on ParseMode {
  String get title {
    switch (this) {
      case ParseMode.sequential:
        return '顺序解析';
      case ParseMode.concurrent:
        return '并发解析';
    }
  }

  String get description {
    switch (this) {
      case ParseMode.sequential:
        return '依次尝试每个解析接口，直到成功';
      case ParseMode.concurrent:
        return '同时调用所有解析接口，哪个先返回就用哪个';
    }
  }
}

class ParseModeDialog extends StatefulWidget {
  const ParseModeDialog({super.key});

  @override
  State<ParseModeDialog> createState() => _ParseModeDialogState();

  static Future<ParseMode?> show(BuildContext context) async {
    return showModalBottomSheet<ParseMode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const ParseModeDialog(),
    );
  }
}

class _ParseModeDialogState extends State<ParseModeDialog> {
  late ParseMode _selected;

  @override
  void initState() {
    super.initState();
    final index = PlayerPref.parseMode.clamp(0, 1);
    _selected = ParseMode.values[index];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题
          Center(
            child: Text(
              '解析模式',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 选项列表
          ...ParseMode.values.map((mode) {
            final isSelected = _selected == mode;
            return _buildOption(
              context: context,
              mode: mode,
              isSelected: isSelected,
              onTap: () {
                setState(() {
                  _selected = mode;
                });
                Future.delayed(const Duration(milliseconds: 200), () {
                  Navigator.pop(context, mode);
                });
              },
            );
          }),

          const SizedBox(height: 16),

          // 底部提示框
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '解析失败时会自动切换模式重试，无需手动切换',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required ParseMode mode,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: Style.mdRadius,
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withOpacity(0.3)
                : colorScheme.outline.withOpacity(0.1),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? colorScheme.primary.withOpacity(0.08)
                  : Colors.transparent,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 单选按钮
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? colorScheme.primary : colorScheme.outline,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // 文字
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.description,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}