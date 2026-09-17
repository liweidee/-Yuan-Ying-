import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';
import '../controllers/alist_file_list_controller.dart';
import '../controllers/alist_server_controller.dart';
import '../models/alist_file_viewing_record.dart';
import '../services/alist_file_utils.dart';
import '../services/alist_open_helper.dart';

class AlistRecentsPage extends StatefulWidget {
  const AlistRecentsPage({super.key});

  @override
  State<AlistRecentsPage> createState() => _AlistRecentsPageState();
}

class _AlistRecentsPageState extends State<AlistRecentsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<AlistFileViewingRecord> _loadRecords() {
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return [];

    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.fileViewingRecords,
        ) ??
        [];
    return raw
        .map((e) =>
            AlistFileViewingRecord.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.serverId == server.id)
        .toList();
  }

  Future<void> _removeRecord(AlistFileViewingRecord record) async {
    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.fileViewingRecords,
        ) ??
        [];
    final list = raw
        .map((e) =>
            AlistFileViewingRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    list.removeWhere((e) => e.id == record.id);
    await StorageManager.setSetting(
      AlistStorageKeys.fileViewingRecords,
      list.map((e) => e.toJson()).toList(),
    );
    alistRecentsRefreshTick.value++;
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空浏览记录'),
        content: const Text('确认清空所有浏览记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return;

    final raw = StorageManager.getSetting<List<dynamic>>(
          AlistStorageKeys.fileViewingRecords,
        ) ??
        [];
    final remaining = raw
        .map((e) =>
            AlistFileViewingRecord.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.serverId != server.id)
        .toList();
    await StorageManager.setSetting(
      AlistStorageKeys.fileViewingRecords,
      remaining.map((e) => e.toJson()).toList(),
    );
    alistRecentsRefreshTick.value++;
  }

  bool _isImageName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic');
  }

  /// 单行卡片
  Widget _buildRow(
    BuildContext context,
    AlistFileViewingRecord r,
  ) {
    final cs = Theme.of(context).colorScheme;
    final icon = AlistFileUtils.getFileIcon(false, r.name);
    final thumbnail = AlistFileUtils.getCompleteThumbnail(r.thumb);
    final showThumb = thumbnail != null &&
        thumbnail.isNotEmpty &&
        _isImageName(r.name);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          child: InkWell(
            onTap: () {
              AlistOpenHelper.openItem(
                context: context,
                name: r.name,
                path: r.path,
                sign: r.sign,
                thumb: r.thumb,
                isDir: false,
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  // ---- 图片缩略图 或 主题色图标 ----
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: showThumb
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              thumbnail,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                icon,
                                color: cs.primary,
                                size: 24,
                              ),
                            ),
                          )
                        : Icon(icon, color: cs.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  // ---- 名称 + 路径 ----
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ---- 删除按钮 ----
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    tooltip: '删除',
                    onPressed: () => _removeRecord(r),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) {
      return const Scaffold(
        body: Center(child: Text('未选择服务器')),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('最近浏览'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          Obx(() {
            alistRecentsRefreshTick.value;
            final records = _loadRecords();
            if (records.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空记录',
              onPressed: _clearAll,
            );
          }),
        ],
      ),
      body: Obx(() {
        alistRecentsRefreshTick.value;
        final records = _loadRecords();

        if (records.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history_toggle_off_rounded,
                  size: 72,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无浏览记录',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '你播放过的文件会出现在这里',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          itemCount: records.length,
          itemBuilder: (ctx, i) => _buildRow(ctx, records[i]),
        );
      }),
    );
  }
}