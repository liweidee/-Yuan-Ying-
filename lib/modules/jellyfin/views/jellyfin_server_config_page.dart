import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import '../controllers/jellyfin_server_controller.dart';
import '../models/jellyfin_server_model.dart';
import '../services/jellyfin_api_service.dart';

class JellyfinServerConfigPage extends StatelessWidget {
  const JellyfinServerConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<JellyfinServerController>()) {
      Get.put(JellyfinServerController());
    }
    final controller = Get.find<JellyfinServerController>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Jellyfin 服务器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          IconButton(
            onPressed: () => _showAddDialog(context, controller),
            icon: const Icon(Icons.add, size: 28),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.servers.isEmpty) {
          return _buildEmptyState(context, theme, controller);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(Style.safeSpace),
          itemCount: controller.servers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final server = controller.servers[index];
            final isCurrent = controller.currentServerId.value == server.id;
            final hasToken = controller.getToken(server.id) != null;
            return _buildServerCard(context, theme, controller, server, hasToken);
          },
        );
      }),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme, JellyfinServerController controller) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns_outlined, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('暂无服务器', style: TextStyle(color: theme.colorScheme.outline)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _showAddDialog(context, controller),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
            ),
            child: const Text('添加服务器'),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard(
    BuildContext context,
    ThemeData theme,
    JellyfinServerController controller,
    JellyfinServer server,
    bool hasToken,
  ) {
    return Card(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      elevation: 1,
      child: ListTile(
        leading: Icon(
          Icons.dns,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          server.name,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          server.baseUrl,
          style: TextStyle(color: theme.colorScheme.outline, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasToken)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '未登录',
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.error),
                ),
              ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: theme.colorScheme.outline),
              tooltip: '更多菜单',
              onSelected: (value) async {
                if (value == 'login') {
                  final logged = await _showLoginDialog(context, controller, server.id);
                  if (logged && context.mounted) {
                    SmartDialog.showToast('登录成功');
                  }
                } else if (value == 'delete') {
                  // 删除前确认（可选）
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('删除服务器'),
                      content: Text('确认删除 "${server.name}" 吗？此操作不会影响服务器本身。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('删除', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await controller.deleteServer(server.id);
                    SmartDialog.showToast('已删除');
                  }
                } else if (value == 'logout') {
                  // 退出登录
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('退出登录'),
                      content: Text('确认退出 "${server.username ?? server.name}" 的登录吗？下次需要重新登录。'),
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
                  if (confirmed == true) {
                    await controller.logout(server.id);
                    SmartDialog.showToast('已退出登录');
                  }
                }
              },
              itemBuilder: (_) => [
                if (!hasToken)
                  const PopupMenuItem(value: 'login', child: Text('登录')),
                // 已登录时显示退出登录
                if (hasToken)
                  const PopupMenuItem(
                    value: 'logout',
                    child: Text('退出登录', style: TextStyle(color: Colors.orange)),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
        onTap: () {
          if (!hasToken) {
            _showLoginDialog(context, controller, server.id);
            return;
          }
          Get.toNamed(AppPages.jellyfinMain, arguments: {'serverId': server.id});
        },
      ),
    );
  }

  // ----- 添加对话框 -----
  void _showAddDialog(BuildContext context, JellyfinServerController controller) {
    final theme = Theme.of(context);
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    showDialog(  // 使用 showDialog 替代 Get.dialog
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: theme.colorScheme.surface,
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('添加 Jellyfin 服务器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '名称 *', hintText: '例如：我的NAS'),
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(labelText: '地址 *', hintText: 'http://192.168.1.100:8096'),
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('取消', style: TextStyle(color: theme.colorScheme.outline)),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      final url = urlCtrl.text.trim();
                      if (name.isEmpty || url.isEmpty) {
                        SmartDialog.showToast('请填写完整信息');
                        return;
                      }
                      Navigator.pop(dialogContext);
                      controller.addServer(name, url);
                      SmartDialog.showToast('添加成功');
                    },
                    child: Text(
                      '确定',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- 登录对话框 -----
  Future<bool> _showLoginDialog(
    BuildContext context,
    JellyfinServerController controller,
    String serverId,
  ) async {
    final theme = Theme.of(context);
    final api = JellyfinApiService();
    final userCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();
    bool obscure = true;
    String error = '';

    return await showDialog<bool>(  // 使用 showDialog 替代 Get.dialog
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: theme.colorScheme.surface,
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('登录 Jellyfin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 20),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: '用户名'),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pwdCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: '密码',
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(error, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text('取消', style: TextStyle(color: theme.colorScheme.outline)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        final username = userCtrl.text.trim();
                        final password = pwdCtrl.text;
                        if (username.isEmpty || password.isEmpty) {
                          setState(() => error = '请输入用户名和密码');
                          return;
                        }
                        final server = controller.servers.firstWhere((s) => s.id == serverId);
                        try {
                          final result = await api.authenticateByName(
                            baseUrl: server.baseUrl,
                            username: username,
                            password: password,
                          );
                          final token = result['AccessToken'] as String;
                          final userId = (result['User'] as Map<String, dynamic>)['Id'] as String;
                          final userName = (result['User'] as Map<String, dynamic>)['Name'] as String;
                          await controller.saveToken(serverId, token);
                          await controller.updateServerCredentials(serverId, userId, userName);
                          if (context.mounted) Navigator.pop(dialogContext, true);
                        } catch (e) {
                          setState(() => error = '登录失败: $e');
                        }
                      },
                      child: const Text('登录'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ) == true;
  }
}