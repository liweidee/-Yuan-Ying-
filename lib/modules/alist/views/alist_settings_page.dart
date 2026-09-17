import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import '../controllers/alist_server_controller.dart';
import '../models/alist_server.dart';

class AlistSettingsPage extends StatelessWidget {
  const AlistSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: [
          // ==================== 当前账户 ====================
          _sectionHeader(theme, '当前账户'),
          if (server != null) _accountCard(theme, server),

          // ==================== 操作 ====================
          _sectionHeader(theme, '操作'),
          _cardRow(
            theme,
            icon: Icons.switch_account_outlined,
            title: '切换账户',
            subtitle: '切换到其它 AList 账户',
            onTap: () => Get.toNamed(AppPages.alistServerConfig),
          ),
          const SizedBox(height: 6),
          _cardRow(
            theme,
            icon: Icons.swap_horiz_rounded,
            title: '返回服务器列表',
            subtitle: '管理已保存的服务器',
            onTap: _backToServerList,
          ),

          // ==================== 浏览与存储 ====================
          _sectionHeader(theme, '浏览与存储'),
          _cardRow(
            theme,
            icon: Icons.sd_storage_outlined,
            title: '缓存管理',
            subtitle: '查看和清理本地缓存',
            onTap: () => Get.toNamed(AppPages.alistCache),
          ),

          // ==================== 危险操作 ====================
          _sectionHeader(theme, '危险操作'),
          _cardRow(
            theme,
            icon: Icons.logout_rounded,
            title: '退出登录',
            subtitle: '清除该账户的登录状态',
            titleColor: cs.error,
            iconColor: cs.error,
            onTap: server == null
                ? null
                : () => _confirmLogout(context, serverCtrl, server),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 返回到路由栈中已有的服务器列表页。
  /// 用 `Get.until` 回退到栈内已有的 alistServerConfig，保留上层路由。
  void _backToServerList() {
    Get.until((route) {
      final name = route.settings.name;
      return name == AppPages.alistServerConfig || route.isFirst;
    });
  }

  Future<void> _confirmLogout(
    BuildContext context,
    AlistServerController serverCtrl,
    AlistServer server,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: Text('确认退出 "${server.username ?? server.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await serverCtrl.logout(server.id);
    // 与"返回服务器列表"按钮一致：回到栈内已有的服务器列表
    _backToServerList();
  }

  // ============================================================
  // 样式辅助
  // ============================================================

  /// 分区标题（主题色小字）
  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /// 当前账户信息卡（稍大，含服务器名 / URL / 用户名）
  Widget _accountCard(ThemeData theme, AlistServer server) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.cloud, color: cs.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    server.serverUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '用户：${server.username ?? '游客'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
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

  /// 通用操作行（卡片式，无下划线）
  Widget _cardRow(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Color? titleColor,
    Color? iconColor,
  }) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: iconColor ?? cs.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: titleColor ?? cs.onSurface,
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}