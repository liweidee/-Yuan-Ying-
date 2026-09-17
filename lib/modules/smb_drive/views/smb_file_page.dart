import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/t4/models/video_detail.dart';

import '../controllers/smb_download_controller.dart';
import '../controllers/smb_file_controller.dart';
import '../controllers/smb_server_controller.dart';
import '../models/smb_entry.dart';
import '../services/smb_proxy_server.dart';

class SmbFilePage extends StatelessWidget {
  const SmbFilePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SmbFileController>()) {
      Get.put(SmbFileController());
    }
    final c = Get.find<SmbFileController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        _buildBreadcrumb(context, c),
        Expanded(
          child: Obx(() {
            // 导航 loading：全屏圆圈，不显示旧列表
            if (c.isNavigating.value) {
              return const Center(child: CircularProgressIndicator());
            }
            if (c.error.value.isNotEmpty) {
              return _buildError(context, c);
            }
            if (c.entries.isEmpty) {
              return Center(
                child: Text('此文件夹为空',
                    style: TextStyle(color: cs.outline)),
              );
            }
            return RefreshIndicator(
              onRefresh: c.refresh,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: c.entries.length,
                itemBuilder: (_, i) =>
                    _buildEntryTile(context, c, c.entries[i]),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ===== 面包屑 =====
  Widget _buildBreadcrumb(BuildContext context, SmbFileController c) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Row(
          children: [
            // 返回上级：导航中禁用
            Obx(() => IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回上级',
                  onPressed: c.canGoUp && !c.isNavigating.value
                      ? c.goUp
                      : null,
                )),
            Expanded(
              child: Obx(() {
                final crumbs = c.breadcrumbs;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < crumbs.length; i++) ...[
                        if (i > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4),
                            child: Text('›',
                                style: TextStyle(color: cs.outline)),
                          ),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          // 导航中禁用面包屑点击
                          onTap: (i == crumbs.length - 1 ||
                                  c.isNavigating.value)
                              ? null
                              : () => c.jumpTo(i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            child: Text(
                              crumbs[i],
                              style: TextStyle(
                                fontWeight: i == crumbs.length - 1
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: i == crumbs.length - 1
                                    ? cs.onSurface
                                    : cs.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ),
            // 刷新按钮：导航中禁用
            Obx(() => IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新',
                  onPressed:
                      c.isNavigating.value ? null : c.refresh,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, SmbFileController c) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(c.error.value,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.error)),
            const SizedBox(height: 12),
            FilledButton(onPressed: c.refresh, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  // ===== 列表项 =====
  Widget _buildEntryTile(
      BuildContext context, SmbFileController c, SmbEntry entry) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 共享
    if (entry.isShare) {
      return ListTile(
        leading: Icon(Icons.storage, color: cs.primary),
        title: Text(entry.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => c.openEntry(entry),
      );
    }

    // 目录
    if (entry.isDirectory) {
      return ListTile(
        leading: Icon(Icons.folder, color: cs.primary),
        title: Text(entry.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => c.openEntry(entry),
      );
    }

    // 视频
    if (entry.isVideo) {
      return ListTile(
        leading:
            Icon(Icons.play_circle_outline, color: cs.secondary),
        title: Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: entry.sizeLabel.isEmpty
            ? null
            : Text(entry.sizeLabel,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurfaceVariant)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: '下载',
              onPressed: () {
                if (!Get.isRegistered<SmbDownloadController>()) {
                  Get.put(SmbDownloadController());
                }
                Get.find<SmbDownloadController>().addDownload(entry);
                SmartDialog.showToast('已加入下载队列');
              },
            ),
          ],
        ),
        onTap: () => _playVideo(context, entry),
      );
    }

    // 其他文件
    return ListTile(
      leading:
          Icon(Icons.insert_drive_file_outlined, color: cs.outline),
      title: Text(entry.name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: entry.sizeLabel.isEmpty
          ? null
          : Text(entry.sizeLabel,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurfaceVariant)),
    );
  }

  static String _stripMediaExtension(String name) {
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

  static String _folderNameFromPath(String path) {
    if (path.isEmpty || path == '/') return '';
    var p = path.replaceAll(RegExp(r'/+$'), '');
    final idx = p.lastIndexOf('/');
    return idx >= 0 ? p.substring(idx + 1) : p;
  }

  // ===== 播放：本地 HTTP 代理 → 边下边播 =====
  //
  // 关键设计：
  // - 单文件 / 多文件 分策略（vodName / vodId / vodRemarks / isSeries）
  // - Episode.name 和 directTitle 一致（去扩展名），确保定位正确
  Future<void> _playVideo(BuildContext context, SmbEntry entry) async {
    final serverCtl = Get.find<SmbServerController>();
    final server = serverCtl.current;
    if (server == null) return;

    final fileCtl = Get.find<SmbFileController>();
    final share = fileCtl.currentShare.value;
    if (share.isEmpty) return;

    SmartDialog.show(
      tag: 'smb_proxy_starting',
      maskColor: Colors.black54,
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 14),
            Text(
              '正在启动流式播放...',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );

    try {
      final proxy = await SmbProxyManager.start(server);

      SmartDialog.dismiss(tag: 'smb_proxy_starting', force: true);

      final videoList = fileCtl.entries.where((e) => e.isVideo).toList();
      final episodes = <Episode>[];
      String? currentUrl;
      String? currentEpisodeName;

      for (final v in videoList) {
        final url = proxy.urlFor(share: share, relativePath: v.path);
        final cleanName = _stripMediaExtension(v.name);
        episodes.add(Episode(name: cleanName, url: url));

        if (v.path == entry.path) {
          currentUrl = url;
          currentEpisodeName = cleanName;
        }
      }

      if (episodes.isEmpty || currentUrl == null) {
        SmartDialog.showToast('无法获取播放链接');
        await SmbProxyManager.stopCurrent();
        return;
      }

      // ============================================================
      // 标题 / ID / 副标题：区分单文件与多文件
      // ============================================================
      final isSingleFile = videoList.length == 1;
      final folderName = _folderNameFromPath(fileCtl.currentPath.value);
      final effectiveVodName = isSingleFile
          ? _stripMediaExtension(entry.name)
          : (folderName.isEmpty
              ? _stripMediaExtension(entry.name)
              : folderName);

      final parentPath = entry.path.contains('/')
          ? entry.path.substring(0, entry.path.lastIndexOf('/'))
          : entry.path;
      final effectiveVodId = isSingleFile
          ? 'smb_${server.id}_${entry.path.hashCode}'
          : 'smb_dir_${server.id}_${share}_$parentPath';

      final effectiveRemarks = isSingleFile
          ? (entry.sizeLabel.isEmpty ? '' : entry.sizeLabel)
          : '共 ${episodes.length} 集';

      final videoDetail = VideoDetail(
        vodId: effectiveVodId,
        vodName: effectiveVodName,
        vodPic: '',
        vodContent: '来自 SMB · ${server.name}\n'
            '共享：$share\n'
            '路径：${fileCtl.currentPath.value}',
        vodYear: '',
        vodActor: '',
        vodDirector: '',
        vodRemarks: effectiveRemarks,
        typeName: 'SMB',
        playSources: [
          PlaySource(name: server.name, episodes: episodes),
        ],
      );

      await Get.toNamed(
        AppPages.detail,
        arguments: {
          'isPush': true,
          'directUrl': currentUrl,
          'directTitle': currentEpisodeName ?? _stripMediaExtension(entry.name),
          'videoDetail': videoDetail,
          'sourceName': server.name,
          'vodPic': '',
          'vodContent': '来自 SMB · ${server.name}',
          'vodYear': '',
          'vodActor': '',
          'vodDirector': '',
          'vodRemarks': effectiveRemarks,
          'isSeries': !isSingleFile,
          'isDirectPushMode': true,
        },
      );

      await SmbProxyManager.stopCurrent();
    } catch (e) {
      SmartDialog.dismiss(tag: 'smb_proxy_starting', force: true);
      SmartDialog.showToast('启动流式播放失败: $e');
    }
  }
}