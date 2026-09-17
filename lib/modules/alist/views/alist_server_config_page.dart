import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import '../controllers/alist_server_controller.dart';
import '../models/alist_server.dart';
import '../services/alist_auth_service.dart';

class AlistServerConfigPage extends StatelessWidget {
  const AlistServerConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AlistServerController>()) {
      Get.put(AlistServerController());
    }
    final controller = Get.find<AlistServerController>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'AList 网盘',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
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
            final hasToken = controller.isLoggedIn(server.id);
            return _buildServerCard(
              context,
              theme,
              controller,
              server,
              hasToken,
            );
          },
        );
      }),
    );
  }

  // ===== 空状态 =====
  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    AlistServerController controller,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_outlined,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无 AList 服务器',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
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

  // ===== 服务器卡片 =====
  Widget _buildServerCard(
    BuildContext context,
    ThemeData theme,
    AlistServerController controller,
    AlistServer server,
    bool hasToken,
  ) {
    return Card(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      elevation: 1,
      child: ListTile(
        leading: Icon(Icons.cloud, color: theme.colorScheme.primary),
        title: Text(
          server.name,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          server.serverUrl,
          style: TextStyle(
            color: theme.colorScheme.outline,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasToken)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '未登录',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: theme.colorScheme.outline),
              onSelected: (value) async {
                if (value == 'login') {
                  final logged =
                      await _showLoginDialog(context, controller, server);
                  if (logged && context.mounted) {
                    SmartDialog.showToast('登录成功');
                  }
                } else if (value == 'logout') {
                  final confirmed = await _confirmLogout(context, server);
                  if (confirmed == true) {
                    await controller.logout(server.id);
                    SmartDialog.showToast('已退出登录');
                  }
                } else if (value == 'delete') {
                  final confirmed = await _confirmDelete(context, server);
                  if (confirmed == true) {
                    await controller.deleteServer(server.id);
                    SmartDialog.showToast('已删除');
                  }
                }
              },
              itemBuilder: (_) => [
                if (!hasToken)
                  const PopupMenuItem(value: 'login', child: Text('登录')),
                if (hasToken)
                  const PopupMenuItem(
                    value: 'logout',
                    child: Text(
                      '退出登录',
                      style: TextStyle(color: Colors.orange),
                    ),
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
            _showLoginDialog(context, controller, server);
            return;
          }
          Get.toNamed(
            AppPages.alistMain,
            arguments: {'serverId': server.id},
          );
        },
      ),
    );
  }

  Future<bool?> _confirmLogout(BuildContext context, AlistServer server) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: Text('确认退出 "${server.username ?? server.name}" 的登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '退出',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, AlistServer server) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确认删除 "${server.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // ===== 添加对话框 =====
  void _showAddDialog(
    BuildContext context,
    AlistServerController controller,
  ) {
    final theme = Theme.of(context);
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    bool ignoreSSL = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: theme.colorScheme.surface,
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '添加 AList 服务器',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '名称 *',
                    hintText: '例如：我的网盘',
                  ),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: '地址 *',
                    hintText: 'http://192.168.1.100:5244/',
                  ),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: ignoreSSL,
                      onChanged: (v) =>
                          setState(() => ignoreSSL = v ?? false),
                    ),
                    GestureDetector(
                      onTap: () =>
                          setState(() => ignoreSSL = !ignoreSSL),
                      child: const Text('忽略 SSL 证书错误'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(
                        '取消',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
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
                        final added = controller.servers.last;
                        controller.updateCredentials(
                          added.id,
                          ignoreSSLError: ignoreSSL,
                        );
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
      ),
    );
  }

  // ===== 登录对话框 =====
  Future<bool> _showLoginDialog(
    BuildContext context,
    AlistServerController controller,
    AlistServer server,
  ) async {
    final theme = Theme.of(context);
    final authService = AlistAuthService();
    final userCtrl = TextEditingController(text: server.username ?? '');
    final pwdCtrl = TextEditingController(text: server.password ?? '');
    bool obscure = true;
    bool ignoreSSL = server.ignoreSSLError;
    String error = '';
    bool loading = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: theme.colorScheme.surface,
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '登录 AList',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  server.serverUrl,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: userCtrl,
                  decoration:
                      const InputDecoration(labelText: '用户名'),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pwdCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: '密码',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => obscure = !obscure),
                    ),
                  ),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: ignoreSSL,
                      onChanged: (v) =>
                          setState(() => ignoreSSL = v ?? false),
                    ),
                    GestureDetector(
                      onTap: () =>
                          setState(() => ignoreSSL = !ignoreSSL),
                      child: const Text('忽略 SSL 证书错误'),
                    ),
                  ],
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: loading
                          ? null
                          : () => Navigator.pop(dialogContext, false),
                      child: Text(
                        '取消',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () async {
                              final username = userCtrl.text.trim();
                              final password = pwdCtrl.text;
                              if (username.isEmpty || password.isEmpty) {
                                setState(() => error = '请输入用户名和密码');
                                return;
                              }
                              setState(() {
                                error = '';
                                loading = true;
                              });

                              try {
                                final token = await authService.login(
                                  serverUrl: server.serverUrl,
                                  username: username,
                                  password: password,
                                  ignoreSSLError: ignoreSSL,
                                );
                                await controller.saveToken(server.id, token);
                                await controller.updateCredentials(
                                  server.id,
                                  username: username,
                                  password: password,
                                  guest: false,
                                  ignoreSSLError: ignoreSSL,
                                );
                                if (context.mounted) {
                                  Navigator.pop(dialogContext, true);
                                }
                              } on AlistLoginException catch (e) {
                                setState(() {
                                  error = e.message;
                                  loading = false;
                                });
                              } catch (e) {
                                setState(() {
                                  error = '登录失败: $e';
                                  loading = false;
                                });
                              }
                            },
                      child: Text(
                        loading ? '登录中...' : '登录',
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
      ),
    );
    return result ?? false;
  }
}