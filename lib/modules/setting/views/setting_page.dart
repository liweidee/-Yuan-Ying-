// lib/modules/setting/views/setting_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/setting/views/site_config_page.dart';
import 'package:yuanying/modules/setting/views/style_setting.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/modules/setting/views/play_setting_page.dart';
import 'package:yuanying/modules/setting/views/extra_setting_page.dart';
import 'package:yuanying/modules/setting/views/danmaku_config_page.dart';
import 'package:yuanying/modules/setting/views/tmdb_config_page.dart';
import 'package:yuanying/modules/setting/views/live_config_page.dart';
import 'package:yuanying/core/routes/app_pages.dart';

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        centerTitle: false,
        elevation: 0,
        toolbarHeight: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Style.safeSpace, Style.safeSpace, Style.safeSpace, 100),
        children: [
          _buildSettingItem(
            context: context,
            icon: Icons.api,
            title: '接口配置',
            subtitle: '管理视频源接口',
            onTap: () => Get.to(() => const SiteConfigPage()),
          ),
          const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.live_tv,
            title: '直播配置',
            subtitle: '管理直播源配置（TVBox格式）',
            onTap: () => Get.to(() => const LiveConfigPage()),
          ),
          const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.video_library,
            title: '播放设置',
            subtitle: '播放请求头策略、播放器行为',
            onTap: () => Get.to(() => const PlaySettingPage()),
          ),
          const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.palette_outlined,
            title: '外观设置',
            subtitle: '主题模式、应用主题',
            onTap: () => Get.to(() => const StyleSetting()),
          ),
          const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.closed_caption_outlined,
            title: '弹幕API配置',
            subtitle: '管理LogVar弹幕服务器地址，自动匹配弹幕',
            // onTap: () => Get.toNamed(AppPages.danmakuConfig),
            onTap: () => Get.to(() => const DanmakuConfigPage()),
          ),
          const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.movie_creation_outlined,
            title: 'TMDB 配置',
            subtitle: '配置 TMDB API 访问与代理',
            onTap: () => Get.to(() => const TmdbConfigPage()),
          ),
          const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.more_horiz,
            title: '其它设置',
            subtitle: '高级功能与调试选项',
            onTap: () => Get.to(() => const ExtraSettingPage()),
          ),
          const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.cloud_sync_outlined,
            title: 'WebDAV 设置',
            subtitle: '备份/恢复设置到 WebDAV 服务器',
            onTap: () => Get.toNamed(AppPages.webdav),
          ),
          const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.wifi,
            title: 'WiFi 互传',
            subtitle: '通过 WiFi 传输文件到本机',
            onTap: () => Get.toNamed('/transfer'),
          ),
          const SizedBox(height: 8),
          // _buildSettingItem(
          //   context: context,
          //   icon: Icons.delete_outline,
          //   title: '清除缓存',
          //   subtitle: '清理本地临时文件',
          //   onTap: () {
          //     SmartDialog.showToast('缓存已清除');
          //   },
          // ),
          // const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.description_outlined,
            title: '免责声明',
            subtitle: '使用前请阅读完整条款',
            onTap: () => Get.toNamed(AppPages.disclaimer),
          ),
          const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.info_outline,
            title: '关于',
            subtitle: '应用版本与相关信息',
            onTap: () => Get.toNamed(AppPages.about),  // 跳转到关于页面
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    // 使用 Material 包裹，修复 ListTile 涟漪效果
    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: Style.mdRadius,
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                  borderRadius: Style.mdRadius,
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}