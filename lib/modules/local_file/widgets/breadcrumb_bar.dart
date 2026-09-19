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
      // 强制读取响应式变量
      final breadcrumbs = controller.breadcrumbs;
      final isAtRoot = controller.isAtRootPath;
      final currentPath = controller.currentFolderPath.value;
      final rootPath = controller.rootPath;

      if (rootPath.isEmpty) {
        return const SizedBox.shrink();
      }

      // 根目录名：iOS 显示"源影"，其他平台显示 scanPath.name
      final rootName = controller.scanPaths.isNotEmpty
          ? controller.scanPaths
              .firstWhere(
                (p) => p.enabled,
                orElse: () => controller.scanPaths.first,
              )
              .name
          : '源影';

      // 即使在根目录，也显示面包屑栏（只有根节点）
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outline.withOpacity(0.06),
              width: 1,
            ),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 根目录
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
                        fontWeight:
                            isAtRoot ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),

              // 面包屑层级
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
                        fontWeight: breadcrumbs[i].path == currentPath
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
            ],
          ),
        ),
      );
    });
  }
}