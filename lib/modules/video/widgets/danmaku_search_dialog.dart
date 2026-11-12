// lib/modules/video/widgets/danmaku_search_dialog.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/utils/storage_manager.dart';

/// 弹幕搜索弹窗（底部弹出）
///
/// 流程：
///   1. 自动填入当前视频标题并发起搜索
///   2. 调 {apiBase}/api/v2/search/anime?keyword=xxx 拿候选列表
///   3. 用户点击某项 → 关闭弹窗 → 交给 DetailController.loadDanmakuByTitle
///
/// 作用域：手动选择的弹幕**仅在当前集生效**。
/// 切换剧集后 `_startPlay` 会重置 `_danmakuLoaded` 并触发自动匹配，
/// 手动选择的弹幕不会残留到下一集，也不会影响自动匹配机制。
class DanmakuSearchDialog extends StatefulWidget {
  final DetailController detailController;
  const DanmakuSearchDialog({super.key, required this.detailController});

  /// 防重入：保证同一时间只有一个搜索弹窗
  static bool _isShowing = false;

  /// 统一入口：底部弹窗
  static Future<void> show(BuildContext context, DetailController dc) async {
    if (_isShowing) return;
    _isShowing = true;
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        routeSettings: const RouteSettings(name: 'danmaku_search_sheet'),
        builder: (_) => DanmakuSearchDialog(detailController: dc),
      );
    } finally {
      _isShowing = false;
    }
  }

  @override
  State<DanmakuSearchDialog> createState() => _DanmakuSearchDialogState();
}

class _DanmakuSearchDialogState extends State<DanmakuSearchDialog> {
  final TextEditingController _keywordCtrl = TextEditingController();
  final Dio _dio = Dio();

  bool _loading = false;

  /// 是否已执行过一次搜索（用于区分"未搜索"和"搜索后空结果"）
  bool _hasSearched = false;

  String? _error;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    final name =
        widget.detailController.introController.videoDetail.value?.vodName ?? '';
    _keywordCtrl.text = name;
    if (name.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _search();
      });
    }
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  /// 读取当前选中的弹幕 API base
  ///
  /// 兼容三种情况：
  ///   - danmakuCurrentKey 为空 / 找不到对应项 → 取第一个
  ///   - 用户配置的 api 字段是完整 FongMi 地址（含 /fongmi/danmaku）
  ///   - 用户配置的是 base URL
  String? _getCurrentApiBase() {
    final apis =
        StorageManager.getSetting<List<dynamic>>(SettingBoxKey.danmakuApis) ??
            [];
    if (apis.isEmpty) return null;

    final currentKey =
        StorageManager.getSetting<String>(SettingBoxKey.danmakuCurrentKey) ??
            '';

    Map<String, dynamic>? matched;
    if (currentKey.isNotEmpty) {
      for (final item in apis) {
        if (item is Map && item['key'] == currentKey) {
          matched = Map<String, dynamic>.from(item);
          break;
        }
      }
    }
    // 兜底：currentKey 未落库或失效时用第一个
    if (matched == null) {
      final first = apis.firstWhere(
        (e) => e is Map,
        orElse: () => null,
      );
      if (first is Map) {
        matched = Map<String, dynamic>.from(first);
      }
    }
    final base = matched?['api']?.toString();
    return (base == null || base.isEmpty) ? null : base;
  }

  /// 规范化 base 并拼出 search/anime 接口地址
  ///
  /// 处理几种常见写法：
  ///   http://x.com                 → http://x.com/api/v2/search/anime
  ///   http://x.com/api/v2          → http://x.com/api/v2/search/anime
  ///   http://x.com/api/v2/fongmi   → http://x.com/api/v2/search/anime
  ///   http://x.com/prefix/api/v2/… → http://x.com/prefix/api/v2/search/anime
  String _buildSearchUrl(String base, String keyword) {
    // 先剥掉 query / fragment，避免用户配置里带 ?pwd=xxx
    String normalized = base.trim();
    final qIndex = normalized.indexOf('?');
    if (qIndex != -1) normalized = normalized.substring(0, qIndex);
    final hIndex = normalized.indexOf('#');
    if (hIndex != -1) normalized = normalized.substring(0, hIndex);
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    // 以 /api/v2 为锚点截断，保留前缀路径
    final idx = normalized.indexOf('/api/v2');
    if (idx != -1) {
      normalized = normalized.substring(0, idx + 7); // 保留 "/api/v2"
    } else {
      normalized = '$normalized/api/v2';
    }
    return Uri.parse('$normalized/search/anime')
        .replace(queryParameters: {'keyword': keyword})
        .toString();
  }

  Future<void> _search() async {
    final keyword = _keywordCtrl.text.trim();
    if (keyword.isEmpty) {
      SmartDialog.showToast('请输入搜索关键词');
      return;
    }

    final apiBase = _getCurrentApiBase();
    if (apiBase == null || apiBase.isEmpty) {
      setState(() {
        _error = '未配置弹幕API，请先在弹幕设置中添加';
        _results = [];
        _loading = false;
        _hasSearched = true;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _hasSearched = true;
    });

    // 记录开始时间，用于保证 loading 至少可见 250ms + 输出耗时日志
    final startTime = DateTime.now();

    try {
      final url = _buildSearchUrl(apiBase, keyword);
      debugPrint('[DanmakuSearch] GET $url');
      final resp = await _dio.get(url);

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[DanmakuSearch] 耗时 ${elapsed}ms, status=${resp.statusCode}');
      debugPrint('[DanmakuSearch] 响应类型=${resp.data.runtimeType}');

      final List<dynamic> rawList = _extractAnimeList(resp.data);
      debugPrint('[DanmakuSearch] 提取到 ${rawList.length} 条');

      // loading 至少展示 250ms，避免服务端缓存命中时"闪一下"用户以为没请求
      if (elapsed < 250) {
        await Future.delayed(Duration(milliseconds: 250 - elapsed));
      }
      if (!mounted) return;

      setState(() {
        _results = rawList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
        // 空结果不用 _error 承载，走 _results.isEmpty 分支
        _error = null;
      });
    } catch (e) {
      debugPrint('[DanmakuSearch] 异常: $e');
      if (!mounted) return;
      setState(() {
        _error = '搜索失败：$e';
        _loading = false;
        _results = [];
      });
    }
  }

  /// 兼容多种响应结构：
  ///   - 直接数组
  ///   - { animes: [...] }        ← danmu_api 主流格式
  ///   - { list: [...] }
  ///   - { data: [...] }
  ///   - { data: { list: [...] } }
  List<dynamic> _extractAnimeList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in ['animes', 'list', 'data']) {
        final v = data[key];
        if (v is List) return v;
      }
      final inner = data['data'];
      if (inner is Map) {
        for (final key in ['animes', 'list']) {
          final v = inner[key];
          if (v is List) return v;
        }
      }
    }
    return const [];
  }

  /// 从任意动漫项里取标题
  String _pickTitle(Map<String, dynamic> m) {
    return (m['animeTitle'] ??
            m['anime_title'] ??
            m['title'] ??
            m['name'] ??
            m['vod_name'] ??
            '')
        .toString()
        .trim();
  }

  /// 从任意动漫项里取类型描述
  String _pickType(Map<String, dynamic> m) {
    return (m['typeDescription'] ??
            m['type_description'] ??
            m['type'] ??
            m['typeName'] ??
            '')
        .toString()
        .trim();
  }

  /// 从任意动漫项里取年份（"2024-01-01" → "2024"）
  String _pickYear(Map<String, dynamic> m) {
    final raw = (m['startDate'] ??
            m['start_date'] ??
            m['year'] ??
            m['premiereDate'] ??
            '')
        .toString()
        .trim();
    if (raw.isEmpty) return '';
    return raw.length >= 4 ? raw.substring(0, 4) : raw;
  }

  void _applyResult(Map<String, dynamic> anime) {
    final title = _pickTitle(anime);
    if (title.isEmpty) {
      SmartDialog.showToast('该结果缺少标题');
      return;
    }
    Navigator.pop(context);
    widget.detailController.loadDanmakuByTitle(title);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: screenHeight * 0.72,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // ===== 拖拽条 =====
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ===== 标题栏 =====
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.manage_search, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  const Text(
                    '搜索弹幕',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // ===== 搜索框 =====
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keywordCtrl,
                      decoration: const InputDecoration(
                        hintText: '输入动漫名称...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _loading ? null : _search,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 18),
                    label: const Text('搜索'),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ===== 本次搜索信息（关键词 + 结果数）=====
            if (_hasSearched && !_loading && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '关键词「${_keywordCtrl.text.trim()}」',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: cs.outline),
                      ),
                    ),
                    Text(
                      '${_results.length} 条',
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
              ),

            // ===== 结果区 =====
            Expanded(child: _buildResultBody(cs)),

            // ===== 底部提示 =====
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                '提示：仅对当前集生效，切换剧集后恢复自动匹配',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      // 搜索失败态
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: cs.outline),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.outline),
              ),
            ],
          ),
        ),
      );
    }
    if (!_hasSearched) {
      // 未搜索态
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 40, color: cs.outline),
            const SizedBox(height: 8),
            Text(
              '输入关键词后点击搜索',
              style: TextStyle(color: cs.outline),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      // 搜索后空结果态
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: cs.outline),
            const SizedBox(height: 8),
            Text(
              '未找到结果，试试其他关键词',
              style: TextStyle(color: cs.outline),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      itemCount: _results.length,
      itemBuilder: (_, index) => _buildResultItem(_results[index], index, cs),
    );
  }

  Widget _buildResultItem(
    Map<String, dynamic> anime,
    int index,
    ColorScheme cs,
  ) {
    final title = _pickTitle(anime);
    final typeDesc = _pickType(anime);
    final year = _pickYear(anime);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _applyResult(anime),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                // 左侧：标题 + 元信息标签
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? '（无标题）' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                          height: 1.3,
                        ),
                      ),
                      if (year.isNotEmpty || typeDesc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (year.isNotEmpty) _chip(year, cs),
                            if (typeDesc.isNotEmpty) _chip(typeDesc, cs),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 右侧：只保留"应用"文字
                Text(
                  '应用',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 元信息标签：保留浅色背景 + 细边框，不带图标
  ///
  /// 只承担"视觉分组"作用，内容用纯文字表达，避免 10px 图标在视觉上
  /// 成为噪音（看不清、占宽度、层级关系无法体现）。
  Widget _chip(String text, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: cs.outline),
      ),
    );
  }
}