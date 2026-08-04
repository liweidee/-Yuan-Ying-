import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:yuanying/modules/local_file/controllers/local_file_controller.dart';
import 'package:yuanying/modules/local_file/models/scan_path.dart';
import 'package:yuanying/utils/platform_utils.dart';

class PathManagementDialog extends StatefulWidget {
  const PathManagementDialog({super.key});

  @override
  State<PathManagementDialog> createState() => _PathManagementDialogState();
}

class _PathManagementDialogState extends State<PathManagementDialog> {
  late final LocalFileController controller;
  final TextEditingController _pathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller = Get.find<LocalFileController>();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: 500,
          maxWidth: isMobile ? double.infinity : 520,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Row(
                children: [
                  Text(
                    '管理扫描路径',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: colorScheme.outline),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '添加路径后点击扫描即可发现视频文件',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // 路径列表
              Expanded(
                child: Obx(() {
                  if (controller.scanPaths.isEmpty) {
                    return Center(
                      child: Text(
                        '暂无路径，点击下方添加',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: controller.scanPaths.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final path = controller.scanPaths[index];
                      return _buildPathItem(context, path);
                    },
                  );
                }),
              ),

              const SizedBox(height: 16),

              // ===== 底部按钮行 - Wrap 自适应，不使用 Flexible =====
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDirectory,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加路径'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.scanPaths.isEmpty ? null : controller.scanAllPaths,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('扫描全部'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                  // Flexible 已移除，TextButton 直接放置
                  TextButton(
                    onPressed: controller.scanPaths.isEmpty ? null : () {
                      controller.clearAllPaths();
                      Navigator.pop(context);
                    },
                    child: Text(
                      '清空所有',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 底部统计
              Obx(() {
                final total = controller.scanPaths.length;
                final scanned = controller.scanPaths.where((p) => p.lastScanTime != null).length;
                final videos = controller.scanPaths.fold(0, (sum, p) => sum + p.videoCount);
                return Text(
                  '共 $total 个路径  •  已扫描 $scanned 个  •  发现 $videos 个视频',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPathItem(BuildContext context, ScanPath path) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          path.enabled ? Icons.folder : Icons.folder_outlined,
          size: 18,
          color: path.enabled ? colorScheme.primary : colorScheme.outline,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                path.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: path.enabled ? colorScheme.onSurface : colorScheme.outline,
                ),
              ),
              Text(
                path.lastScanTime != null
                    ? '最后扫描: ${_formatTime(path.lastScanTime!)}  →  ${path.videoCount} 个视频'
                    : '未扫描',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            path.enabled ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: path.enabled ? colorScheme.primary : colorScheme.outline,
          ),
          onPressed: () => controller.toggleScanPath(path.id),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16, color: Colors.grey),
          onPressed: () => controller.removeScanPath(path.id),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  Future<void> _pickDirectory() async {
    String? selectedPath;

    if (PlatformUtils.isDesktop) {
      // 使用静态方法，不加 platform
      final result = await FilePicker.getDirectoryPath();
      selectedPath = result;
    } else {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final localController = TextEditingController();
          return AlertDialog(
            title: const Text('输入路径'),
            content: TextField(
              controller: localController,
              decoration: const InputDecoration(
                hintText: '/storage/emulated/0/Movies',
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final text = localController.text.trim();
                  if (text.isNotEmpty) {
                    Navigator.pop(ctx, text);
                  }
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
      selectedPath = result;
    }

    if (selectedPath != null && selectedPath!.isNotEmpty) {
      final dir = Directory(selectedPath!);
      if (await dir.exists()) {
        controller.addScanPath(selectedPath!);
      } else {
        SmartDialog.showToast('目录不存在，请检查路径');
      }
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  }
}