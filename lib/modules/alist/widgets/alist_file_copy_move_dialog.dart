import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import '../net/alist_dio_utils.dart';
import '../services/alist_download_manager.dart';
import '../services/alist_file_utils.dart';
import 'alist_mkdir_dialog.dart';

class AlistFileCopyMoveDialog extends StatelessWidget {
  final String originalFolder;
  final List<String> names;
  final bool isCopy;

  const AlistFileCopyMoveDialog({
    super.key,
    required this.originalFolder,
    required this.names,
    required this.isCopy,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(
      _CopyMoveController(originalFolder, names, isCopy),
      tag: '${originalFolder}_${isCopy}_${names.join(",")}',
    );
    return _buildUI(context, controller);
  }

  Widget _buildUI(BuildContext context, _CopyMoveController controller) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(isCopy ? '复制到' : '移动到'),
              leading: BackButton(onPressed: () => Get.back()),
              actions: [
                TextButton(
                  onPressed: () => Get.back(),
                  child: const Text('取消'),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Text(
                '当前目录：${controller.currentPath}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Obx(() => controller.loading.value
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: controller.folders.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final f = controller.folders[i];
                        return ListTile(
                          leading: const Icon(Icons.folder),
                          title: Text(f.name),
                          onTap: () => controller.enterFolder(f.name),
                        );
                      },
                    )),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.create_new_folder, size: 18),
                      label: const Text('新建文件夹'),
                      onPressed: () {
                        final tc = TextEditingController();
                        final fn = FocusNode();
                        SmartDialog.show(
                          clickMaskDismiss: false,
                          builder: (ctx) => AlistMkdirDialog(
                            controller: tc,
                            focusNode: fn,
                            onCancel: () => SmartDialog.dismiss(),
                            onConfirm: () {
                              SmartDialog.dismiss();
                              controller.mkdir(tc.text.trim());
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: controller.loading.value
                          ? null
                          : () => controller.doCopyMove(),
                      child: Text(isCopy ? '复制到此' : '移动到此'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyMoveController extends GetxController {
  final String originalFolder;
  final List<String> names;
  final bool isCopy;
  final currentPath = '/'.obs;
  final folders = <_FolderItem>[].obs;
  final loading = false.obs;

  _CopyMoveController(this.originalFolder, this.names, this.isCopy);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    try {
      final resp = await AlistDioUtils.instance.listDir(
        path: currentPath.value,
      );
      folders.value = (resp.content ?? [])
          .where((c) => c.isDir)
          .map((c) => _FolderItem(name: c.name))
          .toList();
    } catch (e) {
      SmartDialog.showToast('加载失败: $e');
    } finally {
      loading.value = false;
    }
  }

  void enterFolder(String name) {
    if (currentPath.value == '/') {
      currentPath.value = '/$name';
    } else {
      currentPath.value = '${currentPath.value}/$name';
    }
    load();
  }

  Future<void> mkdir(String name) async {
    if (name.isEmpty) return;
    final path =
        currentPath.value == '/' ? '/$name' : '${currentPath.value}/$name';
    try {
      await AlistDioUtils.instance.mkdir(path);
      SmartDialog.showToast('创建成功');
      load();
    } catch (e) {
      SmartDialog.showToast('创建失败: $e');
    }
  }

  Future<void> doCopyMove() async {
    if (currentPath.value == originalFolder) {
      SmartDialog.showToast('目标目录与源目录相同');
      return;
    }
    try {
      if (isCopy) {
        await AlistDioUtils.instance.copy(
          srcDir: originalFolder,
          dstDir: currentPath.value,
          names: names,
        );
      } else {
        await AlistDioUtils.instance.move(
          srcDir: originalFolder,
          dstDir: currentPath.value,
          names: names,
        );
      }
      SmartDialog.showToast(isCopy ? '复制完成' : '移动完成');
      Get.back(result: {'result': true});
    } catch (e) {
      SmartDialog.showToast('操作失败: $e');
    }
  }
}

class _FolderItem {
  final String name;
  _FolderItem({required this.name});
}