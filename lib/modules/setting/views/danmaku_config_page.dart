import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/models/danmaku/danmaku_api.dart';
import 'package:yuanying/modules/setting/controllers/danmaku_config_controller.dart';

class DanmakuConfigPage extends StatelessWidget {
  const DanmakuConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(DanmakuConfigController());
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('弹幕API配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
      body: Column(
        children: [
          _buildGlobalSwitch(context, theme, controller),
          const SizedBox(height: Style.cardSpace),
          Expanded(
            child: Obx(() {
              if (controller.apis.isEmpty) {
                return _buildEmptyState(context, theme, controller);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(Style.safeSpace, 0, Style.safeSpace, Style.safeSpace),
                itemCount: controller.apis.length,
                separatorBuilder: (_, __) => const SizedBox(height: Style.cardSpace),
                itemBuilder: (context, index) {
                  final api = controller.apis[index];
                  final isCurrent = controller.currentKey.value == api.key;
                  return _buildApiCard(
                    context: context,
                    theme: theme,
                    api: api,
                    isCurrent: isCurrent,
                    controller: controller,
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  // ----- 全局开关 -----
  Widget _buildGlobalSwitch(BuildContext context, ThemeData theme, DanmakuConfigController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Style.safeSpace, Style.safeSpace, Style.safeSpace, 0),
      child: Material(
        color: Colors.transparent,
        borderRadius: Style.mdRadius,
        child: InkWell(
          borderRadius: Style.mdRadius,
          onTap: () => controller.toggleAutoMatch(!controller.autoMatch.value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: Style.mdRadius,
              border: Border.all(color: theme.colorScheme.outline.withOpacity(0.15)),
              boxShadow: [BoxShadow(color: theme.shadowColor.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
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
                  child: Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('自动匹配弹幕', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('播放视频时自动匹配弹幕（需配置弹幕API）', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                      ),
                    ],
                  ),
                ),
                Obx(() => Switch(
                  value: controller.autoMatch.value,
                  onChanged: (v) => controller.toggleAutoMatch(v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----- 空状态 -----
  Widget _buildEmptyState(BuildContext context, ThemeData theme, DanmakuConfigController controller) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.closed_caption_off_outlined, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('暂无弹幕API', style: TextStyle(color: theme.colorScheme.outline)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _showAddDialog(context, controller),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('添加API'),
          ),
        ],
      ),
    );
  }

  // ----- API卡片 -----
  Widget _buildApiCard({
    required BuildContext context,
    required ThemeData theme,
    required DanmakuApi api,
    required bool isCurrent,
    required DanmakuConfigController controller,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: () {
          controller.switchApi(api.key);
          SmartDialog.showToast('已切换到 ${api.name}');
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
                child: Icon(Icons.api, color: theme.colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      api.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        api.api,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
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
                  if (value == 'edit') _showEditDialog(context, controller, api);
                  else if (value == 'copy') _copyApiLink(context, api.api);
                  else if (value == 'delete') _showDeleteConfirm(context, controller, api);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('编辑')])),
                  const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.copy, size: 18), SizedBox(width: 8), Text('复制链接')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- 辅助方法 -----
  void _copyApiLink(BuildContext context, String api) {
    Clipboard.setData(ClipboardData(text: api));
    SmartDialog.showToast('API链接已复制到剪贴板');
  }

  void _showAddDialog(BuildContext context, DanmakuConfigController controller) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nameController = TextEditingController();
    final apiController = TextEditingController();

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
              Text('新增弹幕API', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: '名称',
                  labelStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
                  hintText: '例如：LogVar弹幕',
                  hintStyle: TextStyle(fontSize: 13, color: colorScheme.outline.withOpacity(0.5)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.primary, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: apiController,
                      style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'API地址',
                        labelStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
                        hintText: '输入弹幕接口地址',
                        hintStyle: TextStyle(fontSize: 13, color: colorScheme.outline.withOpacity(0.5)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.primary, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && data!.text!.isNotEmpty) {
                        apiController.text = data.text!.trim();
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
                      final api = apiController.text.trim();
                      if (name.isEmpty) {
                        SmartDialog.showToast('请输入名称');
                        return;
                      }
                      if (api.isEmpty) {
                        SmartDialog.showToast('请输入API地址');
                        return;
                      }
                      Navigator.pop(dialogContext);
                      await controller.addApi(name, api);
                      SmartDialog.showToast('API添加成功');
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

  void _showEditDialog(BuildContext context, DanmakuConfigController controller, DanmakuApi api) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nameController = TextEditingController(text: api.name);
    final apiController = TextEditingController(text: api.api);

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
              Text('编辑弹幕API', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: '名称',
                  labelStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.primary, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: apiController,
                style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'API地址',
                  labelStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.primary, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
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
                      final apiStr = apiController.text.trim();
                      if (name.isEmpty) {
                        SmartDialog.showToast('请输入名称');
                        return;
                      }
                      if (apiStr.isEmpty) {
                        SmartDialog.showToast('请输入API地址');
                        return;
                      }
                      Navigator.pop(dialogContext);
                      await controller.updateApi(api.key, name, apiStr);
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

  void _showDeleteConfirm(BuildContext context, DanmakuConfigController controller, DanmakuApi api) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        title: const Text('删除API'),
        content: Text('确定要删除 "${api.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await controller.deleteApi(api.key);
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