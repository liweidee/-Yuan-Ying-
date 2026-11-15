import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/video/controllers/video_controller.dart';

import '../models/subtitle_file.dart';
import '../models/subtitle_search_result.dart';
import '../models/subtitle_site_type.dart';
import '../services/subtitle_site_manager.dart';
import '../services/subtitle_site_service.dart';
import '../utils/subtitle_utils.dart';

/// 字幕搜索对话框
class SubtitleSearchDialog extends StatefulWidget {
  final DetailController controller;

  const SubtitleSearchDialog({super.key, required this.controller});

  static void show(BuildContext context, DetailController controller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      routeSettings: const RouteSettings(name: 'subtitle_search_sheet'),
      builder: (_) => SubtitleSearchDialog(controller: controller),
    );
  }

  @override
  State<SubtitleSearchDialog> createState() => _SubtitleSearchDialogState();
}

class _SubtitleSearchDialogState extends State<SubtitleSearchDialog>
    with SingleTickerProviderStateMixin {
  final SubtitleSiteManager _manager = SubtitleSiteManager();
  late final TextEditingController _searchCtrl;
  late final List<SubtitleSiteService> _sites;
  TabController? _tabCtrl;

  final Map<SubtitleSiteType, List<SubtitleSearchResult>> _results = {};
  final Map<SubtitleSiteType, bool> _loading = {};
  final Map<SubtitleSiteType, String?> _errors = {};
  final Map<SubtitleSiteType, String> _actualKeywords = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(
      text: widget.controller.introController.videoDetail.value?.vodName ?? '',
    );
    _manager.init();
    _sites = _manager.available;

    if (_sites.isNotEmpty) {
      _tabCtrl = TabController(length: _sites.length, vsync: this)
        ..addListener(_onTabChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(_sites.first.type);
      });
    }
  }

  void _onTabChanged() {
    final ctrl = _tabCtrl;
    if (ctrl == null || ctrl.indexIsChanging) return;
    final type = _sites[ctrl.index].type;
    if (!_results.containsKey(type) && _loading[type] != true) {
      _search(type);
    } else {
      setState(() {});
    }
  }

  // ============================================================
  // 关键词增强（仅迅雷）
  // ============================================================

  String _enhanceKeywordForXunlei(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return trimmed;

    if (RegExp(r'[Ss]\d{1,2}[\s.\-_]*[Ee]\d{1,3}').hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(r'第\s*\d+\s*[季集话話期]').hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(r'\b(19|20)\d{2}\b').hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(r'^[A-Za-z]{2,8}-\d{2,5}$').hasMatch(trimmed)) {
      return trimmed;
    }

    final intro = widget.controller.introController;
    final detail = intro.videoDetail.value;
    if (detail == null) return trimmed;

    final episodes = intro.displayEpisodes;
    final isSeries = episodes.length > 1;
    final episodeIdx = intro.currentEpisodeIndex.value;
    if (isSeries) {
      final ep = (episodeIdx + 1).toString().padLeft(2, '0');
      return '$trimmed S01E$ep';
    }
    final year = detail.vodYear;
    if (year != null && RegExp(r'^\d{4}$').hasMatch(year)) {
      return '$trimmed $year';
    }
    return trimmed;
  }

  // ============================================================
  // 搜索
  // ============================================================

  Future<void> _search(SubtitleSiteType type) async {
    String keyword = _searchCtrl.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _loading[type] = false;
        _errors[type] = '请输入搜索关键词';
      });
      return;
    }
    if (type == SubtitleSiteType.xunlei) {
      keyword = _enhanceKeywordForXunlei(keyword);
    }
    _actualKeywords[type] = keyword;

    setState(() {
      _loading[type] = true;
      _errors.remove(type);
    });

    try {
      final list = await _manager.search(type, keyword);
      if (!mounted) return;
      setState(() {
        _results[type] = list;
        _loading[type] = false;
      });
    } on SubtitleSiteException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading[type] = false;
        _errors[type] = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading[type] = false;
        _errors[type] = '$e';
      });
    }
  }

  // ============================================================
  // 点击结果
  // ============================================================

  Future<void> _onTapResult(SubtitleSearchResult item) async {
    // SubHD 且有 groupId：先拉作品全部字幕让用户选
    if (item.site == SubtitleSiteType.subhd && item.groupId != null) {
      await _handleSubhdGroup(item);
      return;
    }
    await _doDownload(item);
  }

  /// SubHD：先拉 /d/{groupId} 拿全部字幕，弹二级选择
  Future<void> _handleSubhdGroup(SubtitleSearchResult item) async {
    SmartDialog.showLoading(msg: '加载字幕列表...');
    List<SubtitleSearchResult>? list;
    try {
      list = await _manager.fetchSubhdGroup(item.groupId!);
    } catch (_) {
      list = null;
    }
    if (!mounted) return;
    SmartDialog.dismiss();

    // 拉不到 → 降级直接下载原条目
    if (list == null || list.isEmpty) {
      await _doDownload(item);
      return;
    }
    // 只有一条 → 直接下载
    if (list.length == 1) {
      await _doDownload(list.first);
      return;
    }
    // 多条 → 弹选择
    final picked = await _pickFromList(
      list,
      '${item.title} · 共 ${list.length} 条字幕',
    );
    if (picked != null && mounted) {
      await _doDownload(picked);
    }
  }

  Future<void> _doDownload(SubtitleSearchResult item) async {
    SmartDialog.showLoading(msg: '下载中...');
    try {
      final result = await _manager.download(item);
      SmartDialog.dismiss();
      if (!mounted) return;
      if (result.files.isEmpty) {
        SmartDialog.showToast('该字幕包内没有可用的字幕文件');
        return;
      }
      if (result.files.length == 1) {
        await _mountSubtitle(result.files.first);
      } else {
        await _pickAndMount(result.files);
      }
    } on SubtitleSiteException catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast(e.message);
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('下载失败：$e');
    }
  }

  // ============================================================
  // 二级选择对话框（选一条字幕）
  // ============================================================

  Future<SubtitleSearchResult?> _pickFromList(
    List<SubtitleSearchResult> list,
    String title,
  ) async {
    final ctx = Get.context;
    if (ctx == null) return null;
    return showDialog<SubtitleSearchResult>(
      context: ctx,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                    itemBuilder: (_, i) {
                      final r = list[i];
                      final chips = <Widget>[];
                      if (r.language != null && r.language!.isNotEmpty) {
                        chips.add(_chip(r.language!, cs));
                      }
                      if (r.format != null && r.format!.isNotEmpty) {
                        chips.add(_chip(r.format!, cs));
                      }
                      return InkWell(
                        onTap: () => Navigator.of(dialogCtx).pop(r),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (r.subtitle != null &&
                                  r.subtitle!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  r.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.outline,
                                  ),
                                ),
                              ],
                              if (chips.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: chips,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // 多文件选择对话框（下载后有多文件时）
  // ============================================================

  Future<void> _pickAndMount(List<SubtitleFile> files) async {
    final ctx = Get.context;
    if (ctx == null) return;

    final picked = await showDialog<SubtitleFile>(
      context: ctx,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '选择字幕文件（共 ${files.length} 个）',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: files.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                    itemBuilder: (_, i) {
                      final f = files[i];
                      return InkWell(
                        onTap: () => Navigator.of(dialogCtx).pop(f),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      await _mountSubtitle(picked);
    }
  }

  Future<void> _mountSubtitle(SubtitleFile file) async {
    final content = decodeSubtitleBytes(file.bytes);
    await widget.controller.addSubtitleFromContent(
      content: content,
      name: file.name,
      ext: file.ext,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    _searchCtrl.dispose();
    _manager.dispose();
    super.dispose();
  }

  // ============================================================
  // UI
  // ============================================================

  bool get _isCurrentLoading {
    final ctrl = _tabCtrl;
    if (ctrl == null) return false;
    return _loading[_sites[ctrl.index].type] == true;
  }

  void _onSearchButtonPressed() {
    final ctrl = _tabCtrl;
    if (ctrl == null) return;
    final type = _sites[ctrl.index].type;
    _results.remove(type);
    _search(type);
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
        child: _sites.isEmpty ? _buildEmpty(cs) : _buildContent(cs),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Column(
      children: [
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
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.subtitles_off_outlined,
                    size: 40,
                    color: cs.outline,
                  ),
                  const SizedBox(height: 8),
                  const Text('未启用任何字幕网站'),
                  const SizedBox(height: 4),
                  Text(
                    '请先在「设置 → 字幕网站」中启用至少一个来源',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(ColorScheme cs) {
    final ctrl = _tabCtrl!;
    return Column(
      children: [
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
          child: Row(
            children: [
              Icon(Icons.subtitles_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              const Text(
                '搜索字幕',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: '输入影片名搜索字幕...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (_) => _onSearchButtonPressed(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed:
                    _isCurrentLoading ? null : _onSearchButtonPressed,
                icon: _isCurrentLoading
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
        TabBar(
          controller: ctrl,
          tabs: _sites.map((s) => Tab(text: s.type.displayName)).toList(),
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: ctrl,
            children: _sites.map((s) => _buildTab(cs, s.type)).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(
            '提示：点击字幕直接下载并挂载，仅对当前视频生效',
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
        ),
      ],
    );
  }

  Widget _buildTab(ColorScheme cs, SubtitleSiteType type) {
    final list = _results[type];
    final loading = _loading[type] == true;
    final error = _errors[type];
    final shownKeyword = _actualKeywords[type] ?? _searchCtrl.text.trim();

    return Column(
      children: [
        if (list != null && !loading && error == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '关键词「$shownKeyword」',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
                ),
                Text(
                  '${list.length} 条',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ],
            ),
          ),
        Expanded(
          child: _buildTabBody(cs, type, list, loading, error),
        ),
      ],
    );
  }

  Widget _buildTabBody(
    ColorScheme cs,
    SubtitleSiteType type,
    List<SubtitleSearchResult>? list,
    bool loading,
    String? error,
  ) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: cs.outline),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.outline),
              ),
            ],
          ),
        ),
      );
    }
    if (list == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 40, color: cs.outline),
              const SizedBox(height: 8),
              Text(
                '输入关键词后点击搜索',
                style: TextStyle(color: cs.outline),
              ),
              if (type == SubtitleSiteType.xunlei) ...[
                const SizedBox(height: 8),
                Text(
                  '剧集带集号（如「越狱 S01E12」）\n电影带年份（如「奥本海默 2023」）\n番号直接输入（如「ADN-773」）',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: cs.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (list.isEmpty) {
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
            if (type == SubtitleSiteType.xunlei) ...[
              const SizedBox(height: 8),
              Text(
                '迅雷看看对关键词敏感，\n建议剧集带集号、电影带年份',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ],
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildItem(cs, list[i]),
    );
  }

  Widget _buildItem(ColorScheme cs, SubtitleSearchResult r) {
    final chips = <Widget>[];
    if (r.language != null && r.language!.isNotEmpty) {
      chips.add(_chip(r.language!, cs));
    }
    if (r.format != null && r.format!.isNotEmpty) {
      chips.add(_chip(r.format!, cs));
    }

    // SubHD 有 groupId 时显示"查看全部"提示
    final hasGroup =
        r.site == SubtitleSiteType.subhd && r.groupId != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _onTapResult(r),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                          height: 1.3,
                        ),
                      ),
                      if (r.subtitle != null && r.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          r.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.outline,
                            height: 1.3,
                          ),
                        ),
                      ],
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: chips,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  hasGroup ? '查看' : '下载',
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