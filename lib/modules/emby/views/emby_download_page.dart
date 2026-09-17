import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/t4/models/video_detail.dart';

import '../controllers/emby_download_controller.dart';
import '../services/emby_api_service.dart';
import '../controllers/emby_server_controller.dart';

class EmbyDownloadPage extends StatelessWidget {
  const EmbyDownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<EmbyDownloadController>()) {
      Get.put(EmbyDownloadController());
    }
    final ctrl = Get.find<EmbyDownloadController>();
    final theme = Theme.of(context);
    final serverController = Get.find<EmbyServerController>();

    return Obx(() {
      if (ctrl.items.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.download_outlined,
                  size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text('暂无下载任务',
                  style: TextStyle(color: theme.colorScheme.outline)),
            ],
          ),
        );
      }

      return Column(
        children: [
          _buildHeader(context, ctrl),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: ctrl.items.length,
              itemBuilder: (context, index) {
                final item = ctrl.items[index];
                final server = serverController.servers.firstWhere(
                  (s) => s.id == item.serverId,
                  orElse: () => serverController.currentServer!,
                );
                final imageUrl = EmbyApiService.primaryImage(
                    server.baseUrl, item.id,
                    maxWidth: 200);
                return Card(
                  color: theme.colorScheme.surface,
                  shape:
                      RoundedRectangleBorder(borderRadius: Style.mdRadius),
                  margin: const EdgeInsets.only(bottom: 8),
                  clipBehavior: Clip.antiAlias, // 让 InkWell 水波纹裁剪到圆角内
                  child: InkWell(
                    // 已完成的任务可点击播放；其他状态不可点
                    onTap: item.status == DownloadStatus.completed
                        ? () => _playDownloaded(context, item)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 60,
                              height: 80,
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: theme.colorScheme.surfaceVariant,
                                  child: Icon(Icons.movie,
                                      color: theme.colorScheme.outline),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.onSurface),
                                ),
                                const SizedBox(height: 4),
                                _buildStatusText(item, theme),
                                if (item.status ==
                                    DownloadStatus.downloading) ...[
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: item.progress,
                                    minHeight: 3,
                                    color: theme.colorScheme.primary,
                                    backgroundColor:
                                        theme.colorScheme.surfaceVariant,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${(item.progress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.outline),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _buildActionButton(item, ctrl, theme),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  /// 顶部小工具条：任务数 + 清空按钮
  Widget _buildHeader(BuildContext context, EmbyDownloadController ctrl) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Text(
            '共 ${ctrl.items.length} 个任务',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _handleClearAll(context, ctrl),
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('清空'),
            style: TextButton.styleFrom(foregroundColor: cs.error),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 播放已下载的本地文件
  // ============================================================

  /// 播放已下载的本地文件
  ///
  /// 下载列表里的文件之间**通常无关联**（用户可能下了不同剧集、不同电影），
  /// 因此播放列表**只构造当前点击的这一个文件**，不拼接其他下载项。
  void _playDownloaded(BuildContext context, DownloadItem item) {
    // ---- 1. 校验文件存在 ----
    if (item.filePath == null || !File(item.filePath!).existsSync()) {
      SmartDialog.showToast('文件不存在或已删除');
      return;
    }

    // ---- 2. 只构造当前文件的播放列表 ----
    final currentUrl = 'file://${item.filePath}';
    final episodes = [
      Episode(name: item.name, url: currentUrl),
    ];

    // ---- 3. 构造 VideoDetail ----
    final videoDetail = VideoDetail(
      vodId: 'emby_download_${item.serverId}_${item.id}',
      vodName: item.name,
      vodPic: '',
      vodContent: '来自 Emby 下载 · 本地播放',
      vodYear: '',
      vodActor: '',
      vodDirector: '',
      vodRemarks: '本地文件',
      typeName: 'Emby 下载',
      playSources: [
        PlaySource(name: '本地下载', episodes: episodes),
      ],
    );

    // ---- 4. 跳转详情页播放 ----
    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': currentUrl,
        'directTitle': item.name,
        'videoDetail': videoDetail,
        'sourceName': 'Emby 下载',
        'isDirectPushMode': true,
      },
    );
  }

  // ============================================================
  // 清空
  // ============================================================

  /// 根据列表状态决定清空流程
  ///
  /// - 无下载中任务 → 单确认框 → clearAllFinished()
  /// - 有下载中任务 → 三选一弹窗 → clearAllFinished() 或 clearAll()
  Future<void> _handleClearAll(
      BuildContext context, EmbyDownloadController ctrl) async {
    if (ctrl.items.isEmpty) {
      SmartDialog.showToast('列表已空');
      return;
    }

    final activeCount = ctrl.items
        .where((i) =>
            i.status == DownloadStatus.downloading ||
            i.status == DownloadStatus.queued)
        .length;

    // ---- 无下载中任务：简单确认 ----
    if (activeCount == 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('清空下载'),
          content: const Text('将删除所有下载记录和文件。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('清空', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ctrl.clearAllFinished();
      }
      return;
    }

    // ---- 有下载中任务：三选一 ----
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空下载'),
        content: Text(
          '有 $activeCount 个任务正在下载。\n\n'
          '· 仅清空已完成：保留正在下载的任务\n'
          '· 取消并清空全部：中断所有下载并删除文件',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'finished'),
            child: const Text('仅清空已完成'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text(
              '取消并清空全部',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (choice == 'finished') {
      await ctrl.clearAllFinished();
    } else if (choice == 'all') {
      await ctrl.clearAll();
    }
  }

  // ============================================================
  // 列表项子组件
  // ============================================================

  Widget _buildStatusText(DownloadItem item, ThemeData theme) {
    switch (item.status) {
      case DownloadStatus.queued:
        return Text('等待中',
            style:
                TextStyle(color: theme.colorScheme.outline, fontSize: 12));
      case DownloadStatus.downloading:
        return Text('下载中',
            style:
                TextStyle(color: theme.colorScheme.primary, fontSize: 12));
      case DownloadStatus.completed:
        final size = item.fileSize / (1024 * 1024);
        return Text('已完成 ${size.toStringAsFixed(1)} MB',
            style: const TextStyle(color: Colors.green, fontSize: 12));
      case DownloadStatus.failed:
        return Text('下载失败',
            style: TextStyle(color: theme.colorScheme.error, fontSize: 12));
    }
  }

  Widget _buildActionButton(
      DownloadItem item, EmbyDownloadController ctrl, ThemeData theme) {
    switch (item.status) {
      case DownloadStatus.downloading:
        return IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => ctrl.cancelDownload(item.id, item.serverId),
          tooltip: '取消',
        );
      case DownloadStatus.completed:
        return IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => ctrl.removeCompleted(item.id, item.serverId),
          tooltip: '删除',
        );
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ctrl.retryDownload(item.id, item.serverId),
          tooltip: '重试',
        );
      case DownloadStatus.queued:
        return IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => ctrl.cancelDownload(item.id, item.serverId),
        );
    }
  }
}