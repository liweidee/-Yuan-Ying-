// lib/modules/live/widgets/live_channel_list.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/live/controllers/live_controller.dart';
import 'package:yuanying/modules/live/models/live_channel.dart';

class LiveChannelList extends StatelessWidget {
  const LiveChannelList({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveController>(tag: 'live');
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final channels = controller.currentGroupChannels;
      if (channels.isEmpty) {
        return Center(
          child: Text(
            '该分组暂无频道',
            style: TextStyle(color: colorScheme.outline, fontSize: 13),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
          return _ChannelItem(channel: channel);
        },
      );
    });
  }
}

class _ChannelItem extends StatefulWidget {
  final LiveChannel channel;

  const _ChannelItem({required this.channel});

  @override
  State<_ChannelItem> createState() => _ChannelItemState();
}

class _ChannelItemState extends State<_ChannelItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveController>(tag: 'live');
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final isCurrent = controller.currentChannel.value?.url == widget.channel.url;

      Color? getBgColor() {
        if (isCurrent) return colorScheme.primaryContainer.withOpacity(0.25);
        if (_isHovered) return colorScheme.primaryContainer.withOpacity(0.08);
        return Colors.transparent;
      }

      return MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => controller.playChannel(widget.channel),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: getBgColor(),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  // 小圆点指示器
                  if (isCurrent)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (isCurrent) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.channel.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                        color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (isCurrent)
                    Icon(
                      Icons.play_circle_filled,
                      color: colorScheme.primary,
                      size: 16,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}