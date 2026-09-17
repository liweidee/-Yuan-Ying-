import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path_provider/path_provider.dart';
import '../controllers/alist_server_controller.dart';

class AlistCachePage extends StatefulWidget {
  const AlistCachePage({super.key});

  @override
  State<AlistCachePage> createState() => _AlistCachePageState();
}

class _AlistCachePageState extends State<AlistCachePage> {
  int _cacheSize = 0;
  String _cacheSizeStr = '计算中...';
  String _cachePath = '';
  bool _calculating = false;

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  Future<void> _calculate() async {
    if (_calculating) return;
    setState(() {
      _calculating = true;
      _cacheSizeStr = '计算中...';
    });
    try {
      final serverCtrl = Get.find<AlistServerController>();
      final server = serverCtrl.currentServer;
      if (server == null) {
        if (mounted) setState(() => _calculating = false);
        return;
      }

      Directory baseDir;
      if (Platform.isAndroid) {
        baseDir = await getExternalStorageDirectory() ??
            await getTemporaryDirectory();
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }
      final subPath = '${server.id}/${server.username ?? "guest"}';
      final dir = Directory('${baseDir.path}/AListDownloads/$subPath');
      _cachePath = dir.path;

      if (!await dir.exists()) {
        if (mounted) {
          setState(() {
            _cacheSize = 0;
            _cacheSizeStr = '0 B';
            _calculating = false;
          });
        }
        return;
      }

      int total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      if (mounted) {
        setState(() {
          _cacheSize = total;
          _cacheSizeStr = _formatSize(total);
          _calculating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cacheSizeStr = '计算失败';
          _calculating = false;
        });
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  Future<void> _clearCache() async {
    if (_cachePath.isEmpty) return;
    if (_cacheSize == 0) {
      SmartDialog.showToast('暂无缓存');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('将删除所有已下载的 AList 文件（不含下载记录）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final dir = Directory(_cachePath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      SmartDialog.showToast('已清除');
      _calculate();
    } catch (e) {
      SmartDialog.showToast('清除失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('缓存管理'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: [
          // ==================== 已用空间（大卡片） ====================
          _sectionHeader(theme, '已用空间'),
          _storageCard(theme, cs),

          // ==================== 操作 ====================
          _sectionHeader(theme, '操作'),
          _cardRow(
            theme,
            icon: Icons.refresh_rounded,
            title: '重新计算',
            subtitle: '刷新缓存占用统计',
            onTap: _calculating ? null : _calculate,
          ),
          const SizedBox(height: 6),
          _cardRow(
            theme,
            icon: Icons.delete_sweep_outlined,
            title: '清除下载文件',
            subtitle: '删除本地已下载的 AList 文件',
            titleColor: cs.error,
            iconColor: cs.error,
            onTap: _clearCache,
          ),

          // ==================== 缓存位置 ====================
          if (_cachePath.isNotEmpty) ...[
            _sectionHeader(theme, '缓存位置'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      color: cs.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectableText(
                        _cachePath,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ============================================================
  // 样式辅助
  // ============================================================

  /// 分区标题（主题色小字）
  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /// 大号存储卡片：图标 + 大号数字 + 刷新按钮
  Widget _storageCard(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // 图标方块
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.sd_storage_outlined,
                color: cs.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            // 大小 + 副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _cacheSizeStr,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '本地缓存占用',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 刷新按钮
            IconButton(
              icon: _calculating
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    )
                  : Icon(Icons.refresh_rounded, color: cs.primary, size: 22),
              tooltip: '重新计算',
              onPressed: _calculating ? null : _calculate,
              splashRadius: 22,
            ),
          ],
        ),
      ),
    );
  }

  /// 通用操作行（卡片式，无下划线）
  Widget _cardRow(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Color? titleColor,
    Color? iconColor,
  }) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: iconColor ?? cs.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: titleColor ?? cs.onSurface,
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}