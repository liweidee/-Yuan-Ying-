import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import '../controllers/alist_download_controller.dart';
import '../models/alist_file_item.dart';
import '../services/alist_download_manager.dart';
import '../services/alist_download_task_status.dart';
import '../services/alist_file_utils.dart';
import '../widgets/alist_overflow_text.dart';

class AlistDownloadPage extends StatelessWidget {
  const AlistDownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AlistDownloadController>()) {
      Get.put(AlistDownloadController());
    }
    final ctrl = Get.find<AlistDownloadController>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('下载管理'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: ctrl.onMenuSelected,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'startAll', child: Text('全部开始')),
              PopupMenuItem(value: 'pauseAll', child: Text('全部暂停')),
              PopupMenuItem(value: 'setMax', child: Text('最大同时下载数')),
            ],
          ),
        ],
      ),
      body: Obx(() {
        if (ctrl.downloadList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.download_outlined,
                  size: 64,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无下载记录',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ],
            ),
          );
        }
        return SlidableAutoCloseBehavior(
          child: ListView.separated(
            itemCount: ctrl.downloadList.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final item = ctrl.downloadList[i];
              return _buildItem(ctx, ctrl, item);
            },
          ),
        );
      }),
    );
  }

  Widget _buildItem(
    BuildContext context,
    AlistDownloadController ctrl,
    AlistDownloadItem item,
  ) {
    final theme = Theme.of(context);
    final thumbnail = AlistFileUtils.getCompleteThumbnail(item.thumbnail);
    final icon = AlistFileUtils.getFileIcon(false, item.name);

    return Slidable(
      key: Key(item.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => ctrl.delete(item),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '删除',
          ),
        ],
      ),
      child: ListTile(
        leading: SizedBox(
          width: 40,
          height: 40,
          child: thumbnail != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(icon),
                  ),
                )
              : Icon(icon),
        ),
        title: AlistOverflowText(text: item.name),
        subtitle: Obx(() => AlistOverflowText(text: item.status.value)),
        trailing: _buildTrailing(ctrl, item),
        onTap: () => _onTap(context, ctrl, item),
      ),
    );
  }

  Widget _buildTrailing(AlistDownloadController ctrl, AlistDownloadItem item) {
    final status = item.downloadStatus.value;
    if (status == AlistDownloadTaskStatus.waiting ||
        status == AlistDownloadTaskStatus.downloading ||
        status == AlistDownloadTaskStatus.decompressing) {
      return IconButton(
        onPressed: () => ctrl.pause(item),
        icon: const Icon(Icons.pause),
      );
    }
    if (status == AlistDownloadTaskStatus.finished) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    return IconButton(
      onPressed: () => ctrl.download(item),
      icon: const Icon(Icons.play_arrow),
    );
  }

  void _onTap(
    BuildContext context,
    AlistDownloadController ctrl,
    AlistDownloadItem item,
  ) async {
    if (item.downloadStatus.value != AlistDownloadTaskStatus.finished) {
      if (item.downloadStatus.value == AlistDownloadTaskStatus.paused) {
        ctrl.download(item);
      } else {
        ctrl.pause(item);
      }
      return;
    }
    final fileType = AlistFileUtils.getFileType(false, item.name);
    switch (fileType) {
      case AlistFileType.video:
      case AlistFileType.audio:
        Get.toNamed(
          AppPages.detail,
          arguments: {
            'isPush': true,
            'directUrl': item.savedPath.value,
            'directTitle': item.name,
          },
        );
        break;
      case AlistFileType.image:
        Get.to(() => _LocalImageWrapper(path: item.savedPath.value));
        break;
      default:
        Get.toNamed(
          AppPages.alistFileReader,
          arguments: {
            'name': item.name,
            'path': item.savedPath.value,
            'remotePath': item.remotePath,
            'sign': item.sign,
            'size': item.contentLength,
          },
        );
        break;
    }
  }
}

class _LocalImageWrapper extends StatelessWidget {
  final String path;
  const _LocalImageWrapper({required this.path});

  @override
  Widget build(BuildContext context) {
    // 使用简化的单图查看，直接调 GalleryViewer
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(child: Image.file(File(path), fit: BoxFit.contain)),
    );
  }
}