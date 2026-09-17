import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

typedef AlistMenuClickCallback = void Function(AlistMenuItemEntity menu);

enum AlistMenuGroupId { operations, view, sort }

enum AlistMenuId {
  // 操作
  forceRefresh,
  newFolder,
  downloadAll,
  configFileNameLines,
  // 视图
  listView,
  gridView,
  // 排序
  fileName,
  fileType,
  modifyTime,
}

enum AlistViewMode { list, grid }

class AlistMenuAnchorController extends GetxController {
  var hasWritePermission = false.obs;
  var isMenuOpen = false.obs;
  var sortBy = AlistMenuId.fileName.obs;
  var sortByUp = true.obs;
  var viewMode = AlistViewMode.list.obs;

  @override
  void onInit() {
    super.onInit();
    _restoreViewMode();
    _restoreSortSettings();
  }

  void _restoreViewMode() {
    final savedView = StorageManager.getSetting<String>(
      AlistStorageKeys.alistViewMode,
    );
    if (savedView == 'grid') {
      viewMode.value = AlistViewMode.grid;
    } else if (savedView == 'list') {
      viewMode.value = AlistViewMode.list;
    }
  }

  /// 从 Hive 恢复排序设置（按名称匹配，避免枚举顺序变化导致索引错位）
  void _restoreSortSettings() {
    final dynamic saved = StorageManager.getSetting<dynamic>(
      AlistStorageKeys.fileSortWayIndex,
    );

    AlistMenuId? restored;

    if (saved is String && saved.isNotEmpty) {
      const sortables = {
        'fileName': AlistMenuId.fileName,
        'fileType': AlistMenuId.fileType,
        'modifyTime': AlistMenuId.modifyTime,
      };
      restored = sortables[saved];
    } else if (saved is int) {
      // 兼容旧版本
      const oldIndexMap = {
        2: AlistMenuId.fileName,
        3: AlistMenuId.fileType,
        4: AlistMenuId.modifyTime,
      };
      restored = oldIndexMap[saved];
    }

    if (restored != null) {
      sortBy.value = restored;
    }
    sortByUp.value =
        StorageManager.getSetting<bool>(AlistStorageKeys.fileSortWayUp) ?? true;
  }

  /// 更新排序（同时持久化）
  void updateSort(AlistMenuId menuId, bool up) {
    sortBy.value = menuId;
    sortByUp.value = up;
    StorageManager.setSetting(
      AlistStorageKeys.fileSortWayIndex,
      menuId.name,
    );
    StorageManager.setSetting(AlistStorageKeys.fileSortWayUp, up);
  }

  /// 更新视图模式（同时持久化）
  void updateViewMode(AlistViewMode mode) {
    viewMode.value = mode;
    StorageManager.setSetting(
      AlistStorageKeys.alistViewMode,
      mode == AlistViewMode.grid ? 'grid' : 'list',
    );
  }
}

class AlistMenuItemEntity {
  final AlistMenuGroupId menuGroupId;
  final AlistMenuId menuId;
  final String name;
  final bool? isUp;

  AlistMenuItemEntity({
    required this.menuGroupId,
    required this.menuId,
    required this.name,
    this.isUp,
  });
}

/// 全局 menu anchor tag（多层级共用）
const String kAlistGlobalMenuTag = 'alist_global_menu_anchor';

/// 获取（或创建）全局 AlistMenuAnchorController
AlistMenuAnchorController getAlistGlobalMenuController() {
  if (Get.isRegistered<AlistMenuAnchorController>(tag: kAlistGlobalMenuTag)) {
    return Get.find<AlistMenuAnchorController>(tag: kAlistGlobalMenuTag);
  }
  return Get.put(
    AlistMenuAnchorController(),
    tag: kAlistGlobalMenuTag,
    permanent: true,
  );
}

/// 显示文件列表菜单（原生 showMenu，点击外部自动关闭）
Future<void> showAlistFileListMenu({
  required BuildContext context,
  required bool hasWritePermission,
  required AlistMenuId sortBy,
  required bool sortByUp,
  required AlistViewMode viewMode,
  required void Function(AlistMenuItemEntity) onSelected,
}) async {
  const menuWidth = 200.0;

  final RenderBox? button = context.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject() as RenderBox?;
  if (button == null || overlay == null) return;

  final Offset topRight = button.localToGlobal(
    Offset(button.size.width, button.size.height),
    ancestor: overlay,
  );
  final RelativeRect position = RelativeRect.fromLTRB(
    topRight.dx - menuWidth,
    topRight.dy,
    overlay.size.width - topRight.dx,
    0,
  );

  final items = <PopupMenuEntry<AlistMenuItemEntity>>[];

  // ===== 操作组 =====
  items.add(PopupMenuItem(
    value: AlistMenuItemEntity(
      menuGroupId: AlistMenuGroupId.operations,
      menuId: AlistMenuId.forceRefresh,
      name: '刷新',
    ),
    height: 40,
    child: const _MenuRow(icon: Icons.refresh, label: '刷新'),
  ));
  if (hasWritePermission) {
    items.add(PopupMenuItem(
      value: AlistMenuItemEntity(
        menuGroupId: AlistMenuGroupId.operations,
        menuId: AlistMenuId.newFolder,
        name: '新建文件夹',
      ),
      height: 40,
      child: const _MenuRow(
        icon: Icons.create_new_folder,
        label: '新建文件夹',
      ),
    ));
  }
  items.add(PopupMenuItem(
    value: AlistMenuItemEntity(
      menuGroupId: AlistMenuGroupId.operations,
      menuId: AlistMenuId.downloadAll,
      name: '下载本页全部',
    ),
    height: 40,
    child: const _MenuRow(icon: Icons.download, label: '下载本页全部'),
  ));
  items.add(PopupMenuItem(
    value: AlistMenuItemEntity(
      menuGroupId: AlistMenuGroupId.operations,
      menuId: AlistMenuId.configFileNameLines,
      name: '文件名行数',
    ),
    height: 40,
    child: const _MenuRow(icon: Icons.line_weight, label: '文件名行数'),
  ));

  items.add(const PopupMenuDivider(height: 3));

  // ===== 视图组 =====
  items.add(PopupMenuItem(
    value: AlistMenuItemEntity(
      menuGroupId: AlistMenuGroupId.view,
      menuId: AlistMenuId.listView,
      name: '列表视图',
    ),
    height: 40,
    child: _MenuRow(
      icon: Icons.view_list,
      label: '列表视图',
      trailing: viewMode == AlistViewMode.list
          ? const Icon(Icons.check, size: 16, color: Colors.blue)
          : null,
    ),
  ));
  items.add(PopupMenuItem(
    value: AlistMenuItemEntity(
      menuGroupId: AlistMenuGroupId.view,
      menuId: AlistMenuId.gridView,
      name: '表格视图',
    ),
    height: 40,
    child: _MenuRow(
      icon: Icons.grid_view,
      label: '表格视图',
      trailing: viewMode == AlistViewMode.grid
          ? const Icon(Icons.check, size: 16, color: Colors.blue)
          : null,
    ),
  ));

  items.add(const PopupMenuDivider(height: 3));

  // ===== 排序组 =====
  items.add(PopupMenuItem(
    value: AlistMenuItemEntity(
      menuGroupId: AlistMenuGroupId.sort,
      menuId: AlistMenuId.fileName,
      name: '文件名称',
      isUp: sortBy == AlistMenuId.fileName ? !sortByUp : true,
    ),
    height: 40,
    child: _MenuRow(
      icon: Icons.sort_by_alpha,
      label: '文件名称',
      trailing: sortBy == AlistMenuId.fileName
          ? Icon(
              sortByUp ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
            )
          : null,
    ),
  ));
  items.add(PopupMenuItem(
    value: AlistMenuItemEntity(
      menuGroupId: AlistMenuGroupId.sort,
      menuId: AlistMenuId.fileType,
      name: '文件类型',
      isUp: sortBy == AlistMenuId.fileType ? !sortByUp : true,
    ),
    height: 40,
    child: _MenuRow(
      icon: Icons.category,
      label: '文件类型',
      trailing: sortBy == AlistMenuId.fileType
          ? Icon(
              sortByUp ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
            )
          : null,
    ),
  ));
  items.add(PopupMenuItem(
    value: AlistMenuItemEntity(
      menuGroupId: AlistMenuGroupId.sort,
      menuId: AlistMenuId.modifyTime,
      name: '修改时间',
      isUp: sortBy == AlistMenuId.modifyTime ? !sortByUp : true,
    ),
    height: 40,
    child: _MenuRow(
      icon: Icons.schedule,
      label: '修改时间',
      trailing: sortBy == AlistMenuId.modifyTime
          ? Icon(
              sortByUp ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
            )
          : null,
    ),
  ));

  final selected = await showMenu<AlistMenuItemEntity>(
    context: context,
    position: position,
    items: items,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    constraints: const BoxConstraints(minWidth: menuWidth, maxWidth: menuWidth),
  );

  if (selected != null) {
    onSelected(selected);
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;

  const _MenuRow({
    required this.icon,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        if (trailing != null) trailing!,
      ],
    );
  }
}