// lib/modules/novel/views/novel_reader_page.dart
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:json5/json5.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/modules/novel/utils/html_text.dart';
import 'package:yuanying/modules/novel/utils/purify.dart';
import 'package:yuanying/modules/novel/settings/novel_reader_settings.dart';
import 'package:yuanying/modules/novel/services/novel_tts_service.dart';
import 'package:yuanying/modules/novel/widgets/chapter_sheet.dart';
import 'package:yuanying/modules/novel/widgets/inbook_search_sheet.dart';
import 'package:yuanying/modules/novel/widgets/bookmark_sheet.dart';
import 'package:yuanying/modules/novel/widgets/purify_sheet.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/modules/novel/services/novel_font_service.dart';

class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({super.key});

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> with WidgetsBindingObserver {
  // 参数
  late String _vodId;
  late String _vodName;
  late String _vodPic;
  late List<Episode> _episodes;
  late int _initialChapter;
  late String _pwd;
  late Map<String, dynamic>? _site;
  late String _sourceName;

  // 服务
  late ISpiderService _apiService;
  late NovelTtsService _ttsService;

  // 阅读状态
  List<String> _titles = [];
  int _index = 0;
  String _content = '';
  bool _loading = true;
  String? _error;
  bool _toolbar = false;
  double _pendingRestore = -1;
  int? _pendingSearchHit;

  // 分页模式
  bool get _paged => NovelReaderSettings.pagedMode;
  PageController? _pageCtrl;
  List<_PageUnit> _pageUnits = const [];
  String _pagedJoined = '';
  int _pageIndex = 0;
  bool _pagedReady = false;
  bool _paginating = false;
  bool _pendingJumpLast = false;
  Object? _pageKey;

  // 滚动控制器（非分页模式）
  final ScrollController _scroll = ScrollController();

  // 听书
  bool _ttsActive = false;
  Timer? _sleepTimer;
  int _sleepMinutes = 0;
  Future<List<Map<String, String>>>? _voicesFuture;

  // 页脚状态
  final Battery _battery = Battery();
  Timer? _footerTimer;
  int _batteryLevel = -1;
  Timer? _statTimer;

  // 书签
  List<NovelBookmark> _bookmarks = [];

  // 净化规则
  List<Map<String, dynamic>> _purifyRules = [];

  // 字体下载状态
  final Set<String> _downloadingFonts = {};

  // 阅读主题（使用 yuedu 主题系统）
  NovelReaderTheme get _theme => NovelReaderTheme.getThemeByIndex(NovelReaderSettings.themeIndex);

  @override
  void initState() {
    super.initState();
    _ttsService = Get.find<NovelTtsService>();
    WidgetsBinding.instance.addObserver(this);
    final args = Get.arguments as Map?;
    _vodId = args?['vodId']?.toString() ?? '';
    _vodName = args?['vodName']?.toString() ?? '未命名';
    _vodPic = args?['vodPic']?.toString() ?? '';
    _initialChapter = args?['initialChapter'] as int? ?? 0;
    _pwd = args?['pwd']?.toString() ?? 'tinydust';
    _site = args?['site'] as Map<String, dynamic>?;
    _sourceName = args?['sourceName']?.toString() ?? '';
    final episodesData = args?['episodes'] as List?;
    if (episodesData != null) {
      _episodes = episodesData.map((e) => Episode(
        name: e['name']?.toString() ?? '',
        url: e['url']?.toString() ?? '',
      )).toList();
    } else {
      _episodes = [];
    }
    _apiService = _site != null
        ? Get.find<SourceManager>().createIndependentService(_site!)
        : Get.find<SourceManager>().currentApiService;
    _index = _initialChapter.clamp(0, _episodes.length - 1);
    if (_episodes.isEmpty) {
      _error = '没有章节';
      _loading = false;
    } else {
      _titles = _episodes.map((e) => e.name).toList();
      _loadBookmarks();
      _loadPurifyRules();
      _loadChapter(_index);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _refreshBattery();
    _footerTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshBattery());
    _statTimer = Timer.periodic(const Duration(seconds: 30), (_) {});
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _sleepTimer?.cancel();
    _footerTimer?.cancel();
    _statTimer?.cancel();
    _saveProgress();
    _scroll.dispose();
    _pageCtrl?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 安全返回方法（先停TTS再退出）
  Future<void> _onBackPressed() async {
    if (_ttsActive) {
      _ttsActive = false;
      await _ttsService.stop();
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _refreshBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) setState(() => _batteryLevel = level);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveProgress();
    }
  }

  String _cleanJsonString(String raw) {
    var s = raw.trim();
    while (s.startsWith('/') || s.startsWith('\\')) {
      s = s.substring(1);
    }
    if (s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    return s;
  }

  // ---------- 书签 ----------
  void _loadBookmarks() {
    final key = '${SettingBoxKey.novelBookmarksPrefix}$_vodId';
    final data = StorageManager.getCache<List>(key);
    if (data != null) {
      _bookmarks = data.map((e) => NovelBookmark.fromMap(Map<String, dynamic>.from(e as Map))).toList();
      _bookmarks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
  }

  void _saveBookmarks() {
    final key = '${SettingBoxKey.novelBookmarksPrefix}$_vodId';
    final list = _bookmarks.map((b) => b.toMap()).toList();
    StorageManager.setCache(key, list);
  }

  void _addBookmark() {
    if (_content.isEmpty || _titles.isEmpty) {
      SmartDialog.showToast('当前无内容可记录');
      return;
    }
    double offset = 0;
    if (_paged && _pagedReady && _pageUnits.length > 1) {
      offset = _pageIndex / (_pageUnits.length - 1);
    } else if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      offset = _scroll.position.pixels / _scroll.position.maxScrollExtent;
    }
    final bookmark = NovelBookmark(
      chapter: _index,
      chapterTitle: _titles[_index],
      offset: offset,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _bookmarks.removeWhere((b) => b.chapter == _index);
    _bookmarks.add(bookmark);
    _saveBookmarks();
    SmartDialog.showToast('已添加书签：${_titles[_index]}');
  }

  void _showBookmarks() async {
    if (_bookmarks.isEmpty) {
      SmartDialog.showToast('暂无书签');
      return;
    }
    await showBookmarkSheet(
      context,
      bookmarks: _bookmarks,
      currentChapter: _index,
      onJump: (chapter, offset) {
        _pendingRestore = offset;
        if (chapter != _index) {
          _loadChapter(chapter);
        } else {
          // 同一章节直接恢复
          if (!_paged) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scroll.hasClients) return;
              final max = _scroll.position.maxScrollExtent;
              if (max > 0) _scroll.jumpTo(max * offset);
            });
          }
          if (_paged && _pagedReady) {
            final target = (offset * (_pageUnits.length - 1)).round().clamp(0, _pageUnits.length - 1);
            _pageCtrl?.jumpToPage(target);
            setState(() => _pageIndex = target);
          }
        }
      },
      onDelete: (bookmark) async {
        _bookmarks.removeWhere((b) => b.chapter == bookmark.chapter && b.createdAt == bookmark.createdAt);
        _saveBookmarks();
        SmartDialog.showToast('已删除书签');
      },
    );
  }

  // ---------- 净化规则 ----------
  void _loadPurifyRules() {
    final key = '${SettingBoxKey.novelPurifyRulesPrefix}$_vodId';
    final data = StorageManager.getCache<String>(key);
    if (data != null && data.isNotEmpty) {
      try {
        final list = jsonDecode(data) as List;
        _purifyRules = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        _purifyRules = [];
      }
    } else {
      _purifyRules = [];
    }
  }

  void _showPurifySheet() async {
    final newRules = await showPurifySheet(
      context,
      rules: _purifyRules,
      onSave: (rules) async {
        _purifyRules = rules;
        final key = '${SettingBoxKey.novelPurifyRulesPrefix}$_vodId';
        await StorageManager.setCache(key, jsonEncode(rules));
        await _loadChapter(_index);
      },
    );
  }

  // ---------- 章节内容加载 ----------
  Future<void> _loadChapter(int idx) async {
    if (idx < 0 || idx >= _episodes.length) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cacheKey = 'novel_chapter_${_vodId}_$idx';
      String text = StorageManager.getCache<String>(cacheKey) ?? '';
      if (text.isEmpty) {
        final playUrl = await _apiService.getPlayUrl(
          playParams: _episodes[idx].url,
          flag: _sourceName,
          pwd: _pwd,
        );
        if (playUrl == null) {
          SmartDialog.showToast('获取播放地址失败');
          setState(() {
            _loading = false;
            _error = '获取播放地址失败';
          });
          return;
        }
        final url = playUrl.defaultUrl;
        if (url == null || url.isEmpty) {
          SmartDialog.showToast('播放地址为空');
          setState(() {
            _loading = false;
            _error = '播放地址为空';
          });
          return;
        }
        if (!url.startsWith('novel://')) {
          SmartDialog.showToast('非小说协议');
          setState(() {
            _loading = false;
            _error = '不支持该协议';
          });
          return;
        }
        String jsonStr = url.substring(7);
        String cleaned = _cleanJsonString(jsonStr);
        Map<String, dynamic>? data;
        try {
          data = JSON5.parse(cleaned) as Map<String, dynamic>;
        } catch (e) {
          SmartDialog.showToast('解析章节内容失败: $e');
          setState(() {
            _loading = false;
            _error = '解析失败';
          });
          return;
        }
        if (data == null) {
          SmartDialog.showToast('解析结果为空');
          setState(() {
            _loading = false;
            _error = '解析结果为空';
          });
          return;
        }
        text = data['content']?.toString() ?? data['body']?.toString() ?? data['text']?.toString() ?? '';
        if (text.isEmpty) {
          SmartDialog.showToast('章节内容为空');
          setState(() {
            _loading = false;
            _error = '章节内容为空';
          });
          return;
        }
        StorageManager.setCache(cacheKey, text);
      }

      // ---------- 应用净化规则 ----------
      if (_purifyRules.isNotEmpty) {
        text = applyReplaceRules(text, jsonEncode(_purifyRules));
      }

      if (mounted) {
        setState(() {
          _content = text;
          _index = idx;
          _pageIndex = 0;
          _pagedReady = false;
          _pageUnits = const [];
          _pageKey = null;
          _loading = false;
          _toolbar = false;
        });
        if (_pendingRestore > 0) {
          final ratio = _pendingRestore.clamp(0.0, 1.0);
          _pendingRestore = -1;
          if (!_paged) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scroll.hasClients) return;
              final max = _scroll.position.maxScrollExtent;
              if (max > 0) _scroll.jumpTo(max * ratio);
            });
          }
        }
        if (_pendingSearchHit != null) {
          _applySearchHit();
        }
        _saveProgress();
      }
    } catch (e) {
      SmartDialog.showToast('加载章节异常: $e');
      if (mounted) {
        setState(() {
          _error = '加载章节异常: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveProgress() async {
    final key = 'novel_progress_$_vodId';
    double offset = 0;
    if (_paged && _pagedReady && _pageUnits.length > 1) {
      offset = _pageIndex / (_pageUnits.length - 1);
    } else if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      offset = _scroll.position.pixels / _scroll.position.maxScrollExtent;
    }
    final progress = {'chapter': _index, 'offset': offset};
    await StorageManager.setCache(key, progress);
  }

  void _nextChapter() {
    if (_index < _episodes.length - 1) {
      _loadChapter(_index + 1);
    } else {
      SmartDialog.showToast('已经是最后一章');
    }
  }

  void _prevChapter() {
    if (_index > 0) {
      _loadChapter(_index - 1);
    } else {
      SmartDialog.showToast('已经是第一章');
    }
  }

  // ---------- 手势翻页 ----------
  void _handleTapZone(TapUpDetails details) {
    if (_loading) return;
    final size = MediaQuery.sizeOf(context);
    final col = details.localPosition.dx / size.width;
    final row = details.localPosition.dy / size.height;
    final x = col < 1 / 3 ? 0 : (col < 2 / 3 ? 1 : 2);
    final y = row < 1 / 3 ? 0 : (row < 2 / 3 ? 1 : 2);
    if (x == 1 && y == 1) {
      _toggleToolbar();
      return;
    }
    if (x == 0 || (x == 1 && y == 0)) {
      _prevPage();
      return;
    }
    _nextPage();
  }

  double get _pageStep {
    if (!_scroll.hasClients) return 600;
    final d = _scroll.position.viewportDimension;
    final line = NovelReaderSettings.fontSize * NovelReaderSettings.lineHeight;
    final step = d - line;
    return step > d * 0.7 ? step : d * 0.7;
  }

  void _nextPage() {
    if (_paged) {
      _pagedNext();
      return;
    }
    if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      final pos = _scroll.position;
      if (pos.maxScrollExtent - pos.pixels > _pageStep * 0.5) {
        final target = (pos.pixels + _pageStep).clamp(0.0, pos.maxScrollExtent);
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
        return;
      }
    }
    _nextChapter();
  }

  void _prevPage() {
    if (_paged) {
      _pagedPrev();
      return;
    }
    if (_scroll.hasClients && _scroll.position.pixels > 2) {
      final pos = _scroll.position;
      final target = (pos.pixels - _pageStep).clamp(0.0, pos.maxScrollExtent);
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      return;
    }
    _prevChapter();
  }

  // ---------- 分页模式 ----------
  void _pagedNext() {
    final n = _pageUnits.length;
    if (!_pagedReady || n == 0) return;
    if (_pageIndex < n - 1) {
      final ctrl = _pageCtrl;
      if (ctrl != null && ctrl.hasClients) {
        ctrl.animateToPage(_pageIndex + 1,
            duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
      }
    } else {
      _pageIndex = 0;
      _nextChapter();
    }
  }

  void _pagedPrev() {
    if (!_pagedReady) return;
    if (_pageIndex > 0) {
      final ctrl = _pageCtrl;
      if (ctrl != null && ctrl.hasClients) {
        ctrl.animateToPage(_pageIndex - 1,
            duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
      }
    } else if (_index > 0) {
      _pendingJumpLast = true;
      _prevChapter();
    } else {
      SmartDialog.showToast('已经是第一章');
    }
  }

  void _schedulePaginate(Size area, Object key) {
    if (_paginating) return;
    _paginating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final text = _joinedText;
      final cuts = _computeCuts(area, text);
      final units = <_PageUnit>[];
      for (int i = 0; i < cuts.length; i++) {
        final s = cuts[i];
        final e = (i + 1 < cuts.length) ? cuts[i + 1] : text.length;
        if (s < e) units.add(_PageUnit.text(s, e));
      }
      if (units.isEmpty) units.add(const _PageUnit.text(0, 0));
      int target = 0;
      if (_pendingRestore > 0 && units.length > 1) {
        target = (_pendingRestore * (units.length - 1)).round().clamp(0, units.length - 1);
        _pendingRestore = -1;
      } else if (_pendingJumpLast) {
        target = units.length - 1;
        _pendingJumpLast = false;
      } else {
        target = _pageIndex.clamp(0, units.length - 1);
      }
      if (!mounted) return;
      setState(() {
        _pageKey = key;
        _pageUnits = units;
        _pagedJoined = text;
        _pageIndex = target;
        _pagedReady = true;
        _paginating = false;
        _pageCtrl?.dispose();
        _pageCtrl = PageController(initialPage: target);
      });
      if (_pendingSearchHit != null) {
        final off = _pendingSearchHit!;
        _pendingSearchHit = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpToOffsetInPage(off);
        });
      }
    });
  }

  List<int> _computeCuts(Size area, String text) {
    final padH = NovelReaderSettings.pagePadding * 2;
    const headerH = 52.0;
    const footerH = 44.0;
    final w = area.width - padH - 2;
    final hAvail = area.height - headerH - footerH;
    final style = NovelReaderSettings.applyTextStyle(TextStyle(
      fontSize: NovelReaderSettings.fontSize,
      height: NovelReaderSettings.lineHeight,
    ));
    if (text.isEmpty || w <= 0 || hAvail <= 0) return const [0];
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: w);
    final metrics = tp.computeLineMetrics();
    if (metrics.isEmpty) return const [0];
    final starts = <int>[];
    double y = 0;
    for (final m in metrics) {
      final pos = tp.getPositionForOffset(Offset(m.left, y + m.height / 2));
      starts.add(pos.offset);
      y += m.height;
    }
    final cuts = <int>[0];
    double used = 0;
    for (int li = 0; li < metrics.length; li++) {
      final h = metrics[li].height;
      if (li > 0 && used + h > hAvail) {
        if (cuts.last != starts[li]) cuts.add(starts[li]);
        used = 0;
      }
      used += h;
    }
    if (cuts.last < text.length) cuts.add(text.length);
    return cuts;
  }

  String get _joinedText {
    final gap = NovelReaderSettings.paragraphGap;
    final sep = gap <= 2 ? '\n' : (gap >= 20 ? '\n\n\n' : '\n\n');
    return _content.split('\n')
        .where((p) => p.trim().isNotEmpty)
        .map((p) => p.trim())
        .join(sep);
  }

  // ============================================================================
  // 翻页动画系统（移植自 yuedu 项目，5种动画模式）
  // ============================================================================
  Widget _pageTransform(int i, Widget child) {
    final mode = NovelPageTurnModeExt.fromStorageKey(NovelReaderSettings.pageAnim);
    if (mode == NovelPageTurnMode.none) return child;
    final ctrl = _pageCtrl;
    if (ctrl == null) return child;

    return AnimatedBuilder(
      animation: ctrl,
      builder: (ctx, c) {
        double delta = 0;
        if (ctrl.hasClients && ctrl.position.hasContentDimensions) {
          final page = ctrl.page ?? ctrl.initialPage.toDouble();
          delta = (i - page).clamp(-1.0, 1.0);
        }
        if (delta.abs() < 0.001) return c!;

        switch (mode) {
          case NovelPageTurnMode.cover:
            return _buildCoverAnimation(c!, delta);
          case NovelPageTurnMode.simulation:
            return _buildSimulationAnimation(c!, delta);
          case NovelPageTurnMode.slide:
            return _buildSlideAnimation(c!, delta);
          case NovelPageTurnMode.scroll:
            return _buildScrollAnimation(c!, delta);
          default:
            return c!;
        }
      },
      child: child,
    );
  }

  // ----- 覆盖动画 -----
  Widget _buildCoverAnimation(Widget child, double delta) {
    final absDelta = delta.abs();
    return ClipRect(
      child: Align(
        alignment: delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
        widthFactor: 1 - absDelta,
        child: child,
      ),
    );
  }

  // ----- 仿真翻页（3D旋转）-----
  Widget _buildSimulationAnimation(Widget child, double delta) {
    final absDelta = delta.abs();
    final angle = (delta > 0 ? -1 : 1) * absDelta * 3.1415926 * 0.36;
    return Transform(
      alignment: delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0015)
        ..rotateY(angle),
      child: Opacity(
        opacity: (1 - absDelta * 0.3).clamp(0.3, 1.0),
        child: child,
      ),
    );
  }

  // ----- 滑动动画 -----
  Widget _buildSlideAnimation(Widget child, double delta) {
    final absDelta = delta.abs();
    return Transform.translate(
      offset: Offset(
        (delta > 0 ? -1 : 1) * absDelta * 60,
        0,
      ),
      child: Opacity(
        opacity: (1 - absDelta * 0.4).clamp(0.2, 1.0),
        child: child,
      ),
    );
  }

  // ----- 滚动动画 -----
  Widget _buildScrollAnimation(Widget child, double delta) {
    final absDelta = delta.abs();
    return Transform.translate(
      offset: Offset(0, (delta > 0 ? -1 : 1) * absDelta * 40),
      child: Opacity(
        opacity: (1 - absDelta * 0.3).clamp(0.3, 1.0),
        child: child,
      ),
    );
  }

  // ---------- 搜索跳转辅助 ----------
  void _applySearchHit() {
    final off = _pendingSearchHit;
    if (off == null) return;
    if (_paged) {
      if (_pagedReady && !_paginating) {
        _pendingSearchHit = null;
        _jumpToOffsetInPage(off);
      }
    } else {
      _pendingSearchHit = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        if (max > 0 && _content.isNotEmpty) {
          final ratio = (off / _content.length).clamp(0.0, 1.0);
          _scroll.jumpTo(max * ratio);
        }
      });
    }
  }

  void _jumpToOffsetInPage(int off) {
    for (int i = 0; i < _pageUnits.length; i++) {
      final u = _pageUnits[i];
      if (u.isImage) continue;
      if (off >= u.start && off < u.end) {
        final ctrl = _pageCtrl;
        if (ctrl != null && ctrl.hasClients) ctrl.jumpToPage(i);
        setState(() => _pageIndex = i);
        return;
      }
    }
  }

  // ---------- 工具栏 ----------
  void _toggleToolbar() {
    setState(() => _toolbar = !_toolbar);
    SystemChrome.setEnabledSystemUIMode(
      _toolbar ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  // ---------- 目录 ----------
  void _openToc() async {
    final picked = await showChapterSheet(
      context,
      titles: _titles,
      current: _index,
    );
    if (picked != null && picked != _index) {
      _loadChapter(picked);
    }
  }

  // ---------- 书内搜索 ----------
  Future<void> _openSearchSheet() async {
    if (_titles.isEmpty || _loading) return;
    final indexes = List.generate(_episodes.length, (i) => i);
    await showInBookSearchSheet(
      context,
      searchableChapters: indexes,
      titles: _titles,
      chapterText: (i) async {
        final cacheKey = 'novel_chapter_${_vodId}_$i';
        final cached = StorageManager.getCache<String>(cacheKey);
        if (cached != null) return cached;
        final playUrl = await _apiService.getPlayUrl(
          playParams: _episodes[i].url,
          flag: _sourceName,
          pwd: _pwd,
        );
        if (playUrl != null) {
          final url = playUrl.defaultUrl;
          if (url != null && url.startsWith('novel://')) {
            final jsonStr = url.substring(7);
            try {
              final data = JSON5.parse(jsonStr) as Map<String, dynamic>;
              return data['content']?.toString() ?? '';
            } catch (_) {}
          }
        }
        return '';
      },
      onJump: (chapter, offset) {
        _pendingSearchHit = offset;
        if (chapter == _index) {
          _applySearchHit();
        } else {
          _loadChapter(chapter);
        }
      },
    );
  }

  // ---------- 听书 ----------
  List<String> _chunksOf(String text) {
    final chunks = <String>[];
    for (final p0 in text.split('\n')) {
      var p = p0.trim();
      if (p.isEmpty) continue;
      while (p.length > 260) {
        var cut = 260;
        final punct = p.lastIndexOf(RegExp(r'[。！？；]'), 260);
        if (punct > 100) cut = punct + 1;
        chunks.add(p.substring(0, cut));
        p = p.substring(cut);
      }
      if (p.isNotEmpty) chunks.add(p);
    }
    return chunks;
  }

  int _ttsStartChunkIndex(int total) {
    if (total <= 1) return 0;
    double ratio = 0;
    if (_paged && _pagedReady && _pageUnits.length > 1) {
      ratio = _pageIndex / (_pageUnits.length - 1);
    } else if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      ratio = _scroll.position.pixels / _scroll.position.maxScrollExtent;
    }
    return (ratio * total).floor().clamp(0, total - 1);
  }

  Future<void> _startTts() async {
    if (_ttsActive || _content.isEmpty) return;
    setState(() => _ttsActive = true);
    while (_ttsActive && mounted) {
      var chunks = _chunksOf(_content);
      final startIdx = _ttsStartChunkIndex(chunks.length);
      if (startIdx > 0 && startIdx < chunks.length) {
        chunks = chunks.sublist(startIdx);
      }
      if (chunks.isEmpty) break;
      await _ttsService.speakChunks(
        chunks,
        isCancelled: () => !_ttsActive,
      );
      if (!_ttsActive || !mounted) break;
      if (_index < _episodes.length - 1) {
        _nextChapter();
        while (_loading && _ttsActive && mounted) {
          await Future.delayed(const Duration(milliseconds: 120));
        }
      } else {
        break;
      }
    }
    if (mounted) setState(() => _ttsActive = false);
  }

  void _stopTts() {
    _sleepTimer?.cancel();
    _sleepMinutes = 0;
    if (_ttsActive) {
      _ttsActive = false;
      _ttsService.stop();
    }
    if (mounted) setState(() {});
  }

  void _setSleepTimer(int minutes, void Function(void Function()) setSheet) {
    _sleepTimer?.cancel();
    _sleepMinutes = minutes;
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), _stopTts);
    }
    setSheet(() {});
    setState(() {});
  }

  void _showTtsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '听书',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _ttsActive ? '正在朗读 第 ${_index + 1} 章' : '未在朗读',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: () {
                        if (_ttsActive) {
                          _stopTts();
                        } else {
                          _startTts();
                        }
                        setSheet(() {});
                      },
                      icon: Icon(_ttsActive ? Icons.stop : Icons.play_arrow),
                      label: Text(_ttsActive ? '停止朗读' : '开始朗读'),
                    ),
                  ),
                  Row(
                    children: [
                      const Text('语速', style: TextStyle(fontSize: 13.5)),
                      Expanded(
                        child: Slider(
                          value: _ttsService.rate,
                          min: 0.3,
                          max: 1.0,
                          divisions: 14,
                          onChanged: (v) {
                            _ttsService.setRate(v);
                            setSheet(() {});
                          },
                        ),
                      ),
                      Text(
                        _ttsService.rate.toStringAsFixed(2),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('音色', style: TextStyle(fontSize: 13.5)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: FutureBuilder<List<Map<String, String>>>(
                          future: _voicesFuture ??= _ttsService.voices(),
                          builder: (ctx, snap) {
                            final voices = snap.data ?? const [];
                            if (voices.isEmpty) {
                              return Text(
                                snap.connectionState == ConnectionState.done
                                    ? '系统默认'
                                    : '加载中…',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Theme.of(ctx).colorScheme.outline,
                                ),
                              );
                            }
                            String keyOf(Map<String, String> v) =>
                                '${v['name']}|${v['locale']}';
                            final current = _ttsService.voiceKey;
                            final valid = current != null &&
                                voices.any((v) => keyOf(v) == current);
                            return DropdownButton<String>(
                              value: valid ? current : null,
                              hint: const Text('系统默认'),
                              isExpanded: true,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final v in voices)
                                  DropdownMenuItem(
                                    value: keyOf(v),
                                    child: Text(
                                      '${v['name']}（${v['locale']}）',
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (key) async {
                                if (key == null) return;
                                await _ttsService.setVoice(key);
                                setSheet(() {});
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('定时', style: TextStyle(fontSize: 13.5)),
                      const SizedBox(width: 14),
                      for (final m in [0, 15, 30, 60])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              m == 0 ? '关' : '$m分',
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: _sleepMinutes == m,
                            onSelected: (_) => _setSleepTimer(m, setSheet),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------- 阅读设置 ----------
  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            void refresh() {
              setSheet(() {});
              setState(() {});
              NovelReaderSettings.save();
            }
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---- 字号 ----
                    Row(
                      children: [
                        const Text('字号', style: TextStyle(fontSize: 13.5)),
                        Expanded(
                          child: Slider(
                            value: NovelReaderSettings.fontSize,
                            min: 14,
                            max: 32,
                            divisions: 18,
                            onChanged: (v) {
                              NovelReaderSettings.fontSize = v;
                              refresh();
                            },
                          ),
                        ),
                        Text(
                          '${NovelReaderSettings.fontSize.round()}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    // ---- 行距 ----
                    Row(
                      children: [
                        const Text('行距', style: TextStyle(fontSize: 13.5)),
                        Expanded(
                          child: Slider(
                            value: NovelReaderSettings.lineHeight,
                            min: 1.3,
                            max: 2.8,
                            divisions: 15,
                            onChanged: (v) {
                              NovelReaderSettings.lineHeight = v;
                              refresh();
                            },
                          ),
                        ),
                        Text(
                          NovelReaderSettings.lineHeight.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    // ---- 段距 ----
                    Row(
                      children: [
                        const Text('段距', style: TextStyle(fontSize: 13.5)),
                        Expanded(
                          child: Slider(
                            value: NovelReaderSettings.paragraphGap,
                            min: 0,
                            max: 28,
                            divisions: 14,
                            onChanged: (v) {
                              NovelReaderSettings.paragraphGap = v;
                              refresh();
                            },
                          ),
                        ),
                        Text(
                          '${NovelReaderSettings.paragraphGap.round()}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    // ---- 字体 ----
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('字体', style: TextStyle(fontSize: 13.5)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final f in [
                                ('system', '默认'),
                                ('serif', '宋体'),
                                ('kai', '楷体'),
                                ('round', '圆体'),
                                ('hei', '黑体'),
                              ])
                                ChoiceChip(
                                  label: Text(
                                    f.$2,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                  selected: NovelReaderSettings.fontKey == f.$1,
                                  onSelected: (_) {
                                    NovelReaderSettings.fontKey = f.$1;
                                    refresh();
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // ---- 在线字体 ----
                    const Divider(height: 20, indent: 0, endIndent: 0),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Row(
                        children: [
                          const Text('在线字体', style: TextStyle(fontSize: 13.5)),
                          const SizedBox(width: 8),
                          Text(
                            '点击下载后自动应用',
                            style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final font in kDownloadableFonts)
                          _buildDownloadableFontChip(ctx, font, setSheet),
                      ],
                    ),
                    // ---- 字距 ----
                    Row(
                      children: [
                        const Text('字距', style: TextStyle(fontSize: 13.5)),
                        Expanded(
                          child: Slider(
                            value: NovelReaderSettings.letterSpacing,
                            min: 0,
                            max: 4,
                            divisions: 8,
                            onChanged: (v) {
                              NovelReaderSettings.letterSpacing = v;
                              refresh();
                            },
                          ),
                        ),
                        Text(
                          NovelReaderSettings.letterSpacing.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    // ---- 边距 ----
                    Row(
                      children: [
                        const Text('边距', style: TextStyle(fontSize: 13.5)),
                        Expanded(
                          child: Slider(
                            value: NovelReaderSettings.pagePadding,
                            min: 8,
                            max: 48,
                            divisions: 20,
                            onChanged: (v) {
                              NovelReaderSettings.pagePadding = v;
                              refresh();
                            },
                          ),
                        ),
                        Text(
                          '${NovelReaderSettings.pagePadding.round()}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    // ---- 亮度 ----
                    Row(
                      children: [
                        const Text('亮度', style: TextStyle(fontSize: 13.5)),
                        Expanded(
                          child: Slider(
                            value: NovelReaderSettings.screenDim,
                            min: 0,
                            max: 0.6,
                            divisions: 12,
                            onChanged: (v) {
                              NovelReaderSettings.screenDim = v;
                              refresh();
                            },
                          ),
                        ),
                        Text(
                          NovelReaderSettings.screenDim == 0
                              ? '系统'
                              : '-${(NovelReaderSettings.screenDim * 100).round()}%',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    // ---- 翻页模式 ----
                    Row(
                      children: [
                        const Text('翻页模式', style: TextStyle(fontSize: 13.5)),
                        const SizedBox(width: 14),
                        ChoiceChip(
                          label: const Text('滚动'),
                          selected: !NovelReaderSettings.pagedMode,
                          onSelected: (_) {
                            NovelReaderSettings.pagedMode = false;
                            refresh();
                          },
                        ),
                        const SizedBox(width: 10),
                        ChoiceChip(
                          label: const Text('仿真分页'),
                          selected: NovelReaderSettings.pagedMode,
                          onSelected: (_) {
                            NovelReaderSettings.pagedMode = true;
                            refresh();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // ---- 翻页动画（5种）----
                    Row(
                      children: [
                        const Text('翻页动画', style: TextStyle(fontSize: 13.5)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: NovelPageTurnMode.values.map((mode) {
                              final isSelected = NovelReaderSettings.pageAnim == mode.storageKey;
                              return ChoiceChip(
                                label: Text(
                                  mode.displayName,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                                selected: isSelected,
                                onSelected: (_) {
                                  NovelReaderSettings.pageAnim = mode.storageKey;
                                  NovelReaderSettings.save();
                                  refresh();
                                },
                                selectedColor: Theme.of(ctx).colorScheme.primaryContainer,
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Theme.of(ctx).colorScheme.primary
                                      : Theme.of(ctx).colorScheme.onSurface,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    // ---- 阅读主题（11种，横向滚动预览）----
                    const SizedBox(height: 10),
                    const Divider(height: 20),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Row(
                        children: [
                          const Text('阅读主题', style: TextStyle(fontSize: 13.5)),
                          const SizedBox(width: 8),
                          Text(
                            NovelReaderTheme.getThemeByIndex(NovelReaderSettings.themeIndex).name,
                            style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      height: 120,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: NovelReaderTheme.allThemes.length,
                        itemBuilder: (ctx, i) {
                          final theme = NovelReaderTheme.getThemeByIndex(i);
                          final isSelected = NovelReaderSettings.themeIndex == i;
                          return GestureDetector(
                            onTap: () {
                              NovelReaderSettings.themeIndex = i;
                              NovelReaderSettings.save();
                              refresh();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 56,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: theme.backgroundColor,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? theme.primaryColor : Colors.transparent,
                                        width: 2.5,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: theme.primaryColor.withValues(alpha: 0.3),
                                                blurRadius: 8,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Aa',
                                          style: TextStyle(
                                            color: theme.textColor,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          theme.name,
                                          style: TextStyle(
                                            color: theme.textColor,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
      },
    );
  }

  // ---------- 构建 ----------
  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final hasContent = _content.isNotEmpty;
    final safePadding = MediaQuery.of(context).padding;

    return PopScope(
      canPop: !_ttsActive,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          await _onBackPressed();
        }
      },
      child: Scaffold(
        backgroundColor: theme.backgroundColor,
        body: Stack(
          children: [
            // ---------- 主体内容 ----------
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _handleTapZone,
                onHorizontalDragEnd: _paged ? null : (details) {
                  if (_loading || _episodes.length < 2) return;
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() < 350) return;
                  if (velocity < 0) _nextChapter();
                  else _prevChapter();
                },
                child: SafeArea(
                  bottom: false,
                  child: _error != null
                      ? _errorView(_error!, retry: () => _loadChapter(_index))
                      : !hasContent && _loading
                          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                          : _paged
                              ? _buildPagedArea(theme)
                              : SingleChildScrollView(
                                  controller: _scroll,
                                  padding: EdgeInsets.fromLTRB(
                                    NovelReaderSettings.pagePadding,
                                    20,
                                    NovelReaderSettings.pagePadding,
                                    160,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (_titles.isNotEmpty)
                                        Text(
                                          _titles[_index],
                                          style: TextStyle(
                                            fontSize: NovelReaderSettings.fontSize + 3,
                                            fontWeight: FontWeight.w600,
                                            color: theme.textColor,
                                            height: 1.5,
                                          ),
                                        ),
                                      const SizedBox(height: 20),
                                      if (_loading)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 40),
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              color: theme.primaryColor,
                                            ),
                                          ),
                                        )
                                      else if (_error != null)
                                        _errorView(_error!, retry: () => _loadChapter(_index))
                                      else
                                        ..._paragraphs(theme),
                                    ],
                                  ),
                                ),
                ),
              ),
            ),

            // ---------- 亮度遮罩 ----------
            if (NovelReaderSettings.screenDim > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: NovelReaderSettings.screenDim),
                  ),
                ),
              ),

            // ---------- 顶部栏（用 AnimatedContainer + Transform 避免定位冲突） ----------
            // 改动：用 Positioned + AnimatedContainer 代替 AnimatedPositioned
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: Matrix4.translationValues(0, _toolbar ? 0 : -100, 0),
                padding: EdgeInsets.only(
                  top: safePadding.top,
                  left: 8,
                  right: 8,
                  bottom: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.backgroundColor.withValues(alpha: 0.95),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 19),
                      color: theme.textColor,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      onPressed: _onBackPressed,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _vodName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.textColor,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_titles.isNotEmpty)
                            Text(
                              _titles[_index],
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textColor.withValues(alpha: 0.7),
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.bookmark_border,
                        color: theme.primaryColor,
                        size: 22,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      tooltip: '添加书签',
                      onPressed: _addBookmark,
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        color: theme.textColor,
                        size: 24,
                      ),
                      tooltip: '更多',
                      color: Theme.of(context).colorScheme.surface,
                      onSelected: (value) {
                        switch (value) {
                          case 'search':
                            _openSearchSheet();
                            break;
                          case 'bookmark_list':
                            _showBookmarks();
                            break;
                          case 'purify':
                            _showPurifySheet();
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'search',
                          child: Row(
                            children: [
                              Icon(Icons.search, size: 20),
                              SizedBox(width: 10),
                              Text('搜索'),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'bookmark_list',
                          child: Row(
                            children: [
                              Icon(Icons.bookmarks_outlined, size: 20),
                              SizedBox(width: 10),
                              Text('书签列表'),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'purify',
                          child: Row(
                            children: [
                              Icon(Icons.cleaning_services_outlined, size: 20),
                              SizedBox(width: 10),
                              Text('净化规则'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ---------- 底部栏（用 AnimatedContainer + Transform 避免定位冲突） ----------
            // 改动：用 Positioned + AnimatedContainer 代替 AnimatedPositioned
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: Matrix4.translationValues(0, _toolbar ? 0 : 160, 0),
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  12 + safePadding.bottom,
                ),
                decoration: BoxDecoration(
                  color: theme.backgroundColor.withValues(alpha: 0.95),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---- 第一行：上一章 | 进度条 | 下一章 ----
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _index > 0 ? () => _loadChapter(_index - 1) : null,
                          child: Text(
                            '上一章',
                            style: TextStyle(
                              fontSize: 14,
                              color: _index > 0
                                  ? theme.primaryColor
                                  : theme.textColor.withValues(alpha: 0.3),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Slider(
                            value: _titles.length > 1 ? _index.toDouble() : 0,
                            min: 0,
                            max: (_titles.length - 1).toDouble().clamp(0, double.infinity),
                            onChanged: (v) {
                              final target = v.round();
                              if (target != _index) _loadChapter(target);
                            },
                            activeColor: theme.primaryColor,
                            inactiveColor: theme.textColor.withValues(alpha: 0.2),
                            thumbColor: theme.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _index < _titles.length - 1
                              ? () => _loadChapter(_index + 1)
                              : null,
                          child: Text(
                            '下一章',
                            style: TextStyle(
                              fontSize: 14,
                              color: _index < _titles.length - 1
                                  ? theme.primaryColor
                                  : theme.textColor.withValues(alpha: 0.3),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14), // 改动：增大间距
                    // ---- 第二行：四个功能按钮 ----
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildBottomActionBtn(
                          icon: Icons.list_alt,
                          label: '目录',
                          color: theme.textColor,
                          onTap: _titles.isEmpty ? null : _openToc,
                        ),
                        _buildBottomActionBtn(
                          icon: Icons.bookmarks_outlined,
                          label: '书签',
                          color: theme.textColor,
                          onTap: _bookmarks.isEmpty ? null : _showBookmarks,
                        ),
                        _buildBottomActionBtn(
                          icon: _ttsActive
                              ? Icons.stop_circle_outlined
                              : Icons.headset_outlined,
                          label: '听书',
                          color: theme.textColor,
                          onTap: _showTtsSheet,
                        ),
                        _buildBottomActionBtn(
                          icon: Icons.settings_outlined,
                          label: '设置',
                          color: theme.textColor,
                          onTap: _showSettings,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 底部功能按钮 ----------
  Widget _buildBottomActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: disabled
                  ? color.withValues(alpha: 0.25)
                  : color,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: disabled
                    ? color.withValues(alpha: 0.25)
                    : color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 子组件 ----------
  List<Widget> _paragraphs(NovelReaderTheme theme) {
    final style = NovelReaderSettings.applyTextStyle(TextStyle(
      fontSize: NovelReaderSettings.fontSize,
      height: NovelReaderSettings.lineHeight,
      color: theme.textColor,
    ));
    return [
      for (final p in _content.split('\n'))
        if (p.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: NovelReaderSettings.paragraphGap),
            child: Text(p, style: style),
          ),
    ];
  }

  Widget _buildDownloadableFontChip(
    BuildContext context,
    DownloadableFont font,
    void Function(void Function()) setSheet,
  ) {
    final isDownloaded = NovelFontService.isDownloaded(font.key);
    final isSelected = NovelReaderSettings.fontKey == font.key;
    final isDownloading = _downloadingFonts.contains(font.key);

    return StatefulBuilder(
      builder: (ctx, setChipState) {
        return GestureDetector(
          onTap: isDownloaded
              ? () {
                  if (!isSelected) {
                    NovelReaderSettings.fontKey = font.key;
                    NovelReaderSettings.save();
                    setSheet(() {});
                    setChipState(() {});
                  }
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isDownloaded
                  ? (isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  font.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDownloaded
                        ? (isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface)
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 4),
                if (isDownloading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (isDownloaded)
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  )
                else
                  GestureDetector(
                    onTap: () async {
                      setChipState(() => _downloadingFonts.add(font.key));
                      setSheet(() {});
                      try {
                        await NovelFontService.download(
                          font.key,
                          onProgress: (p) {},
                        );
                        if (context.mounted) {
                          NovelReaderSettings.fontKey = font.key;
                          await NovelReaderSettings.save();
                          setSheet(() {});
                          SmartDialog.showToast('已下载并应用 ${font.label}');
                        }
                      } catch (e) {
                        SmartDialog.showToast('下载失败: $e');
                      }
                      setChipState(() => _downloadingFonts.remove(font.key));
                      setSheet(() {});
                    },
                    child: Text(
                      '下载',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _errorView(String msg, {required VoidCallback retry}) {
    final theme = _theme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 44, color: theme.textColor.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textColor, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: retry,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.primaryColor,
                side: BorderSide(color: theme.primaryColor),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagedArea(NovelReaderTheme theme) {
    final hasContent = _content.isNotEmpty;
    if (_error != null) return _errorView(_error!, retry: () => _loadChapter(_index));
    if (!hasContent && _loading) {
      return Center(child: CircularProgressIndicator(color: theme.primaryColor));
    }
    if (!hasContent && _error != null) {
      return _errorView(_error!, retry: () => _loadChapter(_index));
    }
    return LayoutBuilder(
      builder: (ctx, c) {
        final key = Object.hash(
          c.maxWidth.toInt(),
          c.maxHeight.toInt(),
          _index,
          _content.length,
          NovelReaderSettings.fontSize,
          NovelReaderSettings.lineHeight,
          NovelReaderSettings.pagePadding.toInt(),
          NovelReaderSettings.letterSpacing,
          NovelReaderSettings.fontKey,
          NovelReaderSettings.paragraphGap.toInt(),
        );
        if (_pageKey != key) {
          _schedulePaginate(Size(c.maxWidth, c.maxHeight), key);
          return Center(child: CircularProgressIndicator(color: theme.primaryColor));
        }
        final n = _pageUnits.length;
        if (n == 0) {
          return Center(
            child: Text('空白章节', style: TextStyle(color: theme.textColor)),
          );
        }
        final faint = theme.textColor.withValues(alpha: 0.45);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                NovelReaderSettings.pagePadding, 6, NovelReaderSettings.pagePadding, 4),
              child: Text(
                _titles.isEmpty ? '' : _titles[_index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: faint),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: n,
                onPageChanged: (i) {
                  setState(() => _pageIndex = i);
                  _saveProgress();
                },
                itemBuilder: (ctx, i) {
                  final unit = _pageUnits[i];
                  return _pageTransform(
                    i,
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: NovelReaderSettings.pagePadding),
                      child: Text(
                        _pagedJoined.substring(unit.start, unit.end).trim(),
                        style: NovelReaderSettings.applyTextStyle(TextStyle(
                          fontSize: NovelReaderSettings.fontSize,
                          height: NovelReaderSettings.lineHeight,
                          color: theme.textColor,
                        )),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                NovelReaderSettings.pagePadding,
                4,
                NovelReaderSettings.pagePadding,
                6 + MediaQuery.paddingOf(ctx).bottom,
              ),
              child: Row(
                children: [
                  Text(
                    '第 ${_index + 1}/${_titles.length} 章 · $_footerStatus',
                    style: TextStyle(fontSize: 11, color: faint),
                  ),
                  const Spacer(),
                  Text(
                    '${_pageIndex + 1} / $n',
                    style: TextStyle(fontSize: 11, color: faint),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String get _footerStatus {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final bat = _batteryLevel >= 0 ? ' · $_batteryLevel%' : '';
    return '$hh:$mm$bat';
  }
}

// ---------- 辅助类 ----------
class _PageUnit {
  final int start;
  final int end;
  final String? image;
  const _PageUnit.text(this.start, this.end) : image = null;
  const _PageUnit.image(this.image, this.start) : end = 0;
  bool get isImage => image != null;
}