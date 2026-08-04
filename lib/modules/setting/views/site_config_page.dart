// lib/modules/setting/views/site_config_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:yuanying/common/widgets/dialog/export_import.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/setting/controllers/site_config_controller.dart';
import 'package:yuanying/t4/models/site.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/utils/platform_utils.dart';

class SiteConfigPage extends StatelessWidget {
  const SiteConfigPage({super.key});

  static Map<String, dynamic>? _pendingConfigPackage;
  static String? _pendingFileName;
  static String? _pendingFilePath;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(SiteConfigController());
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('接口配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 24),
            tooltip: '更多操作',
            onSelected: (value) {
              switch (value) {
                case 'export_clipboard':
                  _exportToClipboard(context, controller);
                  break;
                case 'export_file':
                  _exportToFile(context, controller);
                  break;
                case 'manual_input':
                  _showManualImportDialog(context, controller);
                  break;
                case 'import_clipboard':
                  _importFromClipboard(context, controller);
                  break;
                case 'import_file':
                  _importFromLocalFile(context, controller);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'export_clipboard', child: Row(children: [Icon(Icons.copy, size: 18), SizedBox(width: 8), Text('导出到剪切板')])),
              const PopupMenuItem(value: 'export_file', child: Row(children: [Icon(Icons.save_alt, size: 18), SizedBox(width: 8), Text('导出到本地')])),
              const PopupMenuItem(value: 'manual_input', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('手动输入')])),
              const PopupMenuItem(value: 'import_clipboard', child: Row(children: [Icon(Icons.content_paste, size: 18), SizedBox(width: 8), Text('从剪切板导入')])),
              const PopupMenuItem(value: 'import_file', child: Row(children: [Icon(Icons.folder_open, size: 18), SizedBox(width: 8), Text('从本地文件导入')])),
            ],
          ),
          IconButton(
            onPressed: () => _showAddDialog(context, controller),
            icon: const Icon(Icons.add, size: 28),
            padding: const EdgeInsets.all(8),
            splashRadius: 20,
            tooltip: '',
          ),
        ],
      ),
      body: Obx(() {
        if (controller.sites.isEmpty) {
          return _buildEmptyState(context, theme, controller);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(Style.safeSpace),
          itemCount: controller.sites.length,
          separatorBuilder: (context, index) => const SizedBox(height: Style.cardSpace),
          itemBuilder: (context, index) {
            final site = controller.sites[index];
            final isCurrent = controller.currentSiteKey.value == site.key;
            return _buildSiteCard(
              context: context,
              theme: theme,
              site: site,
              isCurrent: isCurrent,
              controller: controller,
            );
          },
        );
      }),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme, SiteConfigController controller) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.api, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('暂无接口配置', style: TextStyle(color: theme.colorScheme.outline)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _showAddDialog(context, controller),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('添加接口'),
          ),
        ],
      ),
    );
  }

  Widget _buildSiteCard({
    required BuildContext context,
    required ThemeData theme,
    required Site site,
    required bool isCurrent,
    required SiteConfigController controller,
  }) {
    final isLocal = site.isLocalConfig || site.isLocalFile;

    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: () {
          controller.switchSite(site.key);
          SmartDialog.showToast('已切换到 ${site.name}');
        },
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: Style.mdRadius,
            border: Border.all(
              color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.outline.withOpacity(0.15),
              width: isCurrent ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
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
                  child: Icon(
                    site.isLocalFile ? Icons.insert_drive_file : (isLocal ? Icons.folder_open_outlined : Icons.link),
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            site.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                            ),
                          ),
                          if (isLocal) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                site.isLocalFile ? '本地文件' : '本地缓存',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          site.api,
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
                  tooltip: '显示菜单',
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showEditDialog(context, controller, site);
                    } else if (value == 'copy') {
                      _copyApiLink(context, site.api);
                    } else if (value == 'delete') {
                      _showDeleteConfirm(context, controller, site);
                    }
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
      ),
    );
  }

  void _copyApiLink(BuildContext context, String api) {
    Clipboard.setData(ClipboardData(text: api));
    SmartDialog.showToast('接口链接已复制到剪贴板');
  }

  String _generateKey(String name) {
    String key = name.toLowerCase().replaceAll(' ', '_');
    int index = 1;
    final existing = GStorage.getCustomSites().map((s) => s['key']).toList();
    while (existing.contains(key)) {
      key = '${name.toLowerCase().replaceAll(' ', '_')}_$index';
      index++;
    }
    return key;
  }

  Future<void> _pickConfigFile(
    BuildContext context,
    TextEditingController nameController,
    TextEditingController apiController,
  ) async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      if (result == null) return;

      final file = result.xFile;
      final content = await file.readAsString();
      final jsonData = jsonDecode(content);

      if (jsonData is! Map<String, dynamic>) {
        SmartDialog.showToast('配置格式错误：期望对象格式');
        return;
      }
      if (jsonData['sites'] == null || jsonData['sites'] is! List) {
        SmartDialog.showToast('配置格式错误：缺少 sites 字段');
        return;
      }

      _pendingFilePath = file.path;
      _pendingFileName = file.name;
      _pendingConfigPackage = null;

      final baseName = file.name.split('.').first;
      nameController.text = baseName;
      apiController.text = file.path;

      SmartDialog.showToast('已加载本地配置文件');
    } catch (e) {
      SmartDialog.showToast('加载配置失败: $e');
    }
  }

  void _showAddDialog(
    BuildContext context,
    SiteConfigController controller, {
    String? initialName,
    String? initialApi,
  }) {
    final nameController = TextEditingController(text: initialName ?? '');
    final apiController = TextEditingController(text: initialApi ?? '');
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String selectedConfigType = 'tvbox';

    // 根据平台决定选项
    final bool isDesktop = PlatformUtils.isDesktop;

    if (initialApi != null && initialApi.isNotEmpty && File(initialApi).existsSync()) {
      _pendingFilePath = initialApi;
      _pendingConfigPackage = null;
    } else if (initialApi == null) {
      _pendingFilePath = null;
      _pendingConfigPackage = null;
    }

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
                initialApi != null && File(initialApi).existsSync() ? '添加本地文件配置' : '新增接口',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: '线路名称',
                  labelStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
                  hintText: '请输入线路名称',
                  hintStyle: TextStyle(fontSize: 13, color: colorScheme.outline.withOpacity(0.5)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 14),
              // ----- 接口类型下拉选择 -----
              DropdownButtonFormField<String>(
                value: selectedConfigType,
                decoration: InputDecoration(
                  labelText: '接口类型',
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: colorScheme.outline,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                // ===== 下拉菜单样式控制 =====
                dropdownColor: colorScheme.surface,           // 下拉菜单背景色
                menuMaxHeight: 120,                          // 限制下拉菜单高度
                iconSize: 20,                                // 调小下拉图标
                isExpanded: true,                           // 不让下拉菜单撑满宽度
                style: TextStyle(
                  fontSize: 14,                              // 选项文字大小
                  color: colorScheme.onSurface,
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'tvbox',
                    child: Text(
                      'TVBox',
                      style: TextStyle(fontSize: 14),        // 选项文字大小
                    ),
                  ),
                  if (!PlatformUtils.isDesktop)
                    const DropdownMenuItem(
                      value: 'catvod',
                      child: Text(
                        'CatVod (猫影视)',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    selectedConfigType = value;
                  }
                },
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: apiController,
                      readOnly: _pendingFilePath != null,
                      style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: _pendingFilePath != null ? '配置文件路径' : '接口链接',
                        labelStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
                        hintText: _pendingFilePath != null ? '' : '点击右侧文件夹选择配置文件',
                        hintStyle: TextStyle(fontSize: 13, color: colorScheme.outline.withOpacity(0.5)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  if (_pendingFilePath == null) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _pickConfigFile(context, nameController, apiController),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.folder_open_outlined,
                          size: 18,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
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
                      child: Text(
                        '取消',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colorScheme.outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        SmartDialog.showToast('请输入线路名称');
                        return;
                      }

                      if (_pendingFilePath != null) {
                        controller.addLocalFileSite(name, _pendingFilePath!);
                        _pendingFilePath = null;
                        _pendingFileName = null;
                        SmartDialog.showToast('本地文件配置添加成功');
                      } else if (_pendingConfigPackage != null) {
                        final fileName = _pendingFileName ?? (apiController.text.trim().isEmpty ? 'config.json' : apiController.text.trim());
                        controller.addLocalConfig(name, fileName, _pendingConfigPackage!);
                        _pendingConfigPackage = null;
                        _pendingFileName = null;
                        SmartDialog.showToast('本地配置添加成功');
                      } else {
                        final api = apiController.text.trim();
                        if (api.isEmpty) {
                          SmartDialog.showToast('请输入接口链接');
                          return;
                        }
                        controller.addSite(name, api);
                        SmartDialog.showToast('接口添加成功');
                      }

                      Navigator.pop(dialogContext);
                      controller.loadSites();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        '确定',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.primary),
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

  void _showEditDialog(BuildContext context, SiteConfigController controller, Site site) {
    final nameController = TextEditingController(text: site.name);
    final apiController = TextEditingController(text: site.api);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                site.isLocalConfig ? '编辑本地缓存配置' : (site.isLocalFile ? '编辑本地文件配置' : '编辑接口'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: '线路名称',
                  labelStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: apiController,
                enabled: !site.isLocalConfig && !site.isLocalFile,
                style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: site.isLocalFile ? '文件路径' : (site.isLocalConfig ? '文件名' : '接口链接'),
                  labelStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  fillColor: (site.isLocalConfig || site.isLocalFile) ? colorScheme.surfaceContainerHighest.withOpacity(0.3) : null,
                  filled: site.isLocalConfig || site.isLocalFile,
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
                      child: Text(
                        '取消',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colorScheme.outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        SmartDialog.showToast('请输入线路名称');
                        return;
                      }
                      controller.updateSite(site.key, name, apiController.text.trim());
                      Navigator.pop(dialogContext);
                      controller.loadSites();
                      SmartDialog.showToast('配置已更新');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        '保存',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.primary),
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

  void _showDeleteConfirm(BuildContext context, SiteConfigController controller, Site site) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        title: const Text('删除接口'),
        content: Text('确定要删除"${site.name}"吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          TextButton(
            onPressed: () {
              controller.deleteSite(site.key);
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _exportToClipboard(BuildContext context, SiteConfigController controller) {
    final configs = GStorage.getCustomSites();
    Clipboard.setData(ClipboardData(text: jsonEncode(configs)));
    SmartDialog.showToast('已导出到剪切板');
  }

  void _exportToFile(BuildContext context, SiteConfigController controller) {
    showImportExportDialog<List<Map<String, dynamic>>>(
      context,
      title: '导出配置',
      onExport: () => jsonEncode(GStorage.getCustomSites()),
      onImport: (_) {},
      localFileName: () => 'site_config',
      importExtensions: const [],
    );
  }

  void _showManualImportDialog(BuildContext context, SiteConfigController controller) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final TextEditingController textController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: colorScheme.surface,
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('手动输入配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
              const SizedBox(height: 12),
              Text('请粘贴完整的 JSON 配置（包含 sites 和 parses）', style: TextStyle(fontSize: 13, color: colorScheme.outline)),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: textController,
                  maxLines: null,
                  expands: true,
                  style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(12),
                    hintText: '粘贴 JSON 配置...',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final text = textController.text.trim();
                      if (text.isEmpty) {
                        SmartDialog.showToast('请输入配置内容');
                        return;
                      }
                      try {
                        final jsonData = jsonDecode(text);
                        if (jsonData is! Map<String, dynamic>) {
                          SmartDialog.showToast('配置格式错误：期望对象格式');
                          return;
                        }
                        if (jsonData['sites'] == null || jsonData['sites'] is! List) {
                          SmartDialog.showToast('配置格式错误：缺少 sites 字段');
                          return;
                        }
                        Navigator.pop(dialogContext);
                        _showImportConfirmDialog(context, controller, jsonData);
                      } catch (e) {
                        SmartDialog.showToast('解析失败: $e');
                      }
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _importFromClipboard(BuildContext context, SiteConfigController controller) async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData == null || clipboardData.text == null) {
      SmartDialog.showToast('剪切板为空');
      return;
    }
    final text = clipboardData.text!.trim();
    if (text.isEmpty) {
      SmartDialog.showToast('剪切板为空');
      return;
    }
    try {
      final jsonData = jsonDecode(text);
      if (jsonData is! Map<String, dynamic>) {
        SmartDialog.showToast('剪切板内容格式错误：期望对象格式');
        return;
      }
      if (jsonData['sites'] == null || jsonData['sites'] is! List) {
        SmartDialog.showToast('剪切板内容格式错误：缺少 sites 字段');
        return;
      }
      _showImportConfirmDialog(context, controller, jsonData);
    } catch (e) {
      SmartDialog.showToast('解析剪切板内容失败: $e');
    }
  }

  void _showImportConfirmDialog(
    BuildContext context,
    SiteConfigController controller,
    Map<String, dynamic> configPackage,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final nameController = TextEditingController(text: '导入配置_$dateStr');

    final sitesCount = (configPackage['sites'] as List).length;

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
              Text('导入配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
              const SizedBox(height: 16),
              Text('检测到配置包，包含 $sitesCount 个站点', style: TextStyle(fontSize: 14, color: colorScheme.outline)),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: '线路名称',
                  labelStyle: TextStyle(fontSize: 13, color: colorScheme.outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        SmartDialog.showToast('请输入线路名称');
                        return;
                      }
                      Navigator.pop(dialogContext);
                      final fileName = '${name}_${DateTime.now().millisecondsSinceEpoch}.json';
                      controller.addLocalConfig(name, fileName, configPackage);
                      SmartDialog.showToast('配置导入成功');
                    },
                    child: const Text('导入'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _importFromLocalFile(BuildContext context, SiteConfigController controller) async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      if (result == null) return;

      final file = result.xFile;
      final content = await file.readAsString();
      final jsonData = jsonDecode(content);

      if (jsonData is! Map<String, dynamic>) {
        SmartDialog.showToast('配置格式错误：期望对象格式');
        return;
      }
      if (jsonData['sites'] == null || jsonData['sites'] is! List) {
        SmartDialog.showToast('配置格式错误：缺少 sites 字段');
        return;
      }

      final baseName = file.name.split('.').first;
      _showAddDialog(context, controller, initialName: baseName, initialApi: file.path);
    } catch (e) {
      SmartDialog.showToast('加载文件失败: $e');
    }
  }
}