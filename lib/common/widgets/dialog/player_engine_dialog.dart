import 'package:flutter/material.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

enum PlayerEngineOption {
  mpv, // MPV 引擎
  mdk, // MDK 引擎
}

extension PlayerEngineOptionExtension on PlayerEngineOption {
  String get title {
    switch (this) {
      case PlayerEngineOption.mpv:
        return 'MPV';
      case PlayerEngineOption.mdk:
        return 'MDK';
    }
  }

  String get description {
    switch (this) {
      case PlayerEngineOption.mpv:
        return '功能全面，支持音轨/视轨/字幕';
      case PlayerEngineOption.mdk:
        return '使用系统解码，轻量高效';
    }
  }
}

class PlayerEngineDialog extends StatefulWidget {
  const PlayerEngineDialog({super.key});

  @override
  State<PlayerEngineDialog> createState() => _PlayerEngineDialogState();

  static Future<PlayerEngineOption?> show(BuildContext context) async {
    return showModalBottomSheet<PlayerEngineOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const PlayerEngineDialog(),
    );
  }
}

class _PlayerEngineDialogState extends State<PlayerEngineDialog> {
  late PlayerEngineOption _selected;

  @override
  void initState() {
    super.initState();
    final type = PlayerPref.playerEngine;
    _selected = type == PlayerEngineType.fvp
        ? PlayerEngineOption.mdk
        : PlayerEngineOption.mpv;
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
              '选择播放器',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 选项列表
          ...PlayerEngineOption.values.map((option) {
            final isSelected = _selected == option;
            return _buildOption(
              context: context,
              option: option,
              isSelected: isSelected,
              onTap: () {
                setState(() {
                  _selected = option;
                });
                Future.delayed(const Duration(milliseconds: 200), () {
                  Navigator.pop(context, option);
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
                    '切换播放器后当前视频将重新加载',
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
    required PlayerEngineOption option,
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
                    option.title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.description,
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