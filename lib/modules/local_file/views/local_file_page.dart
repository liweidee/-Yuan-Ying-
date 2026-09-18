import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/flutter/refresh_indicator.dart' as custom;
import 'package:yuanying/modules/local_file/controllers/local_file_controller.dart';
import 'package:yuanying/modules/local_file/models/file_sort_type.dart';
import 'package:yuanying/modules/local_file/models/video_file.dart';
import 'package:yuanying/modules/local_file/widgets/breadcrumb_bar.dart';
import 'package:yuanying/modules/local_file/widgets/file_empty_state.dart';
import 'package:yuanying/modules/local_file/widgets/file_grid_item.dart';
import 'package:yuanying/modules/local_file/widgets/file_list_item.dart';
import 'package:yuanying/modules/local_file/widgets/file_search_bar.dart';
import 'package:yuanying/modules/local_file/widgets/folder_grid_item.dart';
import 'package:yuanying/modules/local_file/widgets/folder_item.dart';
import 'package:yuanying/modules/local_file/widgets/path_management_dialog.dart';
import 'package:yuanying/modules/local_file/widgets/statistics_bar.dart';
import 'package:yuanying/utils/platform_utils.dart';

class LocalFilePage extends StatefulWidget {
  const LocalFilePage({super.key});

  @override
  State<LocalFilePage> createState() => _LocalFilePageState();
}

class _LocalFilePageState extends State<LocalFilePage>
    with AutomaticKeepAliveClientMixin {
  late final LocalFileController controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    controller = Get.put(LocalFileController());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth > 800;
    final crossAxisCount = isWide ? 6 : 2;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: _buildAppBar(context, colorScheme),
      body: Obx(() {
        if (controller.isLoading.value && controller.videoFiles.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }

        // 空状态：iOS 显示引导，其他平台显示添加路径
        if (controller.videoFiles.isEmpty && controller.scanPaths.isEmpty) {
          if (Platform.isIOS) {
            return _buildIOSEmptyState(context);
          }
          return FileEmptyState(
            onAddPath: () => _showPathManagementDialog(context),
          );
        }

        return custom.RefreshIndicator(
          onRefresh: () async {
            if (Platform.isIOS) {
              await controller.refreshImportedFolder();
              return;
            }
            if (controller.scanPaths.isNotEmpty) {
              final first = controller.scanPaths.firstWhere(
                (p) => p.enabled,
                orElse: () => controller.scanPaths.first,
              );
              controller.currentFolderPath.value = first.path;
              await controller.scanDirectory(first.path);
            }
          },
          child: Column(
            children: [
              StatisticsBar(
                videoCount: controller.totalVideoCount,
                totalSize: controller.totalSizeFormatted,
                pathCount: Platform.isIOS ? 1 : controller.enabledPathCount,
                lastScanTime: controller.getLastScanTime(),
              ),
              if (controller.isFolderMode.value)
                BreadcrumbBar(controller: controller),
              FileSearchBar(controller: controller),
              Expanded(
                child: _buildContent(context, crossAxisCount),
              ),
            ],
          ),
        );
      }),
    );
  }

  AppBar _buildAppBar(BuildContext context, ColorScheme colorScheme) {
    return AppBar(
      title: const Text('本地文件'),
      centerTitle: false,
      elevation: 0,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      actions: [
        // 刷新按钮
        Obx(() => IconButton(
          icon: controller.isScanning.value
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 20),
          onPressed: controller.isScanning.value
              ? null
              : () async {
                  if (Platform.isIOS) {
                    await controller.refreshImportedFolder();
                    return;
                  }
                  if (controller.scanPaths.isNotEmpty) {
                    final first = controller.scanPaths.firstWhere(
                      (p) => p.enabled,
                      orElse: () => controller.scanPaths.first,
                    );
                    controller.currentFolderPath.value = first.path;
                    await controller.scanDirectory(first.path);
                  }
                },
          splashRadius: 20,
        )),

        // 非 iOS：路径管理
        if (!Platform.isIOS)
          IconButton(
            icon: const Icon(Icons.folder_open, size: 20),
            onPressed: () => _showPathManagementDialog(context),
            splashRadius: 20,
          ),

        // iOS：批量清空
        if (Platform.isIOS)
          Obx(() => IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            tooltip: '清空已导入',
            onPressed: controller.videoFiles.isEmpty
                ? null
                : () => _confirmClearAll(context),
            splashRadius: 20,
          )),

        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildContent(BuildContext context, int crossAxisCount) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Obx(() {
      final isFolderMode = controller.isFolderMode.value;

      if (isFolderMode) {
        final mixedList = controller.mixedList;
        if (mixedList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.folder_open,
                  size: 48,
                  color: colorScheme.outline.withOpacity(0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  '此目录没有视频文件',
                  style: TextStyle(fontSize: 14, color: colorScheme.outline),
                ),
              ],
            ),
          );
        }

        if (controller.viewMode.value == ViewMode.list) {
          return ListView.builder(
            padding: const EdgeInsets.only(
              left: 12,
              right: 12,
              top: 8,
              bottom: 100,
            ),
            itemCount: mixedList.length,
            itemBuilder: (context, index) {
              final item = mixedList[index];
              if (item is FolderItemData) {
                return FolderItem(
                  name: item.name,
                  videoCount: 0,
                  totalSize: 0,
                  onTap: () => controller.enterFolder(item.path),
                );
              } else if (item is VideoFile) {
                return FileListItem(
                  file: item,
                  onTap: () => controller.playVideo(item),
                  onDelete: Platform.isIOS
                      ? () => _confirmDelete(context, item)
                      : null,
                );
              }
              return const SizedBox.shrink();
            },
          );
        } else {
          return GridView.builder(
            padding: const EdgeInsets.only(
              left: 12,
              right: 12,
              top: 8,
              bottom: 100,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.1,
            ),
            itemCount: mixedList.length,
            itemBuilder: (context, index) {
              final item = mixedList[index];
              if (item is FolderItemData) {
                return FolderGridItem(
                  name: item.name,
                  onTap: () => controller.enterFolder(item.path),
                );
              } else if (item is VideoFile) {
                return FileGridItem(
                  file: item,
                  onTap: () => controller.playVideo(item),
                  onDelete: Platform.isIOS
                      ? () => _confirmDelete(context, item)
                      : null,
                );
              }
              return const SizedBox.shrink();
            },
          );
        }
      }

      // 文件模式
      final files = controller.filteredFiles;
      if (files.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 48,
                color: colorScheme.outline.withOpacity(0.5),
              ),
              const SizedBox(height: 12),
              Text(
                '没有找到匹配的文件',
                style: TextStyle(fontSize: 14, color: colorScheme.outline),
              ),
            ],
          ),
        );
      }

      if (controller.viewMode.value == ViewMode.list) {
        return ListView.builder(
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 100,
          ),
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            return FileListItem(
              file: file,
              onTap: () => controller.playVideo(file),
              onDelete: Platform.isIOS
                  ? () => _confirmDelete(context, file)
                  : null,
            );
          },
        );
      }

      return GridView.builder(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 100,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.1,
        ),
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          return FileGridItem(
            file: file,
            onTap: () => controller.playVideo(file),
            onDelete: Platform.isIOS
                ? () => _confirmDelete(context, file)
                : null,
          );
        },
      );
    });
  }

  // ===== iOS 空状态引导 =====
  Widget _buildIOSEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.folder_open_outlined,
                size: 36,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有视频',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'iOS 系统限制，无法直接扫描任意文件夹\n请将视频手动保存到「源影」文件夹',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _buildGuideStep(context, '1', '打开「文件」App'),
            _buildGuideStep(context, '2', '找到「我的 iPhone」→「源影」'),
            _buildGuideStep(context, '3', '把视频拖入或保存到该文件夹'),
            _buildGuideStep(context, '4', '返回源影，下拉刷新即可看到'),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStep(BuildContext context, String num, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  // ===== 单文件删除确认 =====
  Future<void> _confirmDelete(BuildContext context, VideoFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除文件'),
        content: Text('确认删除 "${file.name}" 吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      final success = await controller.deleteVideo(file);
      if (success) {
        SmartDialog.showToast('已删除');
      }
    }
  }

  // ===== 批量清空确认 =====
  Future<void> _confirmClearAll(BuildContext context) async {
    final count = controller.videoFiles.length;
    if (count == 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空已导入视频'),
        content: Text('确认删除全部 $count 个视频文件吗？\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '全部删除',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      final n = await controller.clearAllVideos();
      SmartDialog.showToast('已删除 $n 个文件');
    }
  }

  void _showPathManagementDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const PathManagementDialog());
  }
}