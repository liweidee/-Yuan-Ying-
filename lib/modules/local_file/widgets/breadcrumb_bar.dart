import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/local_file/controllers/local_file_controller.dart';

class BreadcrumbBar extends StatelessWidget {
  final LocalFileController controller;

  const BreadcrumbBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Obx(() {
      final breadcrumbs = controller.breadcrumbs;
      final isAtRoot = controller.isAtRootPath;
      final currentPath = controller.currentFolderPath.value;
      final rootPath = controller.rootPath;

      if (rootPath.isEmpty) {
        return const SizedBox.shrink();
      }

      // 根节点名称：iOS 显示「源影」，其他平台显示 scanPath.name
      final rootName = controller.scanPaths.isNotEmpty
          ? controller.scanPaths
              .firstWhere(
                (p) => p.enabled,
                orElse: () => controller.scanPaths.first,
              )
              .name
          : '源影';

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
            // 返回按钮：仅在子目录时显示；根目录不显示也不占位
            if (!isAtRoot)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                onPressed: () => controller.goToParent(),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 18,
                tooltip: '返回上级',
                color: colorScheme.onSurfaceVariant,
              ),

            // 面包屑（可横向滚动）
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: isAtRoot ? 8 : 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 根节点
                      GestureDetector(
                        onTap: () {
                          if (isAtRoot) return;
                          controller.goToPath(rootPath);
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder,
                              size: 14,
                              color: isAtRoot
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rootName,
                              style: TextStyle(
                                fontSize: 12,
                                color: isAtRoot
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                                fontWeight: isAtRoot
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 子层级
                      if (!isAtRoot)
                        for (int i = 0; i < breadcrumbs.length; i++) ...[
                          const SizedBox(width: 4),
                          Text(
                            ' / ',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.outline.withOpacity(0.4),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              final item = breadcrumbs[i];
                              if (item.path == currentPath) return;
                              controller.goToPath(item.path);
                            },
                            child: Text(
                              breadcrumbs[i].name,
                              style: TextStyle(
                                fontSize: 12,
                                color: breadcrumbs[i].path == currentPath
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                                fontWeight:
                                    breadcrumbs[i].path == currentPath
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}