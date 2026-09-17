import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import '../controllers/fnos_server_controller.dart';
import '../models/fnos_server_model.dart';

class FnosServerConfigPage extends StatelessWidget {
  const FnosServerConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<FnosServerController>()) {
      Get.put(FnosServerController());
    }
    final controller = Get.find<FnosServerController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          '飞牛影视服务器',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
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
            final hasToken = controller.getToken(server.id) != null;
            return _buildServerCard(
                context, theme, controller, server, hasToken);
          },
        );
      }),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    FnosServerController controller,
  ) {
    final colorScheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns_outlined, size: 64, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text('暂无服务器', style: TextStyle(color: colorScheme.outline)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _showAddDialog(context, controller),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
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
    FnosServerController controller,
    FnosServer server,
    bool hasToken,
  ) {
    final colorScheme = theme.colorScheme;
    return Card(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      elevation: 1,
      child: ListTile(
        leading: Icon(Icons.dns, color: colorScheme.primary),
        title: Text(
          server.name,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          server.baseUrl,
          style: TextStyle(color: colorScheme.outline, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasToken)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '未登录',
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.error,
                  ),
                ),
              ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: colorScheme.outline),
              tooltip: '更多菜单',
              onSelected: (value) async {
                if (value == 'login') {
                  final ok = await _showLoginDialog(
                      context, controller, server.id);
                  if (ok && context.mounted) {
                    SmartDialog.showToast('登录成功');
                  }
                } else if (value == 'delete') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('删除服务器'),
                      content: Text(
                          '确认删除 "${server.name}" 吗？此操作不会影响服务器本身。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('删除',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await controller.deleteServer(server.id);
                    SmartDialog.showToast('已删除');
                  }
                } else if (value == 'logout') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('退出登录'),
                      content: Text(
                          '确认退出 "${server.username ?? server.name}" 的登录吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('退出',
                              style: TextStyle(color: Colors.red)),
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
                if (hasToken)
                  const PopupMenuItem(
                    value: 'logout',
                    child:
                        Text('退出登录', style: TextStyle(color: Colors.orange)),
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
          Get.toNamed(AppPages.fnosMain,
              arguments: {'serverId': server.id});
        },
      ),
    );
  }

  // ----- 添加对话框 -----
  void _showAddDialog(
      BuildContext context, FnosServerController controller) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: colorScheme.surface,
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '添加飞牛服务器',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '名称 *',
                  hintText: '例如：我的 NAS',
                ),
                style: TextStyle(color: colorScheme.onSurface),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: '地址 *',
                  hintText: 'http://192.168.1.100:5666',
                ),
                style: TextStyle(color: colorScheme.onSurface),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('取消',
                        style: TextStyle(color: colorScheme.outline)),
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
                        color: colorScheme.primary,
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
    FnosServerController controller,
    String serverId,
  ) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();
    bool obscure = true;
    String error = '';
    bool loading = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: colorScheme.surface,
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '登录飞牛影视',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: '用户名'),
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pwdCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: '密码',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: TextStyle(
                      color: colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: loading
                          ? null
                          : () => Navigator.pop(dialogContext, false),
                      child: Text('取消',
                          style: TextStyle(color: colorScheme.outline)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
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
                                loading = true;
                                error = '';
                              });
                              try {
                                final ok = await controller.login(
                                  serverId: serverId,
                                  username: username,
                                  password: password,
                                );
                                if (!context.mounted) return;
                                if (ok) {
                                  Navigator.pop(dialogContext, true);
                                } else {
                                  setState(() {
                                    error = '登录失败，请检查账号密码';
                                    loading = false;
                                  });
                                }
                              } catch (e) {
                                setState(() {
                                  error = '登录失败: $e';
                                  loading = false;
                                });
                              }
                            },
                      child: loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('登录'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return result == true;
  }
}