import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';

class LabPage extends StatelessWidget {
  const LabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 顶部状态栏安全区（去掉 AppBar 后需要自己补）
    final topInset = MediaQuery.of(context).padding.top;
    // 底部安全区：系统手势条 / 导航栏 + 额外呼吸间距
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      // 去掉 appBar，让内容从顶部开始
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Style.safeSpace,
          // 顶部叠加状态栏高度 + 呼吸间距
          topInset + Style.safeSpace,
          Style.safeSpace,
          // 底部叠加安全区高度 + 呼吸间距
          Style.safeSpace + bottomInset + 12,
        ),
        children: [
          // ===== 媒体服务器 =====
          _buildEntry(
            context,
            theme,
            icon: Icons.movie_filter_rounded,
            title: 'Emby 媒体服务器',
            subtitle: '连接您的 Emby 服务器，浏览媒体库',
            route: AppPages.embyServerConfig,
          ),
          const SizedBox(height: 12),
          _buildEntry(
            context,
            theme,
            icon: Icons.live_tv_outlined,
            title: 'Jellyfin 媒体服务器',
            subtitle: '连接您的 Jellyfin 服务器，浏览媒体库',
            route: AppPages.jellyfinServerConfig,
          ),

          // ===== 网盘 / 工具 =====
          const SizedBox(height: 12),
          _buildEntry(
            context,
            theme,
            icon: Icons.cloud_outlined,
            title: 'AList 网盘',
            subtitle: '连接您的 AList 服务器，浏览网盘文件',
            route: AppPages.alistServerConfig,
          ),
          const SizedBox(height: 12),
          _buildEntry(
            context,
            theme,
            icon: Icons.travel_explore,
            title: '网页嗅探器',
            subtitle: '访问网页并嗅探视频资源，一键播放',
            route: AppPages.webSniffer,
          ),
          const SizedBox(height: 12),
          _buildEntry(
            context,
            theme,
            icon: Icons.cloud_outlined,
            title: 'WebDAV',
            subtitle: '连接 WebDAV 服务器，浏览和下载文件',
            route: AppPages.webdavServerConfig,
          ),
          const SizedBox(height: 12),
          _buildEntry(
            context,
            theme,
            icon: Icons.folder_outlined,
            title: 'FTP / SFTP',
            subtitle: '连接 FTP 或 SFTP 服务器，浏览和下载文件',
            route: AppPages.ftpServerConfig,
          ),
          const SizedBox(height: 12),
          _buildEntry(
            context,
            theme,
            icon: Icons.storage_outlined,
            title: 'SMB / NAS',
            subtitle: '连接局域网 SMB 共享，浏览和下载文件',
            route: AppPages.smbServerConfig,
          ),
          const SizedBox(height: 12),
          _buildEntry(
            context,
            theme,
            icon: Icons.cloud_sync_outlined,
            title: '飞牛影视',
            subtitle: '连接 FnOS / 飞牛影视服务器，浏览媒体库',
            route: AppPages.fnosServerConfig,
          ),
        ],
      ),
    );
  }

  /// 通用卡片入口（后续新增协议只需一行调用）
  Widget _buildEntry(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: () => Get.toNamed(route),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                  borderRadius: Style.mdRadius,
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
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