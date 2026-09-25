import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/lx_music/controllers/lx_source_controller.dart';
import 'package:yuanying/modules/lx_music/models/lx_script_model.dart';
import 'package:yuanying/modules/lx_music/utils/lx_logger.dart';
import 'package:yuanying/modules/lx_music/views/lx_debug_log_page.dart';

class LxSourceManagePage extends StatefulWidget {
  const LxSourceManagePage({super.key});

  @override
  State<LxSourceManagePage> createState() => _LxSourceManagePageState();
}

class _LxSourceManagePageState extends State<LxSourceManagePage> {
  LxSourceController get _controller => Get.find<LxSourceController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.refreshScripts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Obx(() {
          final count = _controller.scripts.length;
          return Row(
            children: [
              const Text('自定义源', style: TextStyle(fontSize: 18)),
              if (count > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          );
        }),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '调试日志',
            icon: const Icon(Icons.bug_report_outlined, size: 22),
            onPressed: () => Get.to(() => const LxDebugLogPage()),
          ),
          IconButton(
            tooltip: '导入脚本',
            icon: const Icon(Icons.add_rounded, size: 26),
            onPressed: () => _showImportOptions(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(() {
        final scripts = _controller.scripts;
        if (scripts.isEmpty) return _buildEmpty(colorScheme);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 保留「当前激活」条
            if (_controller.isActive.value) ...[
              _buildActiveCard(colorScheme),
              const SizedBox(height: 16),
              Text(
                '已导入的脚本 (${scripts.length})',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],
            // 脚本列表
            ...scripts.map((s) => _buildScriptCard(s, colorScheme)),
          ],
        );
      }),
      floatingActionButton: Obx(() => _controller.isActive.value
          ? FloatingActionButton(
              backgroundColor: colorScheme.error,
              tooltip: '停用当前脚本',
              onPressed: _deactivate,
              child: Icon(Icons.stop_rounded,
                  color: colorScheme.onError, size: 28),
            )
          : const SizedBox.shrink()),
    );
  }

  // ==================== 空态 ====================

  Widget _buildEmpty(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.code_rounded, size: 64, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text('暂无自定义源脚本',
              style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('导入洛雪音乐 JS 脚本以启用在线音源',
              style: TextStyle(color: colorScheme.outline, fontSize: 12)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showImportOptions(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('导入脚本'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 当前激活卡片 ====================

  Widget _buildActiveCard(ColorScheme colorScheme) {
    return Obx(() {
      LxScript? cur;
      for (final s in _controller.scripts) {
        if (s.id == _controller.currentScriptId.value) {
          cur = s;
          break;
        }
      }
      if (cur == null) return const SizedBox.shrink();

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: colorScheme.primary, size: 18),
                const SizedBox(width: 6),
                Text(
                  '当前激活',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              cur.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            if (cur.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                cur.description,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildChip('v${cur.version}', colorScheme),
                if (cur.author.isNotEmpty)
                  _buildChip(cur.author, colorScheme),
              ],
            ),
          ],
        ),
      );
    });
  }

  // ==================== 脚本卡片 ====================

  Widget _buildScriptCard(LxScript script, ColorScheme colorScheme) {
    final isActive = _controller.currentScriptId.value == script.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showScriptDetail(script),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 图标（垂直居中）
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.code_rounded,
                    color: isActive
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // 名称 + 描述 + 版本/作者（保持原样：标签在描述下）
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        script.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (script.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          script.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildChip('v${script.version}', colorScheme),
                          if (script.author.isNotEmpty)
                            _buildChip(script.author, colorScheme),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isActive) ...[
                      Icon(
                        Icons.check_circle_rounded,
                        color: colorScheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                    ],
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: colorScheme.outline,
                        size: 20,
                      ),
                      tooltip: '',
                      onSelected: (value) =>
                          _handleMenuAction(value, script),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'detail',
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('详情'),
                            ],
                          ),
                        ),
                        if (!isActive)
                          const PopupMenuItem(
                            value: 'activate',
                            child: Row(
                              children: [
                                Icon(Icons.play_arrow_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('激活'),
                              ],
                            ),
                          ),
                        if (isActive)
                          const PopupMenuItem(
                            value: 'deactivate',
                            child: Row(
                              children: [
                                Icon(Icons.stop_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('停用'),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('删除',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildChip(String label, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(color: colorScheme.outline, fontSize: 10)),
    );
  }

  // ==================== 菜单操作 ====================

  void _handleMenuAction(String action, LxScript script) {
    switch (action) {
      case 'detail':
        _showScriptDetail(script);
        break;
      case 'activate':
        _activate(script.id);
        break;
      case 'deactivate':
        _deactivate();
        break;
      case 'delete':
        _delete(script);
        break;
    }
  }

  Future<void> _activate(String id) async {
    try {
      SmartDialog.showToast('正在激活脚本...');
      await _controller.activate(id);
    } catch (e) {
      SmartDialog.showToast('激活失败: $e');
    }
  }

  Future<void> _deactivate() async {
    await _controller.deactivate();
    SmartDialog.showToast('已停用');
  }

  Future<void> _delete(LxScript script) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerLow,
          title: const Text('删除脚本'),
          content: Text('确定要删除「${script.name}」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('删除',
                  style: TextStyle(color: colorScheme.error)),
            ),
          ],
        );
      },
    );
    if (confirm == true) {
      await _controller.remove(script.id);
      SmartDialog.showToast('已删除');
    }
  }

  // ==================== 脚本详情弹窗 ====================

  void _showScriptDetail(LxScript script) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = _controller.currentScriptId.value == script.id;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) {
          return SafeArea(
            top: false,
            child: Column(
              children: [
                // 拖拽条
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 头部
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isActive
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.code_rounded,
                          color: isActive
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              script.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (script.description.isNotEmpty)
                              Text(
                                script.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colorScheme.outlineVariant),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(20),
                    children: [
                      _detailRow('版本', script.version, colorScheme),
                      _detailRow('作者', script.author, colorScheme),
                      _detailRow('主页', script.homepage, colorScheme),
                      _detailRow('导入时间', _formatTime(script.importedAt),
                          colorScheme),
                      if (script.sources.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          '支持的音源',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...script.sources.entries.map((entry) {
                          final src = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key.toUpperCase(),
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '操作: ${src.actions.join(", ")}',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '音质: ${src.qualitys.join(", ")}',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                Divider(height: 1, color: colorScheme.outlineVariant),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: isActive
                            ? OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _deactivate();
                                },
                                icon: const Icon(Icons.stop_rounded, size: 18),
                                label: const Text('停用'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colorScheme.error,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _activate(script.id);
                                },
                                icon: const Icon(Icons.play_arrow_rounded,
                                    size: 18),
                                label: const Text('激活'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _delete(script);
                          },
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('删除'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _detailRow(
      String label, String value, ColorScheme colorScheme) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label：',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ==================== 导入弹窗 ====================

  void _showImportOptions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽条
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    '导入脚本',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.folder_open_rounded,
                    color: colorScheme.primary, size: 20),
              ),
              title: const Text('从本地文件导入'),
              subtitle: const Text('选择 .js 文件'),
              onTap: () {
                Navigator.pop(ctx);
                _importFromFile();
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.paste_rounded,
                    color: colorScheme.primary, size: 20),
              ),
              title: const Text('粘贴脚本内容'),
              subtitle: const Text('手动粘贴 JS 代码'),
              onTap: () {
                Navigator.pop(ctx);
                _importFromContent();
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.link_rounded,
                    color: colorScheme.primary, size: 20),
              ),
              title: const Text('从远程 URL 导入'),
              subtitle: const Text('输入脚本直链地址'),
              onTap: () {
                Navigator.pop(ctx);
                _importFromUrl();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ==================== 导入动作 ====================

  Future<void> _importFromFile() async {
    try {
      final script = await _controller.importFromFile();
      if (script != null) {
        SmartDialog.showToast('导入成功: ${script.name}');
      }
    } catch (e) {
      SmartDialog.showToast('导入失败: $e');
    }
  }

  Future<void> _importFromContent() async {
    final content = await _showTextInputDialog(
      title: '粘贴脚本内容',
      hint: '请粘贴洛雪音乐 JS 脚本内容...',
      maxLines: null,
    );
    if (content == null || content.trim().isEmpty) return;
    try {
      final script = await _controller.importFromContent(content);
      if (script != null) {
        SmartDialog.showToast('导入成功: ${script.name}');
      }
    } catch (e) {
      SmartDialog.showToast('导入失败: $e');
    }
  }

  Future<void> _importFromUrl() async {
    final url = await _showTextInputDialog(
      title: '从远程 URL 导入',
      hint: '例如：https://example.com/lx-script.js',
      maxLines: 1,
    );
    if (url == null || url.trim().isEmpty) return;
    try {
      SmartDialog.showToast('正在下载脚本...');
      final script = await _controller.importFromUrl(url);
      if (script != null) {
        SmartDialog.showToast('导入成功: ${script.name}');
      }
    } catch (e) {
      SmartDialog.showToast('导入失败: $e');
    }
  }

  Future<String?> _showTextInputDialog({
    required String title,
    required String hint,
    int? maxLines = 1,
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerLow,
          title: Text(title, style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            height: maxLines == null ? 300 : null,
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              expands: maxLines == null,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text('导入',
                  style: TextStyle(color: colorScheme.primary)),
            ),
          ],
        );
      },
    ).then((v) {
      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          controller.dispose();
        } catch (_) {}
      });
      return v;
    });
  }
}