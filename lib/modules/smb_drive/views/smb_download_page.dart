import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/t4/models/video_detail.dart';

import '../controllers/smb_download_controller.dart';

class SmbDownloadPage extends StatelessWidget {
  const SmbDownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SmbDownloadController>()) {
      Get.put(SmbDownloadController());
    }
    final c = Get.find<SmbDownloadController>();
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      if (c.items.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.download_outlined, size: 64, color: cs.outline),
              const SizedBox(height: 16),
              Text('暂无下载', style: TextStyle(color: cs.outline)),
            ],
          ),
        );
      }
      return Column(
        children: [
          _buildHeader(context, c),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                Style.safeSpace,
                4,
                Style.safeSpace,
                Style.safeSpace,
              ),
              itemCount: c.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _buildItem(context, c, c.items[i]),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildHeader(BuildContext context, SmbDownloadController c) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Text(
            '共 ${c.items.length} 个任务',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _confirmClearAll(context, c),
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('清空全部'),
            style: TextButton.styleFrom(foregroundColor: cs.error),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll(
      BuildContext context, SmbDownloadController c) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空所有下载'),
        content: const Text('将删除所有下载任务和已下载的文件，正在下载的任务也会被取消。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清空', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await c.clearAll();
      SmartDialog.showToast('已清空所有下载');
    }
  }

  Widget _buildItem(BuildContext ctx, SmbDownloadController c,
      SmbDownloadItem item) {
    final cs = Theme.of(ctx).colorScheme;

    final color = switch (item.status) {
      SmbDownloadStatus.completed => const Color(0xFF4CAF50),
      SmbDownloadStatus.failed => cs.error,
      SmbDownloadStatus.cancelled => cs.outline,
      SmbDownloadStatus.downloading => cs.primary,
      SmbDownloadStatus.queued => cs.outline,
    };

    final icon = switch (item.status) {
      SmbDownloadStatus.completed => Icons.check_circle,
      SmbDownloadStatus.failed => Icons.error_outline,
      SmbDownloadStatus.cancelled => Icons.cancel_outlined,
      SmbDownloadStatus.downloading => Icons.downloading,
      SmbDownloadStatus.queued => Icons.schedule,
    };

    final statusText = switch (item.status) {
      SmbDownloadStatus.completed => '已完成',
      SmbDownloadStatus.failed => '失败',
      SmbDownloadStatus.cancelled => '已取消',
      SmbDownloadStatus.downloading =>
        '${(item.progress * 100).toStringAsFixed(0)}%',
      SmbDownloadStatus.queued => '等待中',
    };

    return Card(
      color: cs.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: item.status == SmbDownloadStatus.completed
            ? () => _playDownloaded(ctx, item)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                  ),
                  if (item.status == SmbDownloadStatus.downloading ||
                      item.status == SmbDownloadStatus.queued)
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: cs.outline),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => c.cancel(item.id),
                    )
                  else if (item.status == SmbDownloadStatus.failed)
                    IconButton(
                      icon:
                          Icon(Icons.refresh, size: 18, color: cs.primary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => c.retry(item),
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: cs.outline),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => c.remove(item),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(statusText, style: TextStyle(fontSize: 12, color: color)),
              if (item.status == SmbDownloadStatus.downloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: item.progress,
                  minHeight: 3,
                  color: cs.primary,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ],
              if (item.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(item.error!,
                      style: TextStyle(fontSize: 12, color: cs.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _playDownloaded(BuildContext ctx, SmbDownloadItem item) {
    if (item.filePath == null || !File(item.filePath!).existsSync()) {
      SmartDialog.showToast('文件不存在或已删除');
      return;
    }

    final c = Get.find<SmbDownloadController>();
    final downloaded = c.completedItems;
    if (downloaded.isEmpty) {
      SmartDialog.showToast('没有可播放的本地文件');
      return;
    }

    final episodes = downloaded
        .map((i) =>
            Episode(name: i.name, url: 'file://${i.filePath}'))
        .toList();

    final videoDetail = VideoDetail(
      vodId: 'smb_dl_${item.id.hashCode}',
      vodName: item.name,
      vodPic: '',
      vodContent: '来自 SMB 下载 · 本地播放',
      vodYear: '',
      vodActor: '',
      vodDirector: '',
      vodRemarks: '${downloaded.length} 个本地文件',
      typeName: 'SMB 下载',
      playSources: [
        PlaySource(name: '本地下载', episodes: episodes),
      ],
    );

    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': 'file://${item.filePath}',
        'directTitle': item.name,
        'videoDetail': videoDetail,
        'sourceName': 'SMB 下载',
        'isDirectPushMode': true,
      },
    );
  }
}