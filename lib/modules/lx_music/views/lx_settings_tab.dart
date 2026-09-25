import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/lx_music/controllers/lx_source_controller.dart';
import 'package:yuanying/modules/lx_music/storage/lx_settings_storage.dart';
import 'package:yuanying/modules/lx_music/views/lx_debug_log_page.dart';
import 'package:yuanying/modules/lx_music/views/lx_favorites_page.dart';
import 'package:yuanying/modules/lx_music/views/lx_playlist_page.dart';
import 'package:yuanying/modules/lx_music/views/lx_recent_page.dart';
import 'package:yuanying/modules/lx_music/views/lx_source_manage_page.dart';

/// 洛雪音乐设置 Tab
class LxSettingsTab extends StatelessWidget {
  const LxSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sourceController = Get.isRegistered<LxSourceController>()
        ? Get.find<LxSourceController>()
        : Get.put(LxSourceController());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ===== 我的音乐 =====
        _sectionTitle('我的音乐', colorScheme),
        _tile(
          context,
          colorScheme,
          icon: Icons.favorite_rounded,
          title: '我喜欢',
          subtitle: '查看洛雪收藏的歌曲',
          onTap: () => Get.to(() => const LxFavoritesPage()),
        ),
        const SizedBox(height: 8),
        _tile(
          context,
          colorScheme,
          icon: Icons.history_rounded,
          title: '最近播放',
          subtitle: '查看洛雪播放历史',
          onTap: () => Get.to(() => const LxRecentPage()),
        ),
        const SizedBox(height: 8),
        _tile(
          context,
          colorScheme,
          icon: Icons.queue_music_rounded,
          title: '我的歌单',
          subtitle: '新建、管理洛雪歌单',
          onTap: () => Get.to(() => const LxPlaylistPage()),
        ),

        const SizedBox(height: 24),

        // ===== 播放 =====
        _sectionTitle('播放', colorScheme),
        FutureBuilder<String>(
          future: LxSettingsStorage.instance.getQuality(),
          builder: (context, snapshot) {
            final q =
                snapshot.data ?? LxSettingsStorage.defaultQuality;
            final label = LxSettingsStorage.qualityLabel(q);
            return _tile(
              context,
              colorScheme,
              icon: Icons.equalizer_rounded,
              title: '音质选择',
              subtitle: label,
              onTap: () => _showQualityPicker(context),
            );
          },
        ),

        const SizedBox(height: 24),

        // ===== 音源 =====
        _sectionTitle('音源', colorScheme),
        Obx(() => _tile(
              context,
              colorScheme,
              icon: Icons.code_rounded,
              title: '自定义源管理',
              subtitle: sourceController.isActive.value
                  ? '已激活 · ${sourceController.scripts.length} 个脚本'
                  : '未激活 · ${sourceController.scripts.length} 个脚本',
              onTap: () =>
                  Get.to(() => const LxSourceManagePage()),
            )),

        const SizedBox(height: 24),

        // ===== 调试 =====
        _sectionTitle('调试', colorScheme),
        _tile(
          context,
          colorScheme,
          icon: Icons.bug_report_outlined,
          title: '调试日志',
          subtitle: '查看脚本请求与响应',
          onTap: () => Get.to(() => const LxDebugLogPage()),
        ),

        const SizedBox(height: 24),

        // ===== 关于 =====
        _sectionTitle('关于', colorScheme),
        _tile(
          context,
          colorScheme,
          icon: Icons.info_outline_rounded,
          title: '洛雪音乐',
          subtitle: '基于洛雪 lx 协议的在线音乐模块',
          onTap: null,
        ),
        const SizedBox(height: 8),
        _tile(
          context,
          colorScheme,
          icon: Icons.description_outlined,
          title: '使用说明',
          subtitle: '导入 JS 脚本后即可使用在线音源',
          onTap: null,
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  /// 音质选择弹窗
  void _showQualityPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FutureBuilder<String>(
        future: LxSettingsStorage.instance.getQuality(),
        builder: (context, snapshot) {
          final current =
              snapshot.data ?? LxSettingsStorage.defaultQuality;
          final colorScheme = Theme.of(context).colorScheme;

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '音质选择',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...LxSettingsStorage.qualityOptions.map((opt) {
                  final selected = opt['id'] == current;
                  return ListTile(
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.outline,
                      size: 20,
                    ),
                    title: Text(
                      opt['name'] ?? '',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      opt['sub'] ?? '',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () async {
                      await LxSettingsStorage.instance
                          .setQuality(opt['id']!);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: colorScheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    ColorScheme colorScheme, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: colorScheme.onSurfaceVariant, size: 20),
        ),
        title: Text(title,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 12))
            : null,
        trailing: onTap != null
            ? Icon(Icons.chevron_right_rounded,
                color: colorScheme.outline, size: 20)
            : null,
      ),
    );
  }
}