// lib/modules/live/widgets/live_group_list.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/live/controllers/live_controller.dart';

class LiveGroupList extends StatelessWidget {
  final double width;
  final bool isDesktop;

  const LiveGroupList({
    super.key,
    this.width = 80,
    this.isDesktop = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      color: isDesktop
          ? colorScheme.surfaceContainerHighest.withOpacity(0.5)
          : colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Obx(() {
        final controller = Get.find<LiveController>(tag: 'live');
        if (controller.groups.isEmpty) {
          return Center(
            child: Text(
              '无分组',
              style: TextStyle(color: colorScheme.outline, fontSize: 12),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: controller.groups.length,
          itemBuilder: (context, index) {
            final group = controller.groups[index];
            return _GroupItem(
              group: group,
              isDesktop: isDesktop,
            );
          },
        );
      }),
    );
  }
}

class _GroupItem extends StatelessWidget {
  final String group;
  final bool isDesktop;

  const _GroupItem({
    required this.group,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveController>(tag: 'live');
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final isSelected = controller.selectedGroup.value == group;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => controller.selectedGroup.value = group,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), // 只改这里：8→12
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primaryContainer.withOpacity(0.35)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                if (isSelected) const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    group,
                    style: TextStyle(
                      fontSize: isDesktop ? 13 : 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 2),
                  Text(
                    '${_getChannelCount(controller, group)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected
                          ? colorScheme.primary.withOpacity(0.6)
                          : colorScheme.outline.withOpacity(0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  int _getChannelCount(LiveController controller, String group) {
    return controller.channels.where((ch) => ch.group == group).length;
  }
}