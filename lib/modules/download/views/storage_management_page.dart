import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/download/services/cache_service.dart';
import 'package:yuanying/modules/plugin_center/widgets/storage_permission_button.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/utils/cache_manager.dart';

class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key});

  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  final CacheService _service = Get.find<CacheService>();

  CacheStorageStats? _stats;
  int _appCacheBytes = 0;
  String? _error;
  bool _loading = true;
  bool _clearingDownloads = false;
  bool _clearingAppCache = false;

  bool get _busy =>
      _loading ||
      _service.isMigrating.value ||
      _clearingDownloads ||
      _clearingAppCache;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final stats = await _service.storageStats();
      final appCacheBytes = await CacheManager.loadApplicationCache();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _appCacheBytes = appCacheBytes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<String?> _chooseDirectory() async {
    if (Platform.isAndroid) {
      final granted = await StoragePermissionButton.isGranted();
      if (!mounted) return null;
      if (!granted) {
        final shouldRequest = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('需要文件访问权限'),
            content: const Text(
              '选择应用外部目录并迁移下载文件前，需要授予文件访问权限。'
              '也可以继续使用应用内部存储，无需额外授权。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('前往授权'),
              ),
            ],
          ),
        );
        if (shouldRequest == true) {
          await StoragePermissionButton.request();
          if (mounted) {
            SmartDialog.showToast('完成授权后，请再次选择下载目录');
          }
        }
        return null;
      }
    }

    if (Platform.isIOS) {
      if (!mounted) return null;
      return showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择下载位置'),
          children: [
            SimpleDialogOption(
              onPressed: () async {
                final directory = await getApplicationSupportDirectory();
                if (context.mounted) Navigator.pop(context, directory.path);
              },
              child: const Text('应用内部存储'),
            ),
            SimpleDialogOption(
              onPressed: () async {
                final directory = await getApplicationDocumentsDirectory();
                if (context.mounted) Navigator.pop(context, directory.path);
              },
              child: const Text('文件 App 可见目录（Documents）'),
            ),
          ],
        ),
      );
    }

    return FilePicker.getDirectoryPath(dialogTitle: '选择下载保存位置');
  }

  Future<void> _changeDirectory() async {
    if (_busy) return;
    final selected = await _chooseDirectory();
    if (selected == null || selected.trim().isEmpty || !mounted) return;

    final target = CacheService.resolveTargetDirectory(selected);
    final current = _stats?.directory ?? '';
    if (path.equals(path.normalize(current), path.normalize(target))) {
      SmartDialog.showToast('当前已经使用该下载目录');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('迁移下载目录'),
        content: Text(
          '将当前下载内容迁移到：\n$target\n\n'
          '迁移期间会暂停下载。只有全部复制成功后才切换目录，'
          '失败时会保留原目录和现有记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始迁移'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.moveDownloadDirectory(target);
      await _refresh();
      if (mounted) SmartDialog.showToast('下载目录迁移完成');
    } catch (error) {
      if (mounted) SmartDialog.showToast('迁移失败：$error');
    }
  }

  Future<void> _restoreDefaultDirectory() async {
    if (_busy) return;
    final target = await _service.defaultDownloadDirectoryPath();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认下载目录'),
        content: Text('现有下载将迁移到：\n$target'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('迁移'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.moveToDefaultDownloadDirectory();
      await _refresh();
      if (mounted) SmartDialog.showToast('已恢复默认下载目录');
    } catch (error) {
      if (mounted) SmartDialog.showToast('迁移失败：$error');
    }
  }

  Future<void> _clearDownloads() async {
    if (_busy || _service.entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空离线缓存'),
        content: Text(
          '将删除全部 ${_service.entries.length} 条离线缓存记录及对应文件，'
          '此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingDownloads = true);
    try {
      await _service.deleteAll();
      await _refresh();
      if (mounted) SmartDialog.showToast('离线缓存已清空');
    } catch (error) {
      if (mounted) SmartDialog.showToast('清理失败：$error');
    } finally {
      if (mounted) setState(() => _clearingDownloads = false);
    }
  }

  Future<void> _clearAppCache() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理应用缓存'),
        content: const Text('仅清理网络、图片和临时文件，不会删除离线下载内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingAppCache = true);
    try {
      await CacheManager.clearLibraryCache();
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await _refresh();
      if (mounted) SmartDialog.showToast('应用缓存已清理');
    } catch (error) {
      if (mounted) SmartDialog.showToast('清理失败：$error');
    } finally {
      if (mounted) setState(() => _clearingAppCache = false);
    }
  }

  String _displayDirectory(String raw) {
    if (raw.isEmpty) return '暂不可用';
    if (Platform.isIOS && raw.contains('/Containers/Data/Application/')) {
      if (raw.contains('/Documents/')) {
        return '应用沙盒：Documents/${raw.split('/Documents/').last}';
      }
      if (raw.contains('/Library/')) {
        return '应用沙盒：Library/${raw.split('/Library/').last}';
      }
      return '应用专属沙盒目录';
    }
    return raw;
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: Style.mdRadius,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: Style.mdRadius,
                  ),
                  child: Icon(icon, color: colorScheme.primary, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: theme.dividerColor.withValues(alpha: 0.08),
          ),
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.dividerColor.withValues(alpha: 0.08),
              ),
            Material(
              type: MaterialType.transparency,
              child: children[index],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Obx(() {
      final entries = _service.entries.toList();
      final migrating = _service.isMigrating.value;
      final stats = _stats;
      final completed = entries.where((entry) => entry.isCompleted).length;
      final unfinished = entries.length - completed;

      return PopScope(
        canPop: !migrating,
        child: Scaffold(
          backgroundColor: SettingPref.bgActive
              ? Colors.transparent
              : theme.colorScheme.surface,
          appBar: AppBar(
            title: const Text('存储空间与下载目录'),
            actions: [
              if (Platform.isAndroid) const StoragePermissionButton(),
              IconButton(
                tooltip: '刷新',
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              Style.safeSpace,
              Style.safeSpace,
              Style.safeSpace,
              100,
            ),
            children: [
              if (_error != null) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: Style.mdRadius,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: colorScheme.onErrorContainer,
                      ),
                      title: const Text('无法读取下载目录'),
                      subtitle: Text(_error!),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (migrating) ...[
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: Style.mdRadius,
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: const Column(
                    children: [
                      LinearProgressIndicator(),
                      SizedBox(height: 8),
                      Text(
                        '正在迁移下载目录，请保持应用运行…',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _buildSection(
                icon: Icons.pie_chart_outline_rounded,
                title: '存储空间占用',
                subtitle: '统计当前下载目录中的实际文件',
                children: [
                  ListTile(
                    leading: const Icon(Icons.video_library_outlined),
                    title: Text(
                      stats == null
                          ? '正在统计离线缓存…'
                          : CacheManager.formatSize(stats.usedBytes),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '已下载 $completed 集 · 未完成 $unfinished 个任务 · '
                      '${stats?.fileCount ?? 0} 个文件',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildSection(
                icon: Icons.cleaning_services_outlined,
                title: '缓存管理',
                subtitle: '管理应用临时缓存和离线视频缓存',
                children: [
                  ListTile(
                    leading: const Icon(Icons.cached_rounded),
                    title: const Text('应用临时缓存'),
                    subtitle: Text(
                      _loading
                          ? '正在计算…'
                          : CacheManager.formatSize(_appCacheBytes),
                    ),
                    trailing: TextButton(
                      onPressed: _busy ? null : _clearAppCache,
                      child: _clearingAppCache
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('清理'),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.video_library_outlined),
                    title: const Text('离线缓存视频'),
                    subtitle: const Text('查看、播放或删除单条缓存'),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () => Get.toNamed(AppPages.cacheManager),
                      child: const Text('管理'),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.delete_sweep_outlined,
                      color: colorScheme.error,
                    ),
                    title: Text(
                      '清空离线缓存',
                      style: TextStyle(color: colorScheme.error),
                    ),
                    subtitle: const Text('同步删除缓存列表、文件和下载记录'),
                    trailing: TextButton(
                      onPressed: _busy || entries.isEmpty
                          ? null
                          : _clearDownloads,
                      child: _clearingDownloads
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('全部删除'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '清理临时缓存不会删除已下载视频。',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildSection(
                icon: Icons.folder_outlined,
                title: '下载保存目录',
                subtitle: '更改目录时同步迁移现有下载文件',
                children: [
                  ListTile(
                    leading: const Icon(Icons.folder_special_outlined),
                    title: const Text('当前保存路径'),
                    subtitle: SelectableText(
                      _displayDirectory(stats?.directory ?? ''),
                    ),
                    trailing: IconButton(
                      tooltip: '复制完整路径',
                      onPressed: stats == null || stats.directory.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: stats.directory),
                              );
                              SmartDialog.showToast('已复制下载路径');
                            },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.drive_file_move_outlined),
                    title: const Text('更改并迁移目录'),
                    subtitle: const Text('复制现有下载，成功后切换保存位置'),
                    enabled: !_busy,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy ? null : _changeDirectory,
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore_rounded),
                    title: const Text('恢复默认目录'),
                    subtitle: const Text('迁移回应用内部存储'),
                    enabled: !_busy,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _busy ? null : _restoreDefaultDirectory,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}
