import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/t4/models/video_detail.dart';

import '../controllers/webdav_download_controller.dart';
import '../controllers/webdav_file_controller.dart';
import '../controllers/webdav_server_controller.dart';
import '../models/webdav_entry.dart';
import '../services/webdav_service.dart';

class WebDavFilePage extends StatelessWidget {
  const WebDavFilePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<WebDavFileController>()) {
      Get.put(WebDavFileController());
    }
    final c = Get.find<WebDavFileController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        _buildBreadcrumb(context, c),
        Expanded(
          child: Obx(() {
            // 导航 loading：全屏圆圈
            if (c.isNavigating.value) {
              return const Center(child: CircularProgressIndicator());
            }
            if (c.error.value.isNotEmpty) {
              return _buildError(context, c);
            }
            if (c.entries.isEmpty) {
              return Center(
                child: Text(
                  '此文件夹为空',
                  style: TextStyle(color: cs.outline),
                ),
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
  Widget _buildBreadcrumb(BuildContext context, WebDavFileController c) {
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
                            child: Text(
                              '›',
                              style: TextStyle(color: cs.outline),
                            ),
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
                  onPressed: c.isNavigating.value ? null : c.refresh,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WebDavFileController c) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              c.error.value,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.error),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: c.refresh, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  // ===== 列表项 =====
  Widget _buildEntryTile(
      BuildContext context, WebDavFileController c, WebDavEntry entry) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ---- 文件夹 ----
    if (entry.isDirectory) {
      return ListTile(
        leading: Icon(Icons.folder, color: cs.primary),
        title: Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => c.openDirectory(entry),
      );
    }

    // ---- 视频文件 ----
    if (entry.isVideo) {
      return ListTile(
        leading: Icon(Icons.play_circle_outline, color: cs.secondary),
        title: Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: entry.sizeLabel.isEmpty
            ? null
            : Text(
                entry.sizeLabel,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: '下载',
              onPressed: () {
                if (!Get.isRegistered<WebDavDownloadController>()) {
                  Get.put(WebDavDownloadController());
                }
                Get.find<WebDavDownloadController>().addDownload(entry);
                SmartDialog.showToast('已加入下载队列');
              },
            ),
          ],
        ),
        onTap: () => _playVideo(context, entry),
      );
    }

    // ---- 其他文件 ----
    return ListTile(
      leading: Icon(Icons.insert_drive_file_outlined, color: cs.outline),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: entry.sizeLabel.isEmpty
          ? null
          : Text(
              entry.sizeLabel,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
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

  // ===== 播放视频 =====
  //
  // 关键点：
  // 1. 单文件 / 多文件 分策略（vodName / vodId / vodRemarks / isSeries）
  // 2. Episode.name 和 directTitle 一致（去扩展名），确保定位正确
  // 3. 传入 headers（Basic Auth）供播放器请求 WebDAV 资源
  void _playVideo(BuildContext context, WebDavEntry entry) {
    final serverCtl = Get.find<WebDavServerController>();
    final server = serverCtl.current;
    if (server == null) return;

    final fileCtl = Get.find<WebDavFileController>();

    // ---- 1. 请求头（WebDAV Basic Auth）----
    final headers = WebDavService.instance.buildHeaders(server);

    // ---- 2. 当前目录下所有视频 ----
    final videoList = fileCtl.entries.where((e) => e.isVideo).toList();

    final episodes = <Episode>[];
    String? currentUrl;
    String? currentEpisodeName;

    for (final v in videoList) {
      final url = WebDavService.instance.buildPlayableUrl(server, v.path);
      final cleanName = _stripMediaExtension(v.name);
      episodes.add(Episode(name: cleanName, url: url));

      if (v.path == entry.path) {
        currentUrl = url;
        currentEpisodeName = cleanName;
      }
    }

    if (episodes.isEmpty || currentUrl == null) {
      SmartDialog.showToast('无法获取播放链接');
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
        ? 'webdav_${server.id}_${entry.path.hashCode}'
        : 'webdav_dir_${server.id}_$parentPath';

    final effectiveRemarks = isSingleFile
        ? (entry.sizeLabel.isEmpty ? '' : entry.sizeLabel)
        : '共 ${episodes.length} 集';

    // ---- 构造 VideoDetail ----
    final videoDetail = VideoDetail(
      vodId: effectiveVodId,
      vodName: effectiveVodName,
      vodPic: '',
      vodContent: '来自 WebDAV · ${server.name}\n'
          '当前目录：${fileCtl.currentPath.value}',
      vodYear: '',
      vodActor: '',
      vodDirector: '',
      vodRemarks: effectiveRemarks,
      typeName: 'WebDAV',
      playSources: [
        PlaySource(
          name: server.name,
          episodes: episodes,
        ),
      ],
    );

    // ---- 跳转详情页 ----
    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': currentUrl,
        'directTitle': currentEpisodeName ?? _stripMediaExtension(entry.name),
        'videoDetail': videoDetail,
        'sourceName': server.name,
        'vodPic': '',
        'vodContent': '来自 WebDAV · ${server.name}',
        'vodYear': '',
        'vodActor': '',
        'vodDirector': '',
        'vodRemarks': effectiveRemarks,
        'headers': headers,
        'isSeries': !isSingleFile,
        'isDirectPushMode': true,
      },
    );
  }
}