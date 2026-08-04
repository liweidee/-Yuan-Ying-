import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

/// 播放请求头策略
enum HeaderStrategy {
  smart,   // 智能模式（推荐）
  full,    // 完整模式
  minimal, // 最小模式
}

extension HeaderStrategyExtension on HeaderStrategy {
  String get title {
    switch (this) {
      case HeaderStrategy.smart:
        return '智能模式（推荐）';
      case HeaderStrategy.full:
        return '完整模式';
      case HeaderStrategy.minimal:
        return '最小模式';
    }
  }

  String get description {
    switch (this) {
      case HeaderStrategy.smart:
        return '只对已知需要 UA 的 CDN 添加 User-Agent，其他链接不添加';
      case HeaderStrategy.full:
        return '始终添加完整的浏览器 User-Agent 请求头，适合需要 UA 才能播放的源';
      case HeaderStrategy.minimal:
        return '只添加 Accept 头，不带 User-Agent，适合带 UA 反而无法播放的源';
    }
  }
}

class HeaderStrategyDialog extends StatefulWidget {
  const HeaderStrategyDialog({super.key});

  @override
  State<HeaderStrategyDialog> createState() => _HeaderStrategyDialogState();

  static Future<HeaderStrategy?> show(BuildContext context) async {
    return showModalBottomSheet<HeaderStrategy>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const HeaderStrategyDialog(),
    );
  }
}

class _HeaderStrategyDialogState extends State<HeaderStrategyDialog> {
  late HeaderStrategy _selected;

  @override
  void initState() {
    super.initState();
    _selected = HeaderStrategy.values[PlayerPref.requestHeaderStrategy.clamp(0, 2)];
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
          // ===== 标题 =====
          Center(
            child: Text(
              '播放请求头策略',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ===== 选项列表 =====
          ...HeaderStrategy.values.map((strategy) {
            final isSelected = _selected == strategy;
            return _buildOption(
              context: context,
              strategy: strategy,
              isSelected: isSelected,
              onTap: () {
                setState(() {
                  _selected = strategy;
                });
                Future.delayed(const Duration(milliseconds: 200), () {
                  Navigator.pop(context, strategy);
                });
              },
            );
          }),

          const SizedBox(height: 16),

          // ===== 底部提示框 =====
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
                    '播放失败时会自动尝试其他策略重试，无需手动切换',
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
    required HeaderStrategy strategy,
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
            // ===== 单选按钮 =====
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

            // ===== 文字 =====
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strategy.title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    strategy.description,
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