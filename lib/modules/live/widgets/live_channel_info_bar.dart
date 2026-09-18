import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/live_controller.dart';
import 'live_epg_sheet.dart';
import 'channel_logo.dart';

class LiveChannelInfoBar extends StatelessWidget {
  const LiveChannelInfoBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<LiveController>(tag: 'live');
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final channel = ctrl.currentChannel.value;
      if (channel == null) {
        return _buildEmpty(context, colorScheme, '未选择频道');
      }

      final epgLoading = ctrl.epgLoading.value;
      final epgError = ctrl.epgError.value;
      final programme = ctrl.currentProgramme;

      String subtitle;
      if (epgLoading) {
        subtitle = '节目单加载中...';
      } else if (epgError.isNotEmpty) {
        subtitle = epgError;
      } else if (programme == null) {
        subtitle = '暂无节目单';
      } else {
        final remain = programme.remainingAt(DateTime.now());
        final remainMin = remain.inMinutes;
        subtitle = '${programme.title} · 剩余 $remainMin 分钟';
      }

      return InkWell(
        onTap: () => _showEpgSheet(context, ctrl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: colorScheme.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // 频道 Logo
                  ChannelLogo(
                    url: ctrl.currentLogoUrl,
                    size: 44,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          channel.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (programme != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.list_alt_rounded,
                      size: 20,
                      color: colorScheme.outline,
                    ),
                  ],
                ],
              ),
              if (programme != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: programme.progressAt(DateTime.now()),
                    minHeight: 2,
                    backgroundColor: colorScheme.outline.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _buildEmpty(BuildContext context, ColorScheme colorScheme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      color: colorScheme.surface,
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: colorScheme.outline),
      ),
    );
  }

  void _showEpgSheet(BuildContext context, LiveController ctrl) {
    final programmes = ctrl.todayProgrammes;
    if (programmes.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LiveEpgSheet(
        channelName: ctrl.currentChannel.value?.name ?? '',
        programmes: programmes,
      ),
    );
  }
}