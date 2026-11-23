// lib/modules/novel/views/novel_reader_page.dart
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/modules/novel/settings/novel_reader_settings.dart';
import 'package:yuanying/modules/novel/models/novel_chapter_content.dart';
import 'package:yuanying/modules/novel/services/novel_chapter_content_service.dart';
import 'package:yuanying/modules/novel/services/novel_tts_service.dart';
import 'package:yuanying/modules/novel/services/novel_tts_reading_session.dart';
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

class _NovelReaderPageState extends State<NovelReaderPage>
    with WidgetsBindingObserver {
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
  late NovelChapterContentService _chapterContentService;
  final NovelTtsReadingSession _ttsSession = NovelTtsReadingSession();

  // 阅读状态
  List<String> _titles = [];
  int _index = 0;
  String _content = '';
  List<NovelChapterParagraph> _readerParagraphs = const [];
  NovelChapterContent? _currentChapterContent;
  List<GlobalKey> _paragraphKeys = const [];
  String _paragraphLayoutSource = '';
  double? _paragraphLayoutGap;
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
  bool _ttsEngineSwitching = false;
  int? _ttsHighlightStart;
  int? _ttsHighlightEnd;
  int? _pendingTtsOffset;
  int? _readingOffset;
  int? _pendingReadingOffset;
  bool _ttsProgrammaticPageChange = false;
  bool _ttsStartAtChapterTop = false;
  Timer? _sleepTimer;
  int _sleepMinutes = 0;
  Future<List<Map<String, String>>>? _voicesFuture;

  // 页脚状态
  final Battery _battery = Battery();
  Timer? _footerTimer;
  int _batteryLevel = -1;
  // Timer? _statTimer;

  // 书签
  List<NovelBookmark> _bookmarks = [];

  // 净化规则
  List<Map<String, dynamic>> _purifyRules = [];

  // 字体下载状态
  final Set<String> _downloadingFonts = {};

  // 阅读主题（使用 yuedu 主题系统）
  NovelReaderTheme get _theme =>
      NovelReaderTheme.getThemeByIndex(NovelReaderSettings.themeIndex);

  @override
  void initState() {
    super.initState();
    // 加载阅读器设置
    NovelReaderSettings.load();
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
      _episodes = episodesData
          .map(
            (e) => Episode(
              name: e['name']?.toString() ?? '',
              url: e['url']?.toString() ?? '',
            ),
          )
          .toList();
    } else {
      _episodes = [];
    }
    _apiService = _site != null
        ? Get.find<SourceManager>().createIndependentService(_site!)
        : Get.find<SourceManager>().currentApiService;
    _chapterContentService = NovelChapterContentService(
      apiService: _apiService,
      sourceName: _sourceName,
      pwd: _pwd,
      apiUrl: _site?['api']?.toString() ?? '',
    );
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
    _footerTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshBattery(),
    );
    // _statTimer = Timer.periodic(const Duration(seconds: 30), (_) {});
  }

  @override
  void dispose() {
    if (_ttsActive) {
      unawaited(_ttsService.stop());
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _sleepTimer?.cancel();
    _footerTimer?.cancel();
    // _statTimer?.cancel();
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

  // ---------- 书签 ----------
  void _loadBookmarks() {
    final key = '${SettingBoxKey.novelBookmarksPrefix}$_vodId';
    final data = StorageManager.getCache<List>(key);
    if (data != null) {
      _bookmarks = data
          .map(
            (e) => NovelBookmark.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
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
            final target = (offset * (_pageUnits.length - 1)).round().clamp(
              0,
              _pageUnits.length - 1,
            );
            _pageCtrl?.jumpToPage(target);
            setState(() => _pageIndex = target);
          }
        }
      },
      onDelete: (bookmark) async {
        _bookmarks.removeWhere(
          (b) =>
              b.chapter == bookmark.chapter &&
              b.createdAt == bookmark.createdAt,
        );
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
        _purifyRules = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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
  Future<void> _loadChapter(int idx, {bool fromTts = false}) async {
    if (idx < 0 || idx >= _episodes.length) return;
    if (_ttsActive && !fromTts && idx != _index) {
      _ttsSession.takeOver();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final content = await _chapterContentService.load(
        chapterIndex: idx,
        vodId: _vodId,
        playParams: _episodes[idx].url,
        separator: _paragraphSeparator,
        purifyRules: _purifyRules,
      );

      if (mounted) {
        setState(() {
          _currentChapterContent = content;
          _content = content.text;
          _readerParagraphs = content.paragraphs;
          _paragraphKeys = [for (final _ in content.paragraphs) GlobalKey()];
          _paragraphLayoutSource = content.text;
          _paragraphLayoutGap = NovelReaderSettings.paragraphGap;
          _ttsHighlightStart = null;
          _ttsHighlightEnd = null;
          _pendingTtsOffset = null;
          _ttsProgrammaticPageChange = false;
          _readingOffset = 0;
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
      SmartDialog.showToast('加载章节失败：$e');
      if (mounted) {
        setState(() {
          _error = '加载章节失败：$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveProgress() async {
    final apiUrl = _site?['api']?.toString() ?? '';
    final key = StorageManager.progressKey('novel_progress', _vodId, apiUrl);
    final progress = {'chapter': _index};
    await StorageManager.setCache(key, progress);
  }

  void _nextChapter({bool fromTts = false}) {
    if (_index < _episodes.length - 1) {
      _loadChapter(_index + 1, fromTts: fromTts);
    } else {
      SmartDialog.showToast('已经是最后一章');
    }
  }

  void _prevChapter({bool fromTts = false}) {
    if (_index > 0) {
      _loadChapter(_index - 1, fromTts: fromTts);
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
    if (_ttsActive) _ttsSession.takeOver();
    if (_paged) {
      _pagedNext();
      return;
    }
    if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      final pos = _scroll.position;
      if (pos.maxScrollExtent - pos.pixels > _pageStep * 0.5) {
        final target = (pos.pixels + _pageStep).clamp(0.0, pos.maxScrollExtent);
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
        return;
      }
    }
    _nextChapter();
  }

  void _prevPage() {
    if (_ttsActive) _ttsSession.takeOver();
    if (_paged) {
      _pagedPrev();
      return;
    }
    if (_scroll.hasClients && _scroll.position.pixels > 2) {
      final pos = _scroll.position;
      final target = (pos.pixels - _pageStep).clamp(0.0, pos.maxScrollExtent);
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
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
        ctrl.animateToPage(
          _pageIndex + 1,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
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
        ctrl.animateToPage(
          _pageIndex - 1,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
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
      if (!mounted || !_paged) {
        _paginating = false;
        return;
      }
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
        target = (_pendingRestore * (units.length - 1)).round().clamp(
          0,
          units.length - 1,
        );
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
      if (_pendingTtsOffset != null) {
        final off = _pendingTtsOffset!;
        _pendingTtsOffset = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _ttsActive && NovelReaderSettings.followTts) {
            _followPagedOffset(off);
          }
        });
      }
      if (_pendingReadingOffset != null) {
        final off = _pendingReadingOffset!;
        _pendingReadingOffset = null;
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
    final style = NovelReaderSettings.applyTextStyle(
      TextStyle(
        fontSize: NovelReaderSettings.fontSize,
        height: NovelReaderSettings.lineHeight,
      ),
    );
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

  String get _paragraphSeparator {
    final gap = NovelReaderSettings.paragraphGap;
    return gap <= 2 ? '\n' : (gap >= 20 ? '\n\n\n' : '\n\n');
  }

  void _prepareReaderParagraphLayout(String source) {
    final content = NovelChapterContent.fromText(
      chapterIndex: _index,
      text: source,
      separator: _paragraphSeparator,
    );
    _currentChapterContent = content;
    _readerParagraphs = content.paragraphs;
    _paragraphKeys = [for (final _ in content.paragraphs) GlobalKey()];
    _paragraphLayoutSource = source;
    _paragraphLayoutGap = NovelReaderSettings.paragraphGap;
    _ttsHighlightStart = null;
    _ttsHighlightEnd = null;
    _pendingTtsOffset = null;
    _ttsProgrammaticPageChange = false;
  }

  void _ensureReaderParagraphLayout() {
    if (_paragraphLayoutSource == _content &&
        _paragraphLayoutGap == NovelReaderSettings.paragraphGap) {
      return;
    }
    _prepareReaderParagraphLayout(_content);
  }

  String get _joinedText {
    final sep = _paragraphSeparator;
    return _content
        .split('\n')
        .where((p) => p.trim().isNotEmpty)
        .map((p) => p.trim())
        .join(sep);
  }

  // ============================================================================
  // 翻页动画系统（移植自 yuedu 项目，5种动画模式）
  // ============================================================================
  Widget _pageTransform(int i, Widget child) {
    final mode = NovelPageTurnModeExt.fromStorageKey(
      NovelReaderSettings.pageAnim,
    );
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
    return RepaintBoundary(
      child: ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          widthFactor: 1 - absDelta,
          child: child,
        ),
      ),
    );
  }

  // ----- 仿真翻页（3D旋转）-----
  Widget _buildSimulationAnimation(Widget child, double delta) {
    final absDelta = delta.abs();
    final angle = (delta > 0 ? -1 : 1) * absDelta * 3.1415926 * 0.36;
    return RepaintBoundary(
      child: Transform(
        alignment: delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY(angle),
        child: Opacity(
          opacity: (1 - absDelta * 0.3).clamp(0.3, 1.0),
          child: child,
        ),
      ),
    );
  }

  // ----- 滑动动画 -----
  Widget _buildSlideAnimation(Widget child, double delta) {
    final absDelta = delta.abs();
    if (delta > 0) {
      // 下一页：从右侧滑入，显示左侧部分，宽度 0→1
      return ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          widthFactor: absDelta,
          child: child,
        ),
      );
    } else if (delta < 0) {
      // 当前页：向左滑出，显示右侧部分，宽度 1→0
      return ClipRect(
        child: Align(
          alignment: Alignment.topRight,
          widthFactor: 1 - absDelta,
          child: child,
        ),
      );
    } else {
      return child;
    }
  }

  // ----- 滚动动画 -----
  Widget _buildScrollAnimation(Widget child, double delta) {
    final absDelta = delta.abs();
    if (delta > 0) {
      // 下一页：从底部滑入
      return Transform.translate(
        offset: Offset(0, (1 - absDelta) * 150),
        child: Opacity(
          opacity: absDelta.clamp(0.0, 1.0),
          child: child,
        ),
      );
    } else if (delta < 0) {
      // 当前页：向上滑出
      return Transform.translate(
        offset: Offset(0, -absDelta * 150),
        child: Opacity(
          opacity: (1 - absDelta).clamp(0.0, 1.0),
          child: child,
        ),
      );
    } else {
      return child;
    }
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
    // 始终保持 immersiveSticky，不因工具栏切换而改变
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
        try {
          final content = await _chapterContentService.load(
            chapterIndex: i,
            vodId: _vodId,
            playParams: _episodes[i].url,
            separator: _paragraphSeparator,
            purifyRules: _purifyRules,
          );
          return content.text;
        } catch (_) {
          return '';
        }
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
  List<NovelTtsChunk> _ttsChunksOfCurrentLayout() {
    return _ttsSession.content?.buildTtsChunks() ??
        _currentChapterContent?.buildTtsChunks() ??
        const [];
  }

  int _ttsStartChunkIndex(List<NovelTtsChunk> chunks) {
    if (chunks.length <= 1) return 0;
    if (_ttsStartAtChapterTop) {
      _ttsStartAtChapterTop = false;
      return 0;
    }
    final resumeOffset = _readingOffset;
    if (resumeOffset != null) {
      final resumeIndex = chunks.indexWhere(
        (chunk) => chunk.end > resumeOffset,
      );
      if (resumeIndex >= 0) return resumeIndex;
    }
    if (_paged && _pagedReady && _pageUnits.length > 1) {
      final offset =
          _pageUnits[_pageIndex.clamp(0, _pageUnits.length - 1)].start;
      final index = chunks.indexWhere((chunk) => chunk.end > offset);
      return index < 0 ? chunks.length - 1 : index;
    }
    final double ratio =
        _scroll.hasClients && _scroll.position.maxScrollExtent > 0
        ? _scroll.position.pixels / _scroll.position.maxScrollExtent
        : 0;
    final offset = (_joinedText.length * ratio).round();
    final index = chunks.indexWhere((chunk) => chunk.end > offset);
    return index < 0 ? chunks.length - 1 : index;
  }

  void _onTtsChunk(NovelTtsChunk chunk) {
    _ttsSession.updateChunk(chunk);
    if (!_ttsActive || chunk.chapterIndex != _index) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ttsActive || chunk.chapterIndex != _index) return;
      try {
        setState(() {
          _ttsHighlightStart = chunk.start;
          _ttsHighlightEnd = chunk.end;
          _readingOffset = chunk.start;
        });
      } catch (e) {
        debugPrint('[NovelTts] highlight update skipped: $e');
        return;
      }
      if (!NovelReaderSettings.followTts) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_ttsActive ||
            !NovelReaderSettings.followTts ||
            _ttsSession.manualTakeover) {
          return;
        }
        try {
          if (_paged) {
            _followPagedOffset(chunk.start);
          } else {
            _followScrollOffset(chunk.start);
          }
        } catch (e) {
          debugPrint('[NovelTts] follow skipped: $e');
        }
      });
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _clearTtsHighlight() {
    _ttsHighlightStart = null;
    _ttsHighlightEnd = null;
    _pendingTtsOffset = null;
    _ttsSession.clear();
    _ttsProgrammaticPageChange = false;
    _ttsStartAtChapterTop = false;
  }

  int _captureReadingOffset() {
    _ensureReaderParagraphLayout();
    if (_content.isEmpty) return 0;
    if (_ttsActive &&
        !_ttsSession.manualTakeover &&
        _ttsHighlightStart != null) {
      return _ttsHighlightStart!;
    }
    if (_paged && _pagedReady && _pageUnits.isNotEmpty) {
      final index = _pageIndex.clamp(0, _pageUnits.length - 1);
      return _pageUnits[index].start;
    }
    if (!_paged && _scroll.hasClients) {
      final viewportObject = _scroll.position.context.storageContext
          .findRenderObject();
      if (viewportObject is RenderBox) {
        final topGlobal = viewportObject.localToGlobal(Offset.zero).dy + 2;
        for (int i = 0; i < _readerParagraphs.length; i++) {
          if (i >= _paragraphKeys.length) break;
          final renderObject = _paragraphKeys[i].currentContext
              ?.findRenderObject();
          if (renderObject is! RenderParagraph || !renderObject.hasSize) {
            continue;
          }
          final top = renderObject.localToGlobal(Offset.zero).dy;
          final bottom = top + renderObject.size.height;
          if (top <= topGlobal && bottom >= topGlobal) {
            final local = renderObject.globalToLocal(
              Offset(0, topGlobal),
            );
            final position = renderObject.getPositionForOffset(local);
            return _readerParagraphs[i].start + position.offset;
          }
        }
      }
      if (_scroll.position.maxScrollExtent > 0) {
        final ratio =
            _scroll.position.pixels / _scroll.position.maxScrollExtent;
        return (_joinedText.length * ratio).round().clamp(
          0,
          _joinedText.length,
        );
      }
    }
    return _readingOffset ?? 0;
  }

  void _followPagedOffset(int offset) {
    if (!_pagedReady || _paginating || _pageUnits.isEmpty) {
      _pendingTtsOffset = offset;
      return;
    }
    var page = _pageUnits.indexWhere(
      (unit) => !unit.isImage && offset >= unit.start && offset < unit.end,
    );
    if (page < 0) {
      page = _pageUnits.indexWhere(
        (unit) => !unit.isImage && unit.end > offset,
      );
    }
    if (page < 0 || page == _pageIndex) return;
    final controller = _pageCtrl;
    if (controller == null || !controller.hasClients) {
      _pendingTtsOffset = offset;
      return;
    }
    _ttsProgrammaticPageChange = true;
    unawaited(
      controller
          .animateToPage(
            page,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (!mounted) return;
            _ttsProgrammaticPageChange = false;
          }),
    );
  }

  void _followScrollOffset(int offset, {bool animate = true}) {
    if (!_scroll.hasClients) return;
    final index = _readerParagraphs.indexWhere(
      (paragraph) => offset >= paragraph.start && offset < paragraph.end,
    );
    if (index < 0 || index >= _paragraphKeys.length) return;
    final paragraph = _readerParagraphs[index];
    final renderObject = _paragraphKeys[index].currentContext
        ?.findRenderObject();
    if (renderObject is! RenderParagraph || !renderObject.hasSize) return;
    final localOffset = (offset - paragraph.start).clamp(
      0,
      paragraph.text.length,
    );
    final boxes = renderObject.getBoxesForSelection(
      TextSelection(
        baseOffset: localOffset,
        extentOffset: min(localOffset + 1, paragraph.text.length),
      ),
    );
    if (boxes.isEmpty) return;
    final caretGlobal = renderObject.localToGlobal(
      Offset(boxes.first.left, boxes.first.top),
    );
    final viewportObject = _scroll.position.context.storageContext
        .findRenderObject();
    final viewportTop = viewportObject is RenderBox
        ? viewportObject.localToGlobal(Offset.zero).dy
        : 0.0;
    final target = (_scroll.offset + caretGlobal.dy - viewportTop - 80).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if ((target - _scroll.offset).abs() < 4) return;
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  void _scheduleScrollRestore(int offset, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_paged && _scroll.hasClients) {
        _followScrollOffset(offset, animate: false);
      } else if (!_paged && attempt < 3) {
        _scheduleScrollRestore(offset, attempt + 1);
      }
    });
  }

  TextSpan _ttsTextSpan(
    String text,
    int globalStart,
    TextStyle style,
    NovelReaderTheme theme,
  ) {
    final highlightStart = _ttsHighlightStart;
    final highlightEnd = _ttsHighlightEnd;
    if (highlightStart == null || highlightEnd == null || text.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final start = max(highlightStart, globalStart) - globalStart;
    final end = min(highlightEnd, globalStart + text.length) - globalStart;
    if (start >= end || end <= 0 || start >= text.length) {
      return TextSpan(text: text, style: style);
    }
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(safeStart, text.length);
    return TextSpan(
      style: style,
      children: [
        if (safeStart > 0) TextSpan(text: text.substring(0, safeStart)),
        TextSpan(
          text: text.substring(safeStart, safeEnd),
          style: style.copyWith(
            backgroundColor: theme.primaryColor.withValues(alpha: 0.2),
          ),
        ),
        if (safeEnd < text.length) TextSpan(text: text.substring(safeEnd)),
      ],
    );
  }

  Future<void> _startTts({VoidCallback? onStateChanged}) async {
    if (_ttsActive || _content.isEmpty) return;
    if (_ttsService.engine == NovelTtsEngine.network) {
      try {
        await _ttsService.ensureRaTtsReady();
      } catch (e) {
        SmartDialog.showToast('$e');
        return;
      }
      if (_ttsService.currentNetworkVoice == null) {
        SmartDialog.showToast('请先选择网络音色');
        return;
      }
    }
    _readingOffset = _captureReadingOffset();
    final initialContent = _currentChapterContent;
    if (initialContent == null) {
      SmartDialog.showToast('章节内容尚未加载完成');
      return;
    }
    _ttsSession.begin(
      chapterIndex: _index,
      chapterContent: initialContent,
      offset: _readingOffset ?? 0,
    );
    setState(() => _ttsActive = true);
    _ttsProgrammaticPageChange = false;
    _ttsStartAtChapterTop = false;
    onStateChanged?.call();
    try {
      while (_ttsActive && mounted) {
        if (_paged) {
          while (_ttsActive && mounted && (!_pagedReady || _paginating)) {
            await Future.delayed(const Duration(milliseconds: 80));
          }
        }
        if (!_ttsActive || !mounted) break;
        final allChunks = _ttsChunksOfCurrentLayout();
        if (allChunks.isEmpty) break;
        final startIdx = _ttsStartChunkIndex(allChunks);
        final chunks = allChunks.sublist(startIdx);
        await _ttsService.speakChunks(
          chunks.map((chunk) => chunk.text).toList(),
          isCancelled: () => !_ttsActive,
          onChunk: (index) => _onTtsChunk(chunks[index]),
        );
        if (!_ttsActive || !mounted) break;
        if ((_ttsSession.readingChapter ?? _index) < _episodes.length - 1) {
          final nextChapter = (_ttsSession.readingChapter ?? _index) + 1;
          _ttsStartAtChapterTop = true;
          if (_ttsSession.manualTakeover) {
            final nextContent =
                _index == nextChapter && _currentChapterContent != null
                ? _currentChapterContent!
                : await _chapterContentService.load(
                    chapterIndex: nextChapter,
                    vodId: _vodId,
                    playParams: _episodes[nextChapter].url,
                    separator: _paragraphSeparator,
                    purifyRules: _purifyRules,
                  );
            if (!_ttsActive || !mounted) break;
            _ttsSession.advance(nextContent);
          } else {
            if (_index != nextChapter) {
              await _loadChapter(nextChapter, fromTts: true);
            }
            while (_loading && _ttsActive && mounted) {
              await Future.delayed(const Duration(milliseconds: 120));
            }
            final nextContent = _currentChapterContent;
            if (!_ttsActive || !mounted || nextContent == null) break;
            _ttsSession.advance(nextContent);
          }
        } else {
          break;
        }
      }
    } catch (e) {
      if (_ttsActive && mounted) {
        SmartDialog.showToast('朗读失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _ttsActive = false;
          _clearTtsHighlight();
        });
        onStateChanged?.call();
      }
    }
  }

  void _stopTts() {
    _sleepTimer?.cancel();
    _sleepMinutes = 0;
    if (_ttsActive) {
      _readingOffset = _captureReadingOffset();
      _ttsActive = false;
      _ttsService.stop();
      _clearTtsHighlight();
    }
    if (mounted) setState(() {});
  }

  Future<void> _switchTtsEngine(
    NovelTtsEngine next,
    BuildContext sheetContext,
    StateSetter setSheet,
  ) async {
    if (_ttsEngineSwitching ||
        next == _ttsService.engine ||
        !mounted ||
        !sheetContext.mounted) {
      return;
    }
    if (next == NovelTtsEngine.network &&
        !NovelTtsService.isSupportedPlatform) {
      SmartDialog.showToast(NovelTtsService.unsupportedPlatformMessage);
      return;
    }
    final wasActive = _ttsActive;
    if (wasActive) {
      _sleepTimer?.cancel();
      _sleepMinutes = 0;
      _ttsActive = false;
    }
    setState(() => _ttsEngineSwitching = true);
    try {
      if (sheetContext.mounted) setSheet(() {});
      // setEngine 内部只执行一次 stop；这里不能先调 _stopTts()，
      // 否则原生播放器会收到并发 stop，导致平台通道重复返回并闪退。
      await _ttsService.setEngine(next, stopPlayback: wasActive);
    } catch (e) {
      SmartDialog.showToast('切换朗读引擎失败：$e');
    } finally {
      if (mounted) {
        setState(() => _ttsEngineSwitching = false);
      }
      if (sheetContext.mounted) {
        setSheet(() {});
      }
    }
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
    Future<NovelTtsServiceStatus> statusFuture = _ttsService.raTtsStatus();
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
            final colors = Theme.of(ctx).colorScheme;
            final isNetwork = _ttsService.engine == NovelTtsEngine.network;
            final networkSupported = NovelTtsService.isSupportedPlatform;
            final currentNetworkVoice = _ttsService.currentNetworkVoice;
            final systemVoiceLabel = _ttsService.voiceKey ?? '系统默认音色';
            final rateValue = isNetwork
                ? _ttsService.networkRate
                : _ttsService.rate;
            final rateText =
                '${rateValue.toStringAsFixed(isNetwork ? 1 : 2)}'
                '${isNetwork ? 'x' : ''}';
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          '听书',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _ttsActive ? '正在朗读 第 ${_index + 1} 章' : '未在朗读',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.outline,
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
                            _startTts(
                              onStateChanged: () {
                                if (ctx.mounted) setSheet(() {});
                              },
                            );
                          }
                          setSheet(() {});
                        },
                        icon: Icon(_ttsActive ? Icons.stop : Icons.play_arrow),
                        label: Text(_ttsActive ? '停止朗读' : '开始朗读'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const SizedBox(
                          width: 64,
                          child: Text('朗读引擎', style: TextStyle(fontSize: 13.5)),
                        ),
                        Expanded(
                          child: SegmentedButton<NovelTtsEngine>(
                            showSelectedIcon: false,
                            segments: [
                              const ButtonSegment(
                                value: NovelTtsEngine.system,
                                label: Text('系统引擎'),
                                icon: Icon(Icons.record_voice_over_outlined),
                              ),
                              ButtonSegment(
                                value: NovelTtsEngine.network,
                                label: const Text('网络音色包'),
                                icon: const Icon(Icons.cloud_outlined),
                                enabled: networkSupported,
                                tooltip: networkSupported
                                    ? null
                                    : NovelTtsService
                                          .unsupportedPlatformMessage,
                              ),
                            ],
                            selected: {_ttsService.engine},
                            onSelectionChanged: _ttsEngineSwitching
                                ? null
                                : (selection) => _switchTtsEngine(
                                    selection.first,
                                    ctx,
                                    setSheet,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    if (!networkSupported)
                      Padding(
                        padding: const EdgeInsets.only(left: 64, top: 2),
                        child: Text(
                          NovelTtsService.unsupportedPlatformMessage,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.outline,
                          ),
                        ),
                      ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        '跟随朗读',
                        style: TextStyle(fontSize: 13.5),
                      ),
                      subtitle: const Text(
                        '自动滚动或翻页到当前朗读片段',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: NovelReaderSettings.followTts,
                      onChanged: (value) async {
                        NovelReaderSettings.followTts = value;
                        if (value) {
                          _ttsSession.resumeFollow();
                          _ttsProgrammaticPageChange = false;
                        }
                        NovelReaderSettings.save();
                        setState(() {});
                        setSheet(() {});
                        if (!value || !_ttsActive) return;
                        final readingChapter = _ttsSession.readingChapter;
                        if (readingChapter != null &&
                            readingChapter != _index) {
                          await _loadChapter(
                            readingChapter,
                            fromTts: true,
                          );
                        }
                        final offset = _ttsSession.readingOffset;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted || !_ttsActive) return;
                          if (_paged) {
                            _followPagedOffset(offset);
                          } else {
                            _followScrollOffset(offset);
                          }
                        });
                        if (ctx.mounted) setSheet(() {});
                      },
                    ),
                    if (isNetwork)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: FutureBuilder<NovelTtsServiceStatus>(
                          future: statusFuture,
                          builder: (ctx, snap) {
                            final status = snap.data;
                            final running = status?.running == true;
                            final text = status == null
                                ? (snap.hasError ? '服务检测失败' : '正在检测朗读服务…')
                                : running
                                ? 'Edge 朗读 TTS 运行中 · ${status.baseUrl}'
                                : !status.pluginInstalled
                                ? '未安装 Edge 朗读 TTS'
                                : !status.pluginEnabled
                                ? 'Edge 朗读 TTS 插件已关闭'
                                : !status.serviceConfigured
                                ? '服务配置缺失，请重新安装插件'
                                : (status.message ?? 'Edge 朗读 TTS 未启动');
                            return Container(
                              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest
                                    .withValues(
                                      alpha: 0.55,
                                    ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    running
                                        ? Icons.cloud_done
                                        : Icons.cloud_off,
                                    size: 18,
                                    color: running
                                        ? Colors.green
                                        : colors.outline,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      text,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: running
                                            ? Colors.green
                                            : colors.outline,
                                      ),
                                    ),
                                  ),
                                  if (status != null &&
                                      status.pluginInstalled &&
                                      status.pluginEnabled &&
                                      status.serviceConfigured &&
                                      !running)
                                    TextButton(
                                      onPressed: () async {
                                        try {
                                          await _ttsService.startRaTts();
                                          SmartDialog.showToast(
                                            'Edge 朗读 TTS 已启动',
                                          );
                                        } catch (e) {
                                          SmartDialog.showToast('启动失败：$e');
                                        }
                                        if (!ctx.mounted) return;
                                        setSheet(() {
                                          statusFuture = _ttsService
                                              .raTtsStatus();
                                        });
                                      },
                                      child: const Text('启动服务'),
                                    )
                                  else if (status != null &&
                                      (!status.pluginInstalled ||
                                          !status.pluginEnabled ||
                                          !status.serviceConfigured))
                                    TextButton(
                                      onPressed: () async {
                                        await Get.toNamed(
                                          AppPages.pluginCenter,
                                        );
                                        if (!ctx.mounted) return;
                                        setSheet(() {
                                          statusFuture = _ttsService
                                              .raTtsStatus();
                                        });
                                      },
                                      child: const Text('插件中心'),
                                    )
                                  else
                                    IconButton(
                                      tooltip: '重新检测',
                                      onPressed: () {
                                        setSheet(() {
                                          statusFuture = _ttsService
                                              .raTtsStatus();
                                        });
                                      },
                                      icon: const Icon(Icons.refresh, size: 18),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    Row(
                      children: [
                        const SizedBox(
                          width: 64,
                          child: Text('语速', style: TextStyle(fontSize: 13.5)),
                        ),
                        Expanded(
                          child: Slider(
                            value: isNetwork
                                ? _ttsService.networkRate
                                : _ttsService.rate,
                            min: isNetwork ? 0.5 : 0.3,
                            max: isNetwork ? 2.0 : 1.0,
                            divisions: isNetwork ? 15 : 14,
                            onChanged: (v) {
                              if (isNetwork) {
                                _ttsService.setNetworkRate(v);
                              } else {
                                _ttsService.setRate(v);
                              }
                              setSheet(() {});
                            },
                          ),
                        ),
                        SizedBox(
                          width: 42,
                          child: Text(
                            rateText,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                    if (isNetwork)
                      Row(
                        children: [
                          const SizedBox(
                            width: 64,
                            child: Text('音色', style: TextStyle(fontSize: 13.5)),
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _showNetworkVoicePicker(setSheet),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        currentNetworkVoice?.name ?? '请选择网络音色',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: currentNetworkVoice == null
                                              ? colors.outline
                                              : colors.onSurface,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: colors.outline,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              if (_ttsActive) _stopTts();
                              await Get.toNamed(AppPages.novelTtsVoices);
                              if (!ctx.mounted) return;
                              setSheet(() {});
                            },
                            child: const Text('管理音色包'),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          const SizedBox(
                            width: 64,
                            child: Text('音色', style: TextStyle(fontSize: 13.5)),
                          ),
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
                                      color: colors.outline,
                                    ),
                                  );
                                }
                                String keyOf(Map<String, String> v) =>
                                    '${v['name']}|${v['locale']}';
                                final current = _ttsService.voiceKey;
                                final valid =
                                    current != null &&
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
                                    if (!ctx.mounted) return;
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
                        const SizedBox(
                          width: 64,
                          child: Text('定时', style: TextStyle(fontSize: 13.5)),
                        ),
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
                    const SizedBox(height: 8),
                    Text(
                      isNetwork
                          ? '当前引擎：网络朗读 · ${currentNetworkVoice?.name ?? '未选择音色'}'
                          : '当前引擎：系统朗读 · $systemVoiceLabel',
                      style: TextStyle(fontSize: 11.5, color: colors.outline),
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

  Future<void> _showNetworkVoicePicker(StateSetter setSheet) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        final voices = _ttsService.networkVoices;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '选择网络音色',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (voices.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
                  child: Text(
                    '还没有网络音色，请先管理音色包并快捷添加或导入音色。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: colors.outline),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: voices.length,
                    itemBuilder: (ctx, index) {
                      final voice = voices[index];
                      final selected = voice.id == _ttsService.networkVoiceId;
                      return ListTile(
                        title: Text(
                          voice.name,
                          style: TextStyle(
                            color: selected ? colors.primary : null,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${_networkVoiceIdentifier(voice)} · 在线音色包',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selected
                            ? Icon(Icons.check, color: colors.primary)
                            : null,
                        onTap: () => Navigator.pop(ctx, voice.id),
                      );
                    },
                  ),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('管理音色包…'),
                subtitle: const Text('快捷添加 / 导入 / 试听 / 编辑 / 导出'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, '__manage__'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    if (action == '__manage__') {
      if (_ttsActive) _stopTts();
      await Get.toNamed(AppPages.novelTtsVoices);
    } else {
      final wasActive = _ttsActive;
      await _ttsService.setNetworkVoice(action);
      if (wasActive && mounted) {
        SmartDialog.showToast('音色已切换，将在当前及预加载片段后生效');
      }
    }
    if (mounted) setSheet(() {});
  }

  String _networkVoiceIdentifier(NovelTtsVoice voice) {
    final uri = Uri.tryParse(voice.url);
    final raw = uri?.queryParameters['voice'];
    return raw == null || raw.isEmpty ? voice.id : raw;
  }

  void _changeReadingMode(bool paged, VoidCallback refresh) {
    if (paged == NovelReaderSettings.pagedMode) return;
    final offset = _captureReadingOffset();
    _readingOffset = offset;
    _pendingReadingOffset = offset;
    if (_ttsActive) _stopTts();
    setState(() {
      NovelReaderSettings.pagedMode = paged;
      _pageIndex = 0;
      _pagedReady = false;
      _pageUnits = const [];
      _pageKey = null;
      _paginating = false;
      _pendingJumpLast = false;
      _pageCtrl?.dispose();
      _pageCtrl = null;
    });
    refresh();
    if (!paged) _scheduleScrollRestore(offset);
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

                    // ---- 字体（标签在上，选项水平滚动） ----
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('字体', style: TextStyle(fontSize: 13.5)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 36,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                for (final f in [
                                  ('system', '默认'),
                                  ('serif', '宋体'),
                                  ('kai', '楷体'),
                                  ('round', '圆体'),
                                  ('hei', '黑体'),
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(
                                        f.$2,
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                      selected:
                                          NovelReaderSettings.fontKey == f.$1,
                                      onSelected: (_) {
                                        NovelReaderSettings.fontKey = f.$1;
                                        refresh();
                                      },
                                      selectedColor: Theme.of(
                                        ctx,
                                      ).colorScheme.primaryContainer,
                                      labelStyle: TextStyle(
                                        color:
                                            NovelReaderSettings.fontKey == f.$1
                                            ? Theme.of(ctx).colorScheme.primary
                                            : Theme.of(
                                                ctx,
                                              ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
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
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(ctx).colorScheme.outline,
                            ),
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

                    // ---- 翻页模式（标签在上，选项水平滚动） ----
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('翻页模式', style: TextStyle(fontSize: 13.5)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 36,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('滚动'),
                                  selected: !NovelReaderSettings.pagedMode,
                                  onSelected: (_) {
                                    _changeReadingMode(false, refresh);
                                  },
                                  selectedColor: Theme.of(
                                    ctx,
                                  ).colorScheme.primaryContainer,
                                  labelStyle: TextStyle(
                                    color: !NovelReaderSettings.pagedMode
                                        ? Theme.of(ctx).colorScheme.primary
                                        : Theme.of(ctx).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('仿真分页'),
                                  selected: NovelReaderSettings.pagedMode,
                                  onSelected: (_) {
                                    _changeReadingMode(true, refresh);
                                  },
                                  selectedColor: Theme.of(
                                    ctx,
                                  ).colorScheme.primaryContainer,
                                  labelStyle: TextStyle(
                                    color: NovelReaderSettings.pagedMode
                                        ? Theme.of(ctx).colorScheme.primary
                                        : Theme.of(ctx).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ---- 翻页动画（标签在上，选项水平滚动） ----
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('翻页动画', style: TextStyle(fontSize: 13.5)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 36,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: NovelPageTurnMode.values.map((mode) {
                                final isSelected =
                                    NovelReaderSettings.pageAnim ==
                                    mode.storageKey;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(
                                      mode.displayName,
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                    selected: isSelected,
                                    onSelected: (_) {
                                      NovelReaderSettings.pageAnim =
                                          mode.storageKey;
                                      NovelReaderSettings.save();
                                      refresh();
                                    },
                                    selectedColor: Theme.of(
                                      ctx,
                                    ).colorScheme.primaryContainer,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? Theme.of(ctx).colorScheme.primary
                                          : Theme.of(ctx).colorScheme.onSurface,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ---- 阅读主题 ----
                    const SizedBox(height: 10),
                    const Divider(height: 20),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Row(
                        children: [
                          const Text('阅读主题', style: TextStyle(fontSize: 13.5)),
                          const SizedBox(width: 8),
                          Text(
                            NovelReaderTheme.getThemeByIndex(
                              NovelReaderSettings.themeIndex,
                            ).name,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(ctx).colorScheme.outline,
                            ),
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
                          final isSelected =
                              NovelReaderSettings.themeIndex == i;
                          return GestureDetector(
                            onTap: () {
                              NovelReaderSettings.themeIndex = i;
                              NovelReaderSettings.save();
                              refresh();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
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
                                        color: isSelected
                                            ? theme.primaryColor
                                            : Colors.transparent,
                                        width: 2.5,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: theme.primaryColor
                                                    .withValues(alpha: 0.3),
                                                blurRadius: 8,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
                onHorizontalDragEnd: _paged
                    ? null
                    : (details) {
                        if (_loading || _episodes.length < 2) return;
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity.abs() < 350) return;
                        if (velocity < 0)
                          _nextChapter();
                        else
                          _prevChapter();
                      },
                child: SafeArea(
                  bottom: false,
                  child: _error != null
                      ? _errorView(_error!, retry: () => _loadChapter(_index))
                      : !hasContent && _loading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: theme.primaryColor,
                          ),
                        )
                      : _paged
                      ? _buildPagedArea(theme)
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (_ttsActive &&
                                notification is UserScrollNotification) {
                              _ttsSession.takeOver();
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
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
                                      fontSize:
                                          NovelReaderSettings.fontSize + 3,
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
                                  _errorView(
                                    _error!,
                                    retry: () => _loadChapter(_index),
                                  )
                                else
                                  ..._paragraphs(theme),
                              ],
                            ),
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
                    color: Colors.black.withValues(
                      alpha: NovelReaderSettings.screenDim,
                    ),
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
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
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
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
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
                transform: Matrix4.translationValues(
                  0,
                  _toolbar ? 0 : 160 + safePadding.bottom + 20,
                  0,
                ),
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
                          onTap: _index > 0
                              ? () => _loadChapter(_index - 1)
                              : null,
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
                            max: (_titles.length - 1).toDouble().clamp(
                              0,
                              double.infinity,
                            ),
                            onChanged: (v) {
                              final target = v.round();
                              if (target != _index) _loadChapter(target);
                            },
                            activeColor: theme.primaryColor,
                            inactiveColor: theme.textColor.withValues(
                              alpha: 0.2,
                            ),
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
              color: disabled ? color.withValues(alpha: 0.25) : color,
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
    _ensureReaderParagraphLayout();
    final style = NovelReaderSettings.applyTextStyle(
      TextStyle(
        fontSize: NovelReaderSettings.fontSize,
        height: NovelReaderSettings.lineHeight,
        color: theme.textColor,
      ),
    );
    return [
      for (int i = 0; i < _readerParagraphs.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: NovelReaderSettings.paragraphGap),
          child: Text.rich(
            _ttsTextSpan(
              _readerParagraphs[i].text,
              _readerParagraphs[i].start,
              style,
              theme,
            ),
            key: _paragraphKeys[i],
          ),
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
            Icon(
              Icons.error_outline,
              size: 44,
              color: theme.textColor.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 14,
                height: 1.6,
              ),
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
    if (_error != null)
      return _errorView(_error!, retry: () => _loadChapter(_index));
    if (!hasContent && _loading) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
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
          return Center(
            child: CircularProgressIndicator(color: theme.primaryColor),
          );
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
                NovelReaderSettings.pagePadding,
                6,
                NovelReaderSettings.pagePadding,
                4,
              ),
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
                  if (!_ttsProgrammaticPageChange && _ttsActive) {
                    _ttsSession.takeOver();
                  }
                  setState(() => _pageIndex = i);
                  _saveProgress();
                },
                itemBuilder: (ctx, i) {
                  final unit = _pageUnits[i];
                  var start = unit.start.clamp(0, _pagedJoined.length);
                  var end = unit.end.clamp(start, _pagedJoined.length);
                  while (start < end && _pagedJoined[start].trim().isEmpty) {
                    start++;
                  }
                  while (end > start && _pagedJoined[end - 1].trim().isEmpty) {
                    end--;
                  }
                  final pageText = _pagedJoined.substring(start, end);
                  final pageStyle = NovelReaderSettings.applyTextStyle(
                    TextStyle(
                      fontSize: NovelReaderSettings.fontSize,
                      height: NovelReaderSettings.lineHeight,
                      color: theme.textColor,
                    ),
                  );
                  return _pageTransform(
                    i,
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: NovelReaderSettings.pagePadding,
                      ),
                      child: Text.rich(
                        _ttsTextSpan(pageText, start, pageStyle, theme),
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
