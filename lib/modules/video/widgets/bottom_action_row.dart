import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/custom_icon.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';

/// 底部操作按钮区（左右翻转、上下翻转、听视频、后台播放）
class BottomActionRow extends StatelessWidget {
  // ===== 与 PiliPlus 一致：通过构造函数接收 controllerTag =====
  final String controllerTag;
  const BottomActionRow({super.key, required this.controllerTag});

  @override
  Widget build(BuildContext context) {
    // ===== 带 tag 查找 DetailController =====
    final controller = Get.find<DetailController>(tag: controllerTag);
    final playerController = controller.playerController;
    final theme = Theme.of(context);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Obx(() {
        final flipX = playerController.flipX.value;
        final flipY = playerController.flipY.value;
        final onlyPlayAudio = playerController.onlyPlayAudio.value;
        final continueBg = playerController.continuePlayInBackground.value;

        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildActionChip(
              context,
              icon: Icons.flip,
              label: '左右翻转',
              selected: flipX,
              onTap: () => playerController.flipX.value = !flipX,
            ),
            const SizedBox(width: 8),
            _buildActionChip(
              context,
              icon: CustomIcons.view_headline_rotate_90,
              label: '上下翻转',
              selected: flipY,
              onTap: () => playerController.flipY.value = !flipY,
            ),
            const SizedBox(width: 8),
            _buildActionChip(
              context,
              icon: Icons.headphones,
              label: '听视频',
              selected: onlyPlayAudio,
              onTap: () {
                playerController.onlyPlayAudio.value = !onlyPlayAudio;
                controller.playerInit();
              },
            ),
            const SizedBox(width: 8),
            _buildActionChip(
              context,
              icon: Icons.play_circle_outline,
              label: '后台播放',
              selected: continueBg,
              onTap: playerController.setContinuePlayInBackground,
            ),
          ],
        );
      }),
    );
  }

  Widget _buildActionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.secondaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : colorScheme.secondaryContainer,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}