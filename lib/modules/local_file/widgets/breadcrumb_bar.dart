import 'package:flutter/material.dart';
import 'package:yuanying/modules/local_file/controllers/local_file_controller.dart';

class BreadcrumbBar extends StatelessWidget {
  final LocalFileController controller;

  const BreadcrumbBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final breadcrumbs = controller.breadcrumbs;

    if (breadcrumbs.isEmpty && controller.scanPaths.isEmpty) {
      return const SizedBox.shrink();
    }

    final rootName = controller.scanPaths.isNotEmpty
        ? controller.scanPaths.firstWhere(
            (p) => p.enabled,
            orElse: () => controller.scanPaths.first,
          ).name
        : '根目录';

    final isAtRoot = controller.isAtRootPath;

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
                final rootPath = controller.scanPaths.firstWhere(
                  (p) => p.enabled,
                  orElse: () => controller.scanPaths.first,
                ).path;
                controller.goToPath(rootPath);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder,
                    size: 14,
                    color: isAtRoot ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    rootName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isAtRoot ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      fontWeight: isAtRoot ? FontWeight.w600 : FontWeight.normal,
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
                    if (item.path == controller.currentFolderPath.value) return;
                    controller.goToPath(item.path);
                  },
                  child: Text(
                    breadcrumbs[i].name,
                    style: TextStyle(
                      fontSize: 12,
                      color: breadcrumbs[i].path == controller.currentFolderPath.value
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      fontWeight: breadcrumbs[i].path == controller.currentFolderPath.value
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
  }
}