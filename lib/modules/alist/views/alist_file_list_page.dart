import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/image_viewer/gallery_viewer.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import '../controllers/alist_file_list_controller.dart';
import '../controllers/alist_user_controller.dart';
import '../models/alist_file_item.dart';
import '../services/alist_download_manager.dart';
import '../services/alist_file_utils.dart';
import '../widgets/alist_file_info_dialog.dart';
import '../widgets/alist_file_list_menu_anchor.dart';
import '../widgets/alist_overflow_text.dart';
import '../widgets/alist_scaffold.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import '../controllers/alist_server_controller.dart';

class AlistFileListWrapper extends StatelessWidget {
  const AlistFileListWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments;
    final initialPath = args is Map ? args['path'] as String? : null;
    return _AlistFileListBody(initialPath: initialPath);
  }
}

class _AlistFileListBody extends StatelessWidget {
  final String? initialPath;
  const _AlistFileListBody({this.initialPath});

  /// 是否是"文件 Tab 的根目录"（即来自 AlistMainShell 的入口页）
  bool get _isRootEntry => initialPath == null || initialPath!.isEmpty;

  @override
  Widget build(BuildContext context) {
    final tag = initialPath ?? 'alist_root';
    final controller = Get.put(AlistFileListController(), tag: tag);

    // 初始化逻辑延迟到首帧之后执行（避免 build 期间修改 Rx 值）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (initialPath != null &&
          initialPath!.isNotEmpty &&
          controller.path.value == '/') {
        controller.path.value = initialPath!;
        controller.loadFiles();
      } else if (controller.files.isEmpty && !controller.loading.value) {
        controller.loadFiles();
      }
    });

    final menuAnchorController = getAlistGlobalMenuController();

    return AlistScaffold(
      appbarTitle: AlistOverflowText(text: controller.pageName),
      // ★ 顶部返回按钮：直接返回服务器列表
      //   面包屑已经承担了"逐级返回"的功能，所以顶部按钮语义改为"退出浏览"
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '返回服务器列表',
        onPressed: _backToServerList,
      ),
      appbarActions: [
        Builder(
          builder: (ctx) => IconButton(
            onPressed: () {
              showAlistFileListMenu(
                context: ctx,
                hasWritePermission: controller.hasWritePermission.value,
                sortBy: menuAnchorController.sortBy.value,
                sortByUp: menuAnchorController.sortByUp.value,
                viewMode: menuAnchorController.viewMode.value,
                onSelected: (menu) =>
                    controller.handleMenuClick(menu, ctx, menuAnchorController),
              );
            },
            icon: const Icon(Icons.more_horiz),
          ),
        ),
      ],
      body: Column(
        children: [
          _buildBreadcrumb(context, controller),
          Expanded(
            child: Obx(() {
              if (controller.loading.value && controller.files.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (controller.error.value.isNotEmpty &&
                  controller.files.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(controller.error.value),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => controller.loadFiles(refresh: true),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }

              final viewMode = menuAnchorController.viewMode.value;
              return RefreshIndicator(
                onRefresh: () => controller.loadFiles(refresh: true),
                child: viewMode == AlistViewMode.list
                    ? _buildListView(context, controller)
                    : _buildGridView(context, controller),
              );
            }),
          ),
        ],
      ),
    );
  }

  /// 直接返回到服务器列表页。
  ///
  /// 用 `Get.until` 回退到路由栈内**已有的** [AppPages.alistServerConfig]，
  /// 保留上方所有页面的状态（比如 AlistMainShell 里选中的 Tab）。
  ///
  /// 不用 `Get.offAllNamed`：它会清空整个路由栈，
  /// 导致服务器列表页变成栈底（AppBar 返回按钮消失）。
  void _backToServerList() {
    Get.until((route) {
      final name = route.settings.name;
      return name == AppPages.alistServerConfig || route.isFirst;
    });
  }

  // ==================== 面包屑导航 ====================

  /// 面包屑条：显示当前完整路径，点击任意层级跳转到对应目录
  Widget _buildBreadcrumb(
    BuildContext context,
    AlistFileListController controller,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      final path = controller.path.value;
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();

      final crumbs = <({String label, String target})>[
        (label: '根目录', target: '/'),
      ];
      for (int i = 0; i < segments.length; i++) {
        crumbs.add((
          label: segments[i],
          target: '/' + segments.sublist(0, i + 1).join('/'),
        ));
      }

      final crumbWidgets = <Widget>[];
      for (int i = 0; i < crumbs.length; i++) {
        if (i > 0) {
          crumbWidgets.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.chevron_right,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          ));
        }
        crumbWidgets.add(_buildCrumbItem(
          context,
          controller,
          label: crumbs[i].label,
          target: crumbs[i].target,
          isCurrent: i == crumbs.length - 1,
        ));
      }

      final canGoUp = path != '/' && path.isNotEmpty;

      return Material(
        color: cs.surfaceContainerLow,
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              if (canGoUp)
                IconButton(
                  icon: Icon(
                    Icons.arrow_upward_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                  tooltip: '上一级',
                  onPressed: () {
                    final parent = crumbs[crumbs.length - 2];
                    _navigateTo(controller, parent.target);
                  },
                  splashRadius: 20,
                )
              else
                const SizedBox(width: 8),
              Container(
                width: 1,
                height: 18,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(children: crumbWidgets),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// 单个面包屑项
  Widget _buildCrumbItem(
    BuildContext context,
    AlistFileListController controller, {
    required String label,
    required String target,
    required bool isCurrent,
  }) {
    final cs = Theme.of(context).colorScheme;

    if (isCurrent) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _navigateTo(controller, target),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: cs.primary,
          ),
        ),
      ),
    );
  }

  /// 跳转到指定目录（当前页内替换路径，不 push 新页面）
  void _navigateTo(
    AlistFileListController controller,
    String targetPath,
  ) {
    if (controller.path.value == targetPath) return;
    controller.path.value = targetPath;
    // 不同目录可能对应不同密码，重置以便 loadFiles 重新查
    controller.password.value = '';
    controller.loadFiles();
  }

  // ==================== 列表视图 ====================
  Widget _buildListView(
    BuildContext context,
    AlistFileListController controller,
  ) {
    return SlidableAutoCloseBehavior(
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        itemCount: controller.files.length,
        itemBuilder: (ctx, i) {
          final file = controller.files[i];
          final row = _buildListRow(ctx, controller, file);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: controller.hasWritePermission.value
                  ? Slidable(
                      key: Key(file.path),
                      endActionPane: ActionPane(
                        motion: const DrawerMotion(),
                        extentRatio: 0.25,
                        children: [
                          SlidableAction(
                            onPressed: (_) => controller.deleteFile(file),
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            icon: Icons.delete,
                            label: '删除',
                          ),
                        ],
                      ),
                      child: row,
                    )
                  : row,
            ),
          );
        },
      ),
    );
  }

  Widget _buildListRow(
    BuildContext context,
    AlistFileListController controller,
    AlistFileItem file,
  ) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = _subtitleFor(file);

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: InkWell(
        onTap: () => _onFileTap(context, controller, file),
        onLongPress: () => _showBottomMenu(context, controller, file),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(file.icon, color: cs.primary, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.more_vert,
                  color: cs.onSurfaceVariant,
                  size: 20,
                ),
                onPressed: () => _showBottomMenu(context, controller, file),
                splashRadius: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleFor(AlistFileItem file) {
    final parts = <String>[];
    if (file.sizeDesc != null && file.sizeDesc!.isNotEmpty) {
      parts.add(file.sizeDesc!);
    }
    return parts.join(' · ');
  }

  // ==================== 网格视图 ====================
  Widget _buildGridView(
    BuildContext context,
    AlistFileListController controller,
  ) {
    if (controller.files.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('空文件夹')),
        ],
      );
    }
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        childAspectRatio: 0.82,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: controller.files.length,
      itemBuilder: (ctx, i) {
        final file = controller.files[i];
        return _buildGridItem(ctx, controller, file);
      },
    );
  }

  Widget _buildGridItem(
    BuildContext context,
    AlistFileListController controller,
    AlistFileItem file,
  ) {
    final cs = Theme.of(context).colorScheme;
    final thumbnail = AlistFileUtils.getCompleteThumbnail(file.thumb);
    final showThumbnail = !file.isDir &&
        thumbnail != null &&
        thumbnail.isNotEmpty &&
        file.type == AlistFileType.image;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _onFileTap(context, controller, file),
        onLongPress: () => _showBottomMenu(context, controller, file),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: showThumbnail
                      ? Image.network(
                          thumbnail,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) =>
                              _gridIconArea(cs, file.icon),
                        )
                      : _gridIconArea(cs, file.icon),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                file.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gridIconArea(ColorScheme cs, IconData icon) {
    return Container(
      color: cs.primary.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: Icon(icon, size: 34, color: cs.primary),
    );
  }

  // ==================== 文件点击 ====================
  void _onFileTap(
    BuildContext context,
    AlistFileListController controller,
    AlistFileItem file,
  ) {
    if (!file.isDir) {
      controller.recordViewing(file);
    }

    switch (file.type) {
      case AlistFileType.folder:
        // ★ 仍用 push 进入子目录，但顶部返回按钮已改为回服务器列表
        Get.to(
          () => AlistFileListWrapper(),
          arguments: {'path': file.path},
          preventDuplicates: false,
        );
        break;
      case AlistFileType.video:
      case AlistFileType.audio:
        _playMedia(controller, file);
        break;
      case AlistFileType.image:
        _openGallery(controller, file);
        break;
      default:
        AlistFileInfoDialog.show(
          context,
          name: file.name,
          path: file.path,
          size: file.sizeDesc,
          modified: file.modified,
          provider: file.provider,
          sign: file.sign,
          isDir: file.isDir,
        );
        break;
    }
  }

  /// 播放媒体
  Future<void> _playMedia(
    AlistFileListController controller,
    AlistFileItem file,
  ) async {
    final mediaFiles = controller.files
        .where((f) =>
            !f.isDir &&
            (f.type == AlistFileType.video ||
                f.type == AlistFileType.audio))
        .toList();

    if (mediaFiles.isEmpty) {
      SmartDialog.showToast('当前目录无媒体文件');
      return;
    }

    SmartDialog.showLoading(msg: '正在准备播放...');

    try {
      final episodes = <Episode>[];
      String? currentUrl;
      String? currentEpisodeName;

      for (int i = 0; i < mediaFiles.length; i++) {
        final f = mediaFiles[i];
        final localPath =
            AlistDownloadManager.instance.findLocalPath(f.path);
        final url = localPath ??
            await AlistFileUtils.makeFileLink(f.path, f.sign);
        if (url == null || url.isEmpty) continue;

        final cleanName = _stripExtension(f.name);
        episodes.add(Episode(name: cleanName, url: url));

        if (f.path == file.path) {
          currentUrl = url;
          currentEpisodeName = cleanName;
        }
      }

      if (episodes.isEmpty || currentUrl == null) {
        SmartDialog.dismiss();
        SmartDialog.showToast('无法获取播放链接');
        return;
      }

      final serverCtrl = Get.find<AlistServerController>();
      final server = serverCtrl.currentServer;
      final serverName = server?.name ?? 'AList';

      final coverUrl =
          AlistFileUtils.getCompleteThumbnail(file.thumb) ?? '';

      final isSingleFile = mediaFiles.length == 1;
      final isAudio = file.type == AlistFileType.audio;

      final folderTitle = controller.pageName.trim();
      final effectiveVodName = isSingleFile
          ? _stripExtension(file.name)
          : (folderTitle.isEmpty
              ? _stripExtension(file.name)
              : folderTitle);

      final parentPath = file.path.contains('/')
          ? file.path.substring(0, file.path.lastIndexOf('/'))
          : file.path;
      final effectiveVodId = isSingleFile
          ? 'alist_file_${file.path}'
          : 'alist_dir_$parentPath';

      final effectiveRemarks = isSingleFile
          ? (file.sizeDesc ?? '')
          : '${isAudio ? "音频" : "视频"} · 共 ${episodes.length} 集';

      final videoDetail = VideoDetail(
        vodId: effectiveVodId,
        vodName: effectiveVodName,
        vodPic: coverUrl,
        vodContent: '',
        vodYear: '',
        vodActor: '',
        vodDirector: '',
        vodRemarks: effectiveRemarks,
        typeName: isAudio ? '音频' : '视频',
        playSources: [
          PlaySource(
            name: serverName,
            episodes: episodes,
          ),
        ],
      );

      SmartDialog.dismiss();

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'isPush': true,
          'directUrl': currentUrl,
          'directTitle': currentEpisodeName ?? _stripExtension(file.name),
          'videoDetail': videoDetail,
          'sourceName': serverName,
          'vodPic': coverUrl,
          'vodContent': '',
          'vodYear': '',
          'vodActor': '',
          'vodRemarks': effectiveRemarks,
          'isSeries': !isSingleFile,
          'isDirectPushMode': true,
        },
      );
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('播放失败: $e');
    }
  }

  static String _stripExtension(String name) {
    final idx = name.lastIndexOf('.');
    if (idx <= 0) return name;
    final ext = name.substring(idx + 1).toLowerCase();
    const validExts = {
      'mp4', 'mkv', 'avi', 'webm', 'mov', 'ts', 'm2ts', 'wmv', 'flv',
      'ogv', 'rmvb', 'mpg', 'mpeg', 'vob', '3gp', 'm4v', 'rm',
      'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'opus', 'wma', 'ape',
      'dsf', 'dff', 'aiff', 'alac',
    };
    if (!validExts.contains(ext)) return name;
    return name.substring(0, idx);
  }

  Future<void> _openGallery(
    AlistFileListController controller,
    AlistFileItem file,
  ) async {
    final images =
        controller.files.where((f) => f.type == AlistFileType.image).toList();
    if (images.isEmpty) return;

    SmartDialog.showLoading(msg: '加载中...');
    try {
      final sources = <SourceModel>[];
      for (final img in images) {
        final localPath =
            AlistDownloadManager.instance.findLocalPath(img.path);
        if (localPath != null) {
          sources.add(SourceModel(
            url: localPath,
            sourceType: SourceType.fileImage,
          ));
        } else {
          final url = await AlistFileUtils.makeFileLink(img.path, img.sign);
          if (url != null && url.isNotEmpty) {
            sources.add(SourceModel(url: url));
          }
        }
      }
      SmartDialog.dismiss();
      if (sources.isEmpty) {
        SmartDialog.showToast('无可显示的图片');
        return;
      }
      final index = images.indexWhere((f) => f.path == file.path);
      Get.to(() => GalleryViewer(
            quality: 80,
            sources: sources,
            initIndex: index >= 0 ? index : 0,
          ));
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('打开失败: $e');
    }
  }

  // ==================== 底部菜单 ====================
  void _showBottomMenu(
    BuildContext context,
    AlistFileListController controller,
    AlistFileItem file,
  ) {
    final theme = Theme.of(context);
    final isFav = controller.isFavorite(file);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(file.icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('打开'),
                onTap: () {
                  Navigator.pop(ctx);
                  _onFileTap(context, controller, file);
                },
              ),
              if (!file.isDir)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('复制链接'),
                  onTap: () {
                    Navigator.pop(ctx);
                    AlistFileUtils.copyFileLink(file.path, file.sign);
                  },
                ),
              if (!file.isDir)
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('下载'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AlistDownloadManager.instance.enqueue(
                      name: file.name,
                      remotePath: file.path,
                      sign: file.sign,
                      thumb: file.thumb,
                    );
                    SmartDialog.showToast('已加入下载队列');
                  },
                ),
              ListTile(
                leading: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? theme.colorScheme.primary : null,
                ),
                title: Text(isFav ? '取消收藏' : '收藏'),
                onTap: () {
                  Navigator.pop(ctx);
                  controller.toggleFavorite(file);
                },
              ),
              if (controller.hasWritePermission.value)
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('重命名'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showRenameDialog(controller, file);
                  },
                ),
              if (controller.hasWritePermission.value)
                ListTile(
                  leading: const Icon(Icons.delete),
                  title: const Text('删除'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDelete(controller, file);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('详情'),
                onTap: () {
                  Navigator.pop(ctx);
                  AlistFileInfoDialog.show(
                    context,
                    name: file.name,
                    path: file.path,
                    size: file.sizeDesc,
                    modified: file.modified,
                    provider: file.provider,
                    sign: file.sign,
                    isDir: file.isDir,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameDialog(
    AlistFileListController controller,
    AlistFileItem file,
  ) {
    final tc = TextEditingController(text: file.name);
    final fn = FocusNode();
    var hasContent = file.name.isNotEmpty;
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('重命名'),
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
                      controller.renameFile(file, tc.text.trim());
                    }
                  : null,
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
    AlistFileListController controller,
    AlistFileItem file,
  ) {
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确认删除 "${file.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              controller.deleteFile(file);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}