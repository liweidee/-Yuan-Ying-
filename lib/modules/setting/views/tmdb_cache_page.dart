// lib/modules/setting/views/tmdb_cache_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/services/tmdb_match_cache_service.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/modules/setting/controllers/tmdb_config_controller.dart';
import 'package:yuanying/models/tmdb_match_record.dart';

class TmdbCachePage extends StatefulWidget {
  const TmdbCachePage({super.key});

  @override
  State<TmdbCachePage> createState() => _TmdbCachePageState();
}

class _TmdbCachePageState extends State<TmdbCachePage> {
  final _cacheService = Get.find<TmdbMatchCacheService>();
  final _sourceManager = Get.find<SourceManager>();

  String _searchQuery = '';
  List<TmdbCacheEntry> _allEntries = [];
  List<TmdbCacheEntry> _filteredEntries = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _allEntries = _cacheService.getAll();
      _applyFilter();
    });
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredEntries = List.from(_allEntries);
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredEntries = _allEntries.where((e) {
        final siteName = _getSiteName(e.siteKey).toLowerCase();
        return siteName.contains(q) ||
            e.record.title.toLowerCase().contains(q) ||
            e.vodId.toLowerCase().contains(q);
      }).toList();
    }
  }

  String _getSiteName(String siteKey) {
    for (final site in _sourceManager.sites) {
      if (site['key']?.toString() == siteKey) {
        return site['name']?.toString() ?? siteKey;
      }
    }
    return siteKey;
  }

  Future<void> _clearAll() async {
    final confirmed = await SmartDialog.show<bool>(
      builder: (_) => AlertDialog(
        title: const Text('清空全部缓存'),
        content: Text('确定要清除全部 ${_cacheService.count} 条 TMDB 匹配记录吗？'),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => SmartDialog.dismiss(result: true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _cacheService.clear();
    SmartDialog.showToast('已清空');
    _reload();
  }

  Future<void> _removeEntry(TmdbCacheEntry entry) async {
    await _cacheService.remove(entry.siteKey, entry.vodId);
    SmartDialog.showToast('已删除');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'TMDB 匹配缓存',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: colorScheme.onSurface),
          onPressed: () => Get.back(),
        ),
        actions: [
          if (_allEntries.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep, color: colorScheme.outline),
              tooltip: '清空全部',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Style.safeSpace),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) {
                      setState(() {
                        _searchQuery = v;
                        _applyFilter();
                      });
                    },
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: '搜索片名 / 站点...',
                      hintStyle: TextStyle(color: colorScheme.outline),
                      prefixIcon:
                          Icon(Icons.search, color: colorScheme.outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor:
                          colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_allEntries.length}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _filteredEntries.isEmpty
                ? _buildEmpty(colorScheme)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Style.safeSpace,
                    ),
                    itemCount: _filteredEntries.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Style.cardSpace),
                    itemBuilder: (context, index) {
                      final entry = _filteredEntries[index];
                      return _buildEntryCard(entry, colorScheme);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: colorScheme.outline.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isEmpty ? '暂无匹配缓存' : '未找到匹配项',
            style: TextStyle(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(TmdbCacheEntry entry, ColorScheme colorScheme) {
    final record = entry.record;
    final siteName = _getSiteName(entry.siteKey);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 50,
                height: 75,
                color: colorScheme.surfaceContainerHighest,
                child: record.posterPath.isNotEmpty
                    ? Image.network(
                        _buildPosterUrl(record.posterPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.movie,
                          color: colorScheme.outline,
                        ),
                      )
                    : Icon(Icons.movie, color: colorScheme.outline),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      siteName,
                      if (record.displayYear.isNotEmpty) record.displayYear,
                      record.mediaType == 'tv' ? '剧集' : '电影',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'vodId: ${entry.vodId}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.outline.withOpacity(0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 20, color: colorScheme.outline),
              onPressed: () => _removeEntry(entry),
            ),
          ],
        ),
      ),
    );
  }

  String _buildPosterUrl(String path) {
    final tmdbCtrl = Get.find<TmdbConfigController>();
    String base = tmdbCtrl.imageProxy.value.trim();
    if (base.isEmpty) base = 'https://image.tmdb.org/t/p';
    if (!base.endsWith('/')) base = '$base/';
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '${base}w92/$cleanPath';
  }
}