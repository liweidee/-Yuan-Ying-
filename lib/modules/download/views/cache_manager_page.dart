// lib/modules/download/views/cache_manager_page.dart
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/download/models/cache_entry.dart';
import 'package:yuanying/modules/download/services/cache_service.dart';
import 'package:yuanying/modules/download/widgets/cache_item.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/services/magnet/magnet_cache_manager.dart';
import 'package:yuanying/services/magnet/magnet_models.dart';
import 'package:yuanying/services/magnet/magnet_plugin_service.dart';

class CacheManagerPage extends StatefulWidget {
  const CacheManagerPage({super.key});

  @override
  State<CacheManagerPage> createState() => _CacheManagerPageState();
}

class _CacheManagerPageState extends State<CacheManagerPage> {
  final _service = Get.find<CacheService>();
  final _magnetService = MagnetCacheManager.instance;
  final _selected = <String>{};
  final _searchController = TextEditingController();

  bool _multiSelect = false;
  bool _searching = false;
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // 搜索过滤
  // ============================================================
  List<CacheEntry> _filter(List<CacheEntry> src) {
    if (_keyword.isEmpty) return src;
    final k = _keyword.toLowerCase();
    return src
        .where((e) =>
            e.vodName.toLowerCase().contains(k) ||
            e.episodeName.toLowerCase().contains(k) ||
            e.displayTitle.toLowerCase().contains(k))
        .toList();
  }

  // ============================================================
  // 选择逻辑
  // ============================================================
  void _exitMultiSelect() {
    setState(() {
      _multiSelect = false;
      _selected.clear();
    });
  }

  void _toggleSelect(CacheEntry entry) {
    setState(() {
      if (_selected.contains(entry.id)) {
        _selected.remove(entry.id);
      } else {
        _selected.add(entry.id);
      }
    });
  }

  void _toggleSelectAll(List<CacheEntry> all) {
    setState(() {
      if (_selected.length == all.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all.map((e) => e.id));
      }
    });
  }

  // ============================================================
  // 构建
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final all = _service.entries;
      final migrating = _service.isMigrating.value;
      final downloading = _filter(
        all.where((e) => !e.isCompleted).toList(),
      );
      final completed = _filter(
        all.where((e) => e.isCompleted).toList(),
      );
      final magnetEntries = _magnetService.entries;

      return PopScope(
        canPop: !_multiSelect && !_searching,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_multiSelect) {
            _exitMultiSelect();
          } else if (_searching) {
            _exitSearch();
          }
        },
        child: Scaffold(
          backgroundColor: SettingPref.bgActive ? Colors.transparent : theme.colorScheme.surface,
          appBar: _buildAppBar(downloading, completed),
          body: CustomScrollView(
            slivers: [
              if (migrating)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Column(
                      children: [
                        LinearProgressIndicator(),
                        SizedBox(height: 6),
                        Text('正在迁移下载目录，请保持应用运行…'),
                      ],
                    ),
                  ),
                ),
              // ===== 正在缓存 =====
              if (downloading.isNotEmpty) ...[
                _buildSectionHeader(
                  '正在缓存 (${downloading.length})',
                  top: 12,
                ),
                SliverList.builder(
                  itemCount: downloading.length,
                  itemBuilder: (context, index) {
                    final entry = downloading[index];
                    return CacheItem(
                      entry: entry,
                      multiSelect: _multiSelect,
                      selected: _selected.contains(entry.id),
                      onSelect: () => _toggleSelect(entry),
                      onTap: () => _onItemTap(entry),
                      onDelete: () => _onDelete(entry),
                      onPause: () => _service.pauseDownload(entry),
                      onResume: () => _service.resumeDownload(entry),
                    );
                  },
                ),
              ],

              // ===== 磁力缓存 =====
              if (magnetEntries.isNotEmpty) ...[
                _buildSectionHeader(
                  '磁力缓存 (${magnetEntries.length})',
                  top: downloading.isEmpty ? 12 : 16,
                ),
                SliverList.builder(
                  itemCount: magnetEntries.length,
                  itemBuilder: (context, index) {
                    return _buildMagnetItem(magnetEntries[index]);
                  },
                ),
              ],

              // ===== 已缓存视频 =====
              if (completed.isNotEmpty) ...[
                _buildSectionHeader(
                  '已缓存视频 (${completed.length})',
                  top: downloading.isEmpty && magnetEntries.isEmpty ? 12 : 16,
                ),
                SliverList.builder(
                  itemCount: completed.length,
                  itemBuilder: (context, index) {
                    final entry = completed[index];
                    return CacheItem(
                      entry: entry,
                      multiSelect: _multiSelect,
                      selected: _selected.contains(entry.id),
                      onSelect: () => _toggleSelect(entry),
                      onTap: () => _onItemTap(entry),
                      onDelete: () => _onDelete(entry),
                      onPause: () => _service.pauseDownload(entry),
                      onResume: () => _service.resumeDownload(entry),
                    );
                  },
                ),
              ],

              // ===== 空状态 =====
              if (downloading.isEmpty &&
                  completed.isEmpty &&
                  magnetEntries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(theme),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      );
    });
  }

  // ============================================================
  // AppBar 三态：普通 / 搜索 / 多选
  // ============================================================
  PreferredSizeWidget _buildAppBar(
    List<CacheEntry> downloading,
    List<CacheEntry> completed,
  ) {
    // ---- 搜索态 ----
    if (_searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _exitSearch,
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索缓存视频',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _keyword = v.trim()),
        ),
        actions: [
          if (_keyword.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                setState(() => _keyword = '');
              },
            ),
        ],
      );
    }

    // ---- 多选态 ----
    if (_multiSelect) {
      final all = [...downloading, ...completed];
      final total = all.length;
      final isAllSelected = total > 0 && _selected.length == total;
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitMultiSelect,
        ),
        title: Text('已选 ${_selected.length}'),
        actions: [
          IconButton(
            tooltip: isAllSelected ? '取消全选' : '全选',
            icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all),
            onPressed: total == 0 ? null : () => _toggleSelectAll(all),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: _selected.isEmpty ? null : _deleteSelected,
          ),
          const SizedBox(width: 6),
        ],
      );
    }

    // ---- 普通态 ----
    return AppBar(
      title: const Text('缓存管理'),
      actions: [
        IconButton(
          tooltip: '存储空间与下载目录',
          icon: const Icon(Icons.storage_rounded),
          onPressed: _service.isMigrating.value
              ? null
              : () => Get.toNamed(AppPages.storageManagement),
        ),
        IconButton(
          tooltip: '搜索',
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searching = true),
        ),
        IconButton(
          tooltip: '多选',
          icon: const Icon(Icons.checklist),
          onPressed: () => setState(() => _multiSelect = true),
        ),
        IconButton(
          tooltip: '清空普通下载缓存',
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed:
              _service.entries.isEmpty || _service.isMigrating.value
              ? null
              : _clearAll,
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  // ============================================================
  // 退出搜索
  // ============================================================
  void _exitSearch() {
    setState(() {
      _searching = false;
      _keyword = '';
      _searchController.clear();
    });
  }

  // ============================================================
  // 分区标题
  // ============================================================
  Widget _buildSectionHeader(String title, {double top = 0}) {
    return SliverPadding(
      padding: EdgeInsets.only(left: 12, top: top, bottom: 7),
      sliver: SliverToBoxAdapter(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 空状态
  // ============================================================
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            _keyword.isEmpty ? '暂无缓存' : '未找到相关缓存',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildMagnetItem(MagnetCacheEntry entry) {
    final mediaExists =
        entry.mediaPath != null &&
        entry.mediaPath!.isNotEmpty &&
        File(entry.mediaPath!).existsSync();
    final size = formatMagnetBytes(
      entry.complete && entry.totalBytes > 0
          ? entry.totalBytes
          : entry.downloadedBytes,
    );
    final subtitle = entry.complete
        ? '${mediaExists ? '已缓存' : '已完成'} · $size'
        : '缓存中 ${formatMagnetBytes(entry.downloadedBytes)} / '
              '${formatMagnetBytes(entry.totalBytes)}';
    return ListTile(
      leading: Icon(
        entry.complete ? Icons.movie_filter : Icons.downloading,
      ),
      title: Text(
        entry.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _onMagnetTap(entry),
      trailing: IconButton(
        tooltip: '删除磁力缓存',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _onMagnetDelete(entry),
      ),
    );
  }

  Future<void> _onMagnetTap(MagnetCacheEntry entry) async {
    final canPlayLocal =
        entry.complete &&
        entry.mediaPath != null &&
        entry.mediaPath!.isNotEmpty &&
        File(entry.mediaPath!).existsSync();
    final localUrl = canPlayLocal ? 'file://${entry.mediaPath}' : null;
    final magnetUrl = MagnetUri.build(
      infoHash: entry.infoHash,
      fileIndex: entry.fileIndex,
      originalMagnet: entry.originalMagnet,
      fileName: entry.fileName,
    );
    final url = localUrl ?? magnetUrl;
    final detail = VideoDetail(
      vodId: 'magnet_${entry.infoHash}_${entry.fileIndex}',
      vodName: entry.fileName,
      vodPic: '',
      playSources: [
        PlaySource(
          name: localUrl == null ? '磁力缓存' : '本地缓存',
          episodes: [Episode(name: entry.fileName, url: url)],
        ),
      ],
    );
    await Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'isDirectPushMode': true,
        'directUrl': url,
        'directTitle': entry.fileName,
        'videoDetail': detail,
        '_controllerTag':
            'magnet_cache_${DateTime.now().millisecondsSinceEpoch}',
      },
    );
  }

  Future<void> _onMagnetDelete(MagnetCacheEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除磁力缓存'),
        content: Text('确定删除「${entry.fileName}」的磁力媒体文件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final session = MagnetPluginService.instance.currentSession;
    if (session?.infoHash == entry.infoHash &&
        session?.file.index == entry.fileIndex) {
      await MagnetPluginService.instance.stopCurrent(deleteMedia: true);
    }
    await _magnetService.deleteEntry(entry);
    if (mounted) SmartDialog.showToast('磁力缓存已删除');
  }

  // ============================================================
  // 点击条目
  // ============================================================
  Future<void> _onItemTap(CacheEntry entry) async {
    if (_multiSelect) {
      _toggleSelect(entry);
      return;
    }

    // ---- 已完成 → 播放本地文件 ----
    if (entry.isCompleted) {
      final localUrl = 'file://${entry.savePath}';

      // 构造一个最小的 VideoDetail，让 _initPushMode 走「传了 videoDetail」分支，
      // 从而让 sourceName = '本地缓存' 被原版代码正常设置。
      // 这样既不动 video_controller.dart，也不影响其它调用方。
      final detail = VideoDetail(
        vodId: 'local_${entry.id}',
        vodName: entry.vodName,
        vodPic: entry.vodPic ?? '',
        playSources: [
          PlaySource(
            name: '本地缓存',
            episodes: [
              Episode(name: entry.displayTitle, url: localUrl),
            ],
          ),
        ],
      );

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'isPush': true,
          'isDirectPushMode': true,
          'directUrl': localUrl,
          'directTitle': entry.displayTitle,
          'vodPic': entry.vodPic,
          'vodName': entry.vodName,
          'sourceName': '本地缓存',
          'videoDetail': detail,
        },
      );
      return;
    }

    // ---- 下载中 → 暂停；其他 → 继续 / 重试 ----
    if (entry.isDownloading) {
      await _service.pauseDownload(entry);
    } else {
      await _service.resumeDownload(entry);
    }
  }

  // ============================================================
  // 单条删除
  // ============================================================
  Future<void> _onDelete(CacheEntry entry) async {
    if (_service.isMigrating.value) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除缓存'),
        content: Text('确定删除「${entry.displayTitle}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.deleteEntry(entry);
    if (!mounted) return;
    SmartDialog.showToast('已删除');
  }

  // ============================================================
  // 批量删除
  // ============================================================
  Future<void> _deleteSelected() async {
    if (_service.isMigrating.value) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 ${_selected.length} 个缓存吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ids = _selected.toList();
    for (final id in ids) {
      final entry = _service.entries.firstWhereOrNull((e) => e.id == id);
      if (entry != null) {
        await _service.deleteEntry(entry);
      }
    }
    if (!mounted) return;
    _exitMultiSelect();
    SmartDialog.showToast('已删除');
  }

  Future<void> _clearAll() async {
    if (_service.entries.isEmpty || _service.isMigrating.value) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空普通下载缓存'),
        content: Text(
          '确定删除全部 ${_service.entries.length} 条离线缓存吗？'
          '对应视频文件也会被删除，此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.deleteAll();
    if (!mounted) return;
    SmartDialog.showToast('缓存已全部清空');
  }
}
