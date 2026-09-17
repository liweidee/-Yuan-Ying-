import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../controllers/alist_server_controller.dart';
import '../models/alist_favorite.dart';
import '../models/alist_file_item.dart';
import '../models/alist_file_viewing_record.dart';
import '../net/alist_dio_utils.dart';
import '../services/alist_download_manager.dart';
import '../services/alist_file_password_helper.dart';
import '../services/alist_file_utils.dart';
import '../widgets/alist_file_list_menu_anchor.dart';

/// 全局刷新信号（收藏页面监听此值以实时刷新）
final alistFavoritesRefreshTick = 0.obs;

/// 全局刷新信号（最近页面监听此值以实时刷新）
final alistRecentsRefreshTick = 0.obs;

class AlistFileListController extends GetxController {
  final path = '/'.obs;
  final files = <AlistFileItem>[].obs;
  final hasWritePermission = false.obs;
  final readme = RxnString();
  final password = ''.obs;
  final loading = false.obs;
  final error = ''.obs;

  /// 全局菜单控制器（排序/视图全局共享）
  AlistMenuAnchorController get _menu => getAlistGlobalMenuController();

  String get pageName {
    if (path.value == '/' || path.value.isEmpty) return '根目录';
    final idx = path.value.lastIndexOf('/');
    if (idx < 0) return path.value;
    return path.value.substring(idx + 1);
  }

  // ==================== 加载文件列表 ====================

  Future<void> loadFiles({bool refresh = false}) async {
    loading.value = true;
    error.value = '';

    // 查找密码
    if (password.value.isEmpty) {
      try {
        final cached = await AlistFilePasswordHelper.instance
            .findPasswordByPath(path.value);
        if (cached != null) password.value = cached;
      } catch (_) {}
    }

    try {
      final resp = await AlistDioUtils.instance.listDir(
        path: path.value,
        password: password.value,
        refresh: refresh,
      );
      hasWritePermission.value = resp.write;
      readme.value = resp.readme.isEmpty ? null : resp.readme;

      final items = (resp.content ?? [])
          .map((c) => AlistFileUtils.respContentToVO(
                path.value,
                resp.provider,
                c,
              ))
          .toList();
      _sort(items);
      files.value = items;
    } on AlistNetException catch (e) {
      if (e.code == 403) {
        _showPasswordDialog();
      } else {
        error.value = e.message;
        SmartDialog.showToast(e.message);
      }
    } catch (e) {
      error.value = '$e';
      SmartDialog.showToast('加载失败: $e');
    } finally {
      loading.value = false;
    }
  }

  // ==================== 密码对话框 ====================

  Future<void> _showPasswordDialog() async {
    final fn = FocusNode();
    await SmartDialog.show(
      clickMaskDismiss: false,
      backDismiss: false,
      builder: (ctx) => _buildPasswordDialog(fn, ctx),
    );
  }

  Widget _buildPasswordDialog(FocusNode fn, BuildContext ctx) {
    final controller = TextEditingController();
    var remember = true;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('请输入目录密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              focusNode: fn,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isCollapsed: true,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 11, vertical: 12),
              ),
            ),
            Row(
              children: [
                Checkbox(
                  value: remember,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => setState(() => remember = v ?? false),
                ),
                GestureDetector(
                  onTap: () => setState(() => remember = !remember),
                  child: const Text('记住密码？'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final pwd = controller.text;
              if (pwd.isEmpty) {
                SmartDialog.showToast('密码不能为空');
                return;
              }
              SmartDialog.dismiss();
              password.value = pwd;
              if (remember) {
                await AlistFilePasswordHelper.instance
                    .savePassword(path.value, pwd);
              }
              loadFiles(refresh: true);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  // ==================== 排序 ====================

  /// 设置排序（委托全局 controller，全局生效）
  void setSort(AlistMenuId menuId, bool up) {
    if (menuId != AlistMenuId.fileName &&
        menuId != AlistMenuId.fileType &&
        menuId != AlistMenuId.modifyTime) {
      return;
    }
    _menu.updateSort(menuId, up);
    // 当前列表立即重排
    final list = files.toList();
    _sort(list);
    files.value = list;
  }

  void _sort(List<AlistFileItem> list) {
    if (list.isEmpty) return;
    final sortBy = _menu.sortBy.value;
    final sortUp = _menu.sortByUp.value;
    list.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (b.isDir && !a.isDir) return 1;
      int result = 0;
      switch (sortBy) {
        case AlistMenuId.fileName:
          result = AlistFileUtils.naturalCompare(a.name, b.name);
          break;
        case AlistMenuId.fileType:
          result = a.typeInt.compareTo(b.typeInt);
          break;
        case AlistMenuId.modifyTime:
          if (a.modifiedMilliseconds <= 0 && b.modifiedMilliseconds > 0) {
            return 1;
          } else if (b.modifiedMilliseconds <= 0 &&
              a.modifiedMilliseconds > 0) {
            return -1;
          } else {
            result = a.modifiedMilliseconds.compareTo(b.modifiedMilliseconds);
          }
          break;
        default:
          break;
      }
      return sortUp ? result : -result;
    });
  }

  // ==================== 文件操作 ====================

  Future<void> deleteFile(AlistFileItem file) async {
    final dir = file.path.substring(0, file.path.lastIndexOf('/'));
    try {
      await AlistDioUtils.instance.remove(
        dir: dir.isEmpty ? '/' : dir,
        names: [file.name],
      );
      SmartDialog.showToast('删除成功');
      loadFiles(refresh: true);
    } catch (e) {
      SmartDialog.showToast('删除失败: $e');
    }
  }

  Future<void> renameFile(AlistFileItem file, String newName) async {
    if (file.name == newName) return;
    try {
      await AlistDioUtils.instance.rename(
        path: file.path,
        name: newName,
      );
      SmartDialog.showToast('重命名成功');
      loadFiles(refresh: true);
    } catch (e) {
      SmartDialog.showToast('重命名失败: $e');
    }
  }

  Future<void> mkdir(String name) async {
    if (name.isEmpty) return;
    final p = path.value == '/' ? '/$name' : '${path.value}/$name';
    try {
      await AlistDioUtils.instance.mkdir(p);
      SmartDialog.showToast('创建成功');
      loadFiles(refresh: true);
    } catch (e) {
      SmartDialog.showToast('创建失败: $e');
    }
  }

  Future<void> downloadAll() async {
    final downloadable = files.where((f) => !f.isDir).toList();
    if (downloadable.isEmpty) {
      SmartDialog.showToast('没有可下载的文件');
      return;
    }
    for (final f in downloadable) {
      await AlistDownloadManager.instance.enqueue(
        name: f.name,
        remotePath: f.path,
        sign: f.sign,
        thumb: f.thumb,
        ignoreDuplicates: true,
      );
    }
    SmartDialog.showToast('已加入下载队列');
  }

  // ==================== 菜单点击处理 ====================

  void handleMenuClick(
    AlistMenuItemEntity menu,
    BuildContext context,
    AlistMenuAnchorController menuAnchorController,
  ) {
    switch (menu.menuGroupId) {
      case AlistMenuGroupId.operations:
        switch (menu.menuId) {
          case AlistMenuId.forceRefresh:
            loadFiles(refresh: true);
            break;
          case AlistMenuId.newFolder:
            _showMkdirDialog();
            break;
          case AlistMenuId.downloadAll:
            downloadAll();
            break;
          case AlistMenuId.configFileNameLines:
            _showConfigFileNameLinesDialog(context);
            break;
          default:
            break;
        }
        break;

      case AlistMenuGroupId.view:
        if (menu.menuId == AlistMenuId.listView) {
          menuAnchorController.updateViewMode(AlistViewMode.list);
        } else if (menu.menuId == AlistMenuId.gridView) {
          menuAnchorController.updateViewMode(AlistViewMode.grid);
        }
        break;

      case AlistMenuGroupId.sort:
        setSort(menu.menuId, menu.isUp ?? true);
        break;
    }
  }

  // ==================== 文件名行数配置 ====================

  void _showConfigFileNameLinesDialog(BuildContext context) {
    final current =
        StorageManager.getSetting<int>(AlistStorageKeys.fileNameMaxLines) ?? 1;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('文件名行数'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
              value: 1,
              groupValue: current,
              title: const Text('最多一行'),
              onChanged: (v) {
                _setFileNameMaxLines(v!);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<int>(
              value: 2,
              groupValue: current,
              title: const Text('最多两行'),
              onChanged: (v) {
                _setFileNameMaxLines(v!);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<int>(
              value: 999,
              groupValue: current,
              title: const Text('不限制行数'),
              onChanged: (v) {
                _setFileNameMaxLines(v!);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _setFileNameMaxLines(int lines) {
    StorageManager.setSetting(AlistStorageKeys.fileNameMaxLines, lines);
    final list = files.toList();
    files.value = [];
    files.value = list;
  }

  // ==================== 新建文件夹对话框 ====================

  void _showMkdirDialog() {
    final tc = TextEditingController();
    final fn = FocusNode();
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (ctx) => _mkdirDialogWidget(tc, fn),
    );
  }

  Widget _mkdirDialogWidget(TextEditingController tc, FocusNode fn) {
    var hasContent = false;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: tc,
          focusNode: fn,
          autofocus: true,
          onChanged: (v) {
            final hc = v.trim().isNotEmpty;
            if (hasContent != hc) setState(() => hasContent = hc);
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '新文件夹名称',
            isCollapsed: true,
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 11, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: hasContent
                ? () {
                    SmartDialog.dismiss();
                    mkdir(tc.text.trim());
                  }
                : null,
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  // ==================== 收藏 ====================

  bool isFavorite(AlistFileItem file) {
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return false;

    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.favorites,
        ) ??
        [];
    final favorites = raw
        .map((e) => AlistFavorite.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final serverId = server.id;
    final userId = server.username ?? 'guest';
    return favorites.any((f) =>
        f.serverId == serverId &&
        f.userId == userId &&
        f.remotePath == file.path);
  }

  Future<void> toggleFavorite(AlistFileItem file) async {
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return;

    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.favorites,
        ) ??
        [];
    final favorites = raw
        .map((e) => AlistFavorite.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final serverId = server.id;
    final userId = server.username ?? 'guest';

    final idx = favorites.indexWhere((f) =>
        f.serverId == serverId &&
        f.userId == userId &&
        f.remotePath == file.path);

    if (idx != -1) {
      favorites.removeAt(idx);
      SmartDialog.showToast('已取消收藏');
    } else {
      favorites.insert(
        0,
        AlistFavorite(
          id: const Uuid().v4(),
          isDir: file.isDir,
          serverId: serverId,
          userId: userId,
          remotePath: file.path,
          name: file.name,
          path: file.path,
          size: file.size ?? 0,
          sign: file.sign,
          thumb: file.thumb,
          modified: file.modifiedMilliseconds,
          provider: file.provider ?? '',
          createTime: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      SmartDialog.showToast('已收藏');
    }

    await StorageManager.setSetting(
      AlistStorageKeys.favorites,
      favorites.map((e) => e.toJson()).toList(),
    );

    // 通知收藏页面实时刷新
    alistFavoritesRefreshTick.value++;
  }

  // ==================== 工具方法 ====================

  String? findLocalPath(String remotePath) {
    return AlistDownloadManager.instance.findLocalPath(remotePath);
  }

  /// 记录浏览（写入 Hive）
  void recordViewing(AlistFileItem file) {
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return;

    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.fileViewingRecords,
        ) ??
        [];
    final records = raw
        .map((e) =>
            AlistFileViewingRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final serverId = server.id;
    final userId = server.username ?? 'guest';

    // 去重
    records.removeWhere((r) =>
        r.serverId == serverId &&
        r.userId == userId &&
        r.remotePath == file.path);

    // 插入到最前
    records.insert(
      0,
      AlistFileViewingRecord(
        id: const Uuid().v4(),
        serverId: serverId,
        userId: userId,
        remotePath: file.path,
        name: file.name,
        path: file.path,
        size: file.size ?? 0,
        sign: file.sign,
        thumb: file.thumb,
        modified: file.modifiedMilliseconds,
        provider: file.provider ?? '',
        createTime: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // 最多保留 100 条
    if (records.length > 100) {
      records.removeRange(100, records.length);
    }

    StorageManager.setSetting(
      AlistStorageKeys.fileViewingRecords,
      records.map((e) => e.toJson()).toList(),
    );

    // 通知最近页面实时刷新
    alistRecentsRefreshTick.value++;
  }
}