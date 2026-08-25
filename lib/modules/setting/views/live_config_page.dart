// lib/modules/setting/views/live_config_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/models/live/live_config.dart';
import 'package:yuanying/modules/setting/controllers/live_config_controller.dart';

class LiveConfigPage extends StatelessWidget {
  const LiveConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(LiveConfigController());
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('直播配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          IconButton(
            onPressed: () => _showAddDialog(context, controller),
            icon: const Icon(Icons.add, size: 28),
            padding: const EdgeInsets.all(8),
            splashRadius: 20,
          ),
        ],
      ),
      body: Obx(() {
        if (controller.configs.isEmpty) {
          return _buildEmptyState(context, theme, controller);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(Style.safeSpace, Style.safeSpace, Style.safeSpace, Style.safeSpace),
          itemCount: controller.configs.length,
          separatorBuilder: (_, __) => const SizedBox(height: Style.cardSpace),
          itemBuilder: (context, index) {
            final config = controller.configs[index];
            final isCurrent = controller.currentKey.value == config.key;
            return _buildConfigCard(
              context: context,
              theme: theme,
              config: config,
              isCurrent: isCurrent,
              controller: controller,
            );
          },
        );
      }),
    );
  }

  // ----- 空状态 -----
  Widget _buildEmptyState(BuildContext context, ThemeData theme, LiveConfigController controller) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.live_tv_outlined, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('暂无直播配置', style: TextStyle(color: theme.colorScheme.outline)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _showAddDialog(context, controller),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('添加配置'),
          ),
        ],
      ),
    );
  }

  // ----- 配置卡片 -----
  Widget _buildConfigCard({
    required BuildContext context,
    required ThemeData theme,
    required LiveConfig config,
    required bool isCurrent,
    required LiveConfigController controller,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: () {
          controller.switchConfig(config.key);
          SmartDialog.showToast('已切换到 ${config.name}');
        },
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: Style.mdRadius,
            border: Border.all(
              color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.outline.withOpacity(0.15),
              width: isCurrent ? 1.5 : 1,
            ),
            boxShadow: [BoxShadow(color: theme.shadowColor.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isCurrent ? theme.colorScheme.primary.withOpacity(0.1) : theme.colorScheme.primaryContainer.withOpacity(0.2),
                  borderRadius: Style.mdRadius,
                ),
                child: Icon(Icons.live_tv, color: theme.colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        config.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                      ),
                    ),
                    if (config.ua != null || config.epg != null || config.logo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (config.ua != null) _buildTag(theme, 'UA', config.ua!),
                            if (config.epg != null) _buildTag(theme, 'EPG', config.epg!),
                            if (config.logo != null) _buildTag(theme, 'Logo', config.logo!),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (isCurrent) ...[
                Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
              ],
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: theme.colorScheme.outline),
                offset: const Offset(0, 40),
                onSelected: (value) {
                  if (value == 'edit') _showEditDialog(context, controller, config);
                  else if (value == 'copy') _copyConfigLink(context, config.url);
                  else if (value == 'delete') _showDeleteConfirm(context, controller, config);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('编辑')])),
                  const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.copy, size: 18), SizedBox(width: 8), Text('复制地址')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(ThemeData theme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.6)),
      ),
    );
  }

  // ----- 辅助方法 -----
  void _copyConfigLink(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    SmartDialog.showToast('地址已复制到剪贴板');
  }

  // ----- 添加对话框 -----
  void _showAddDialog(BuildContext context, LiveConfigController controller) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final uaController = TextEditingController();
    final epgController = TextEditingController();
    final logoController = TextEditingController();

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
              Text('新增直播配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
              const SizedBox(height: 20),
              _buildTextField(controller: nameController, label: '名称 *', hint: '例如：央视频道', colorScheme: colorScheme),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _buildTextField(controller: urlController, label: '地址 *', hint: '输入直播源地址', colorScheme: colorScheme),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && data!.text!.isNotEmpty) {
                        urlController.text = data.text!.trim();
                      } else {
                        SmartDialog.showToast('剪贴板为空');
                      }
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                      child: Icon(Icons.paste, size: 18, color: colorScheme.onPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildTextField(controller: uaController, label: 'UA（可选）', hint: '自定义 User-Agent', colorScheme: colorScheme),
              const SizedBox(height: 14),
              _buildTextField(controller: epgController, label: 'EPG节目表（可选）', hint: 'EPG接口地址', colorScheme: colorScheme),
              const SizedBox(height: 14),
              _buildTextField(controller: logoController, label: 'Logo图标（可选）', hint: '图标图片地址', colorScheme: colorScheme),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(dialogContext),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('取消', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colorScheme.outline)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () async {
                      final name = nameController.text.trim();
                      final url = urlController.text.trim();
                      if (name.isEmpty) {
                        SmartDialog.showToast('请输入名称');
                        return;
                      }
                      if (url.isEmpty) {
                        SmartDialog.showToast('请输入地址');
                        return;
                      }
                      Navigator.pop(dialogContext);
                      await controller.addConfig(
                        name,
                        url,
                        ua: uaController.text.trim().isEmpty ? null : uaController.text.trim(),
                        epg: epgController.text.trim().isEmpty ? null : epgController.text.trim(),
                        logo: logoController.text.trim().isEmpty ? null : logoController.text.trim(),
                      );
                      SmartDialog.showToast('配置添加成功');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('确定', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.primary)),
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

  // ----- 编辑对话框 -----
  void _showEditDialog(BuildContext context, LiveConfigController controller, LiveConfig config) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nameController = TextEditingController(text: config.name);
    final urlController = TextEditingController(text: config.url);
    final uaController = TextEditingController(text: config.ua ?? '');
    final epgController = TextEditingController(text: config.epg ?? '');
    final logoController = TextEditingController(text: config.logo ?? '');

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
              Text('编辑直播配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
              const SizedBox(height: 20),
              _buildTextField(controller: nameController, label: '名称 *', colorScheme: colorScheme),
              const SizedBox(height: 14),
              _buildTextField(controller: urlController, label: '地址 *', colorScheme: colorScheme),
              const SizedBox(height: 14),
              _buildTextField(controller: uaController, label: 'UA（可选）', colorScheme: colorScheme),
              const SizedBox(height: 14),
              _buildTextField(controller: epgController, label: 'EPG节目表（可选）', colorScheme: colorScheme),
              const SizedBox(height: 14),
              _buildTextField(controller: logoController, label: 'Logo图标（可选）', colorScheme: colorScheme),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(dialogContext),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('取消', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colorScheme.outline)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () async {
                      final name = nameController.text.trim();
                      final url = urlController.text.trim();
                      if (name.isEmpty) {
                        SmartDialog.showToast('请输入名称');
                        return;
                      }
                      if (url.isEmpty) {
                        SmartDialog.showToast('请输入地址');
                        return;
                      }
                      Navigator.pop(dialogContext);
                      await controller.updateConfig(
                        config.key,
                        name,
                        url,
                        ua: uaController.text.trim().isEmpty ? null : uaController.text.trim(),
                        epg: epgController.text.trim().isEmpty ? null : epgController.text.trim(),
                        logo: logoController.text.trim().isEmpty ? null : logoController.text.trim(),
                      );
                      SmartDialog.showToast('更新成功');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('保存', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.primary)),
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

  // ----- 公用输入框 -----
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required ColorScheme colorScheme,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: colorScheme.outline.withOpacity(0.5)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // ----- 删除确认 -----
  void _showDeleteConfirm(BuildContext context, LiveConfigController controller, LiveConfig config) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        title: const Text('删除配置'),
        content: Text('确定要删除 "${config.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await controller.deleteConfig(config.key);
              Navigator.pop(dialogContext);
              SmartDialog.showToast('已删除');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}