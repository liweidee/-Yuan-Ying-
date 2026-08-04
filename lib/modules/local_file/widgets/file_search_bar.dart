import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/local_file/controllers/local_file_controller.dart';
import 'package:yuanying/modules/local_file/models/file_sort_type.dart';

class FileSearchBar extends StatelessWidget {
  final LocalFileController controller;

  const FileSearchBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withOpacity(0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 搜索框
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                onChanged: controller.updateSearch,
                textAlignVertical: TextAlignVertical.center,  // ← 关键修复
                decoration: InputDecoration(
                  hintText: '搜索文件或文件夹...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                  ),
                  prefixIcon: Icon(Icons.search, size: 18, color: colorScheme.outline),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 排序按钮
          PopupMenuButton<FileSortType>(
            onSelected: controller.setSortBy,
            icon: Icon(Icons.sort, size: 20, color: colorScheme.outline),
            itemBuilder: (context) => FileSortType.values.map((type) {
              return PopupMenuItem(
                value: type,
                child: Row(
                  children: [
                    Obx(() => Icon(
                      controller.sortBy.value == type
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 16,
                      color: controller.sortBy.value == type
                          ? colorScheme.primary
                          : colorScheme.outline,
                    )),
                    const SizedBox(width: 8),
                    Text(type.label, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              );
            }).toList(),
          ),

          // 排序方向
          Obx(() => IconButton(
            icon: Icon(
              controller.sortOrder.value == SortOrder.ascending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 18,
              color: colorScheme.outline,
            ),
            onPressed: controller.toggleSortOrder,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          )),

          // 视图切换
          Obx(() => IconButton(
            icon: Icon(
              controller.viewMode.value == ViewMode.list
                  ? Icons.grid_view
                  : Icons.view_list,
              size: 20,
              color: colorScheme.outline,
            ),
            onPressed: controller.toggleViewMode,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          )),

          // 文件夹模式
          Obx(() => IconButton(
            icon: Icon(
              controller.isFolderMode.value
                  ? Icons.folder_open
                  : Icons.folder_outlined,
              size: 20,
              color: controller.isFolderMode.value
                  ? colorScheme.primary
                  : colorScheme.outline,
            ),
            onPressed: controller.toggleFolderMode,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          )),
        ],
      ),
    );
  }
}