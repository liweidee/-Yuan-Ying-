import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import '../controllers/alist_server_controller.dart';

class AlistAccountPage extends StatelessWidget {
  const AlistAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AlistServerController>()) {
      Get.put(AlistServerController());
    }
    final ctrl = Get.find<AlistServerController>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('账户管理'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => Get.toNamed(AppPages.alistServerConfig),
            child: const Text('添加'),
          ),
        ],
      ),
      body: Obx(() {
        if (ctrl.servers.isEmpty) {
          return Center(
            child: Text(
              '暂无账户',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          );
        }
        return ListView.separated(
          itemCount: ctrl.servers.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final s = ctrl.servers[i];
            final isCurrent = ctrl.currentServerId.value == s.id;
            return ListTile(
              leading: CircleAvatar(
                child: Text(
                  (s.username?.isNotEmpty ?? false)
                      ? s.username![0].toUpperCase()
                      : 'A',
                ),
              ),
              title: Text(s.name),
              subtitle: Text(s.serverUrl),
              trailing: isCurrent
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              onTap: () {
                if (isCurrent) return;
                ctrl.setDefault(s.id);
                Get.offAllNamed(
                  AppPages.alistMain,
                  arguments: {'serverId': s.id},
                );
              },
            );
          },
        );
      }),
    );
  }
}