import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/t4/models/video_detail.dart';

import '../controllers/webdav_download_controller.dart';

class WebDavDownloadPage extends StatelessWidget {
  const WebDavDownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<WebDavDownloadController>()) {
      Get.put(WebDavDownloadController());
    }
    final c = Get.find<WebDavDownloadController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
          // ===== 顶部操作栏 =====
          _buildHeader(context, c),
          // ===== 下载列表 =====
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

  // ===== 顶部操作栏：任务数 + 清空全部 =====
  Widget _buildHeader(BuildContext context, WebDavDownloadController c) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Text(
            '共 ${c.items.length} 个任务',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
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
      BuildContext context, WebDavDownloadController c) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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

  // ===== 单个下载项 =====
  Widget _buildItem(BuildContext ctx, WebDavDownloadController c,
      WebDavDownloadItem item) {
    final theme = Theme.of(ctx);
    final cs = theme.colorScheme;

    final color = switch (item.status) {
      WebDavDownloadStatus.completed => const Color(0xFF4CAF50),
      WebDavDownloadStatus.failed => cs.error,
      WebDavDownloadStatus.cancelled => cs.outline,
      WebDavDownloadStatus.downloading => cs.primary,
      WebDavDownloadStatus.queued => cs.outline,
    };

    final icon = switch (item.status) {
      WebDavDownloadStatus.completed => Icons.check_circle,
      WebDavDownloadStatus.failed => Icons.error_outline,
      WebDavDownloadStatus.cancelled => Icons.cancel_outlined,
      WebDavDownloadStatus.downloading => Icons.downloading,
      WebDavDownloadStatus.queued => Icons.schedule,
    };

    final statusText = switch (item.status) {
      WebDavDownloadStatus.completed => '已完成',
      WebDavDownloadStatus.failed => '失败',
      WebDavDownloadStatus.cancelled => '已取消',
      WebDavDownloadStatus.downloading =>
        '${(item.progress * 100).toStringAsFixed(0)}%',
      WebDavDownloadStatus.queued => '等待中',
    };

    return Card(
      color: cs.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: item.status == WebDavDownloadStatus.completed
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
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (item.status == WebDavDownloadStatus.downloading ||
                      item.status == WebDavDownloadStatus.queued)
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: cs.outline),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => c.cancel(item.id),
                    )
                  else if (item.status == WebDavDownloadStatus.failed)
                    IconButton(
                      icon: Icon(Icons.refresh, size: 18, color: cs.primary),
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
              Text(
                statusText,
                style: TextStyle(fontSize: 12, color: color),
              ),
              if (item.status == WebDavDownloadStatus.downloading) ...[
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
                  child: Text(
                    item.error!,
                    style: TextStyle(fontSize: 12, color: cs.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== 点击已下载项 → 跳转详情页并播放 =====
  void _playDownloaded(BuildContext ctx, WebDavDownloadItem item) {
    if (item.filePath == null || !File(item.filePath!).existsSync()) {
      SmartDialog.showToast('文件不存在或已删除');
      return;
    }

    final c = Get.find<WebDavDownloadController>();

    // ---- 1. 收集所有已下载成功的本地文件 ----
    final downloaded = c.completedItems;
    if (downloaded.isEmpty) {
      SmartDialog.showToast('没有可播放的本地文件');
      return;
    }

    // ---- 2. 构造 Episode 列表 ----
    final episodes = downloaded
        .map((i) => Episode(
              name: i.name,
              url: 'file://${i.filePath}',
            ))
        .toList();

    // ---- 3. 当前点击项的 URL ----
    final currentUrl = 'file://${item.filePath}';

    // ---- 4. 构造 VideoDetail（结构参考 Emby）----
    final videoDetail = VideoDetail(
      vodId: 'webdav_dl_${item.id.hashCode}',
      vodName: item.name,
      vodPic: '',
      vodContent: '来自 WebDAV 下载 · 本地播放',
      vodYear: '',
      vodActor: '',
      vodDirector: '',
      vodRemarks: '${downloaded.length} 个本地文件',
      typeName: 'WebDAV 下载',
      playSources: [
        PlaySource(
          name: '本地下载',
          episodes: episodes,
        ),
      ],
    );

    // ---- 5. 跳转详情页 ----
    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': currentUrl,
        'directTitle': item.name,
        'videoDetail': videoDetail,
        'sourceName': 'WebDAV 下载',
        'isDirectPushMode': true,
      },
    );
  }
}