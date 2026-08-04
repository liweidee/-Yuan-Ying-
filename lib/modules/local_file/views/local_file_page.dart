import 'dart:io';

import 'package:flutter/material.dart';
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

        if (controller.videoFiles.isEmpty && controller.scanPaths.isEmpty) {
          return FileEmptyState(onAddPath: () => _showPathManagementDialog(context));
        }

        return custom.RefreshIndicator(
          onRefresh: () async {
            if (controller.scanPaths.isNotEmpty) {
              final first = controller.scanPaths
                  .firstWhere((p) => p.enabled, orElse: () => controller.scanPaths.first);
              controller.currentFolderPath.value = first.path;
              await controller.scanDirectory(first.path);
            }
          },
          child: Column(
            children: [
              StatisticsBar(
                videoCount: controller.totalVideoCount,
                totalSize: controller.totalSizeFormatted,
                pathCount: controller.enabledPathCount,
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
        Obx(() => IconButton(
          icon: controller.isScanning.value
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh, size: 20),
          onPressed: controller.isScanning.value
              ? null
              : () async {
                  if (controller.scanPaths.isNotEmpty) {
                    final first = controller.scanPaths
                        .firstWhere((p) => p.enabled, orElse: () => controller.scanPaths.first);
                    controller.currentFolderPath.value = first.path;
                    await controller.scanDirectory(first.path);
                  }
                },
          splashRadius: 20,
        )),
        IconButton(
          icon: const Icon(Icons.folder_open, size: 20),
          onPressed: () => _showPathManagementDialog(context),
          splashRadius: 20,
        ),
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
                Icon(Icons.folder_open, size: 48, color: colorScheme.outline.withOpacity(0.5)),
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
              Icon(Icons.search_off, size: 48, color: colorScheme.outline.withOpacity(0.5)),
              const SizedBox(height: 12),
              Text('没有找到匹配的文件', style: TextStyle(fontSize: 14, color: colorScheme.outline)),
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
          return FileGridItem(file: file, onTap: () => controller.playVideo(file));
        },
      );
    });
  }

  void _showPathManagementDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const PathManagementDialog());
  }
}