// lib/modules/manga/views/manga_reader_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/modules/manga/settings/manga_reader_settings.dart';
import 'package:yuanying/modules/novel/settings/novel_reader_settings.dart';
import 'package:yuanying/modules/novel/widgets/chapter_sheet.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/core/constants/storage_keys.dart';

class MangaReaderPage extends StatefulWidget {
  const MangaReaderPage({super.key});
  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> with WidgetsBindingObserver {
  late String _vodId;
  late String _vodName;
  late String _vodPic;
  late List<Episode> _episodes;
  late int _initialChapter;
  late String _pwd;
  late Map<String, dynamic>? _site;
  late String _sourceName;
  late ISpiderService _apiService;

  List<String> _imageUrls = [];
  int _currentPage = 0;
  int _totalPages = 0;
  bool _loading = true;
  String? _error;
  int _currentChapterIdx = 0;

  double _scale = 1.0;
  Timer? _autoScrollTimer;
  static const double _tapSlop = 20.0;

  bool _toolbar = false;
  double _pendingRestore = -1;

  NovelReaderTheme get _theme => NovelReaderTheme.getThemeByIndex(NovelReaderSettings.themeIndex);
  MangaReadMode get _readMode => MangaReaderSettings.readMode;

  final ScrollController _stripScrollController = ScrollController();
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
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
    MangaReaderSettings.load();
    _scale = MangaReaderSettings.zoomLevel;
    _currentChapterIdx = _initialChapter.clamp(0, _episodes.length - 1);
    if (_episodes.isEmpty) {
      _error = '没有章节';
      _loading = false;
    } else {
      _loadChapter(_currentChapterIdx);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _autoScrollTimer?.cancel();
    _pageController?.dispose();
    _stripScrollController.dispose();
    _saveProgress();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveProgress();
    }
  }

  Future<void> _onBackPressed() async {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (mounted) Navigator.pop(context);
  }

  // 安全重置条漫滚动位置（等布局完成后再跳，避免 controller 未 attach）
  void _resetStripScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stripScrollController.hasClients) {
        _stripScrollController.jumpTo(0);
      }
    });
  }

  Future<void> _loadChapter(int idx) async {
    if (idx < 0 || idx >= _episodes.length) return;
    _currentChapterIdx = idx;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cacheKey = 'manga_chapter_${_vodId}_$idx';
      String cached = StorageManager.getCache<String>(cacheKey) ?? '';
      List<String> urls = [];
      if (cached.isNotEmpty) {
        urls = jsonDecode(cached).cast<String>();
      } else {
        final playUrl = await _apiService.getPlayUrl(
          playParams: _episodes[idx].url,
          flag: _sourceName,
          pwd: _pwd,
        );
        if (playUrl == null) {
          SmartDialog.showToast('获取图片地址失败');
          setState(() { _loading = false; _error = '获取图片地址失败'; });
          return;
        }
        final url = playUrl.defaultUrl;
        if (url == null || url.isEmpty) {
          SmartDialog.showToast('图片地址为空');
          setState(() { _loading = false; _error = '图片地址为空'; });
          return;
        }
        if (!url.startsWith('pics://')) {
          SmartDialog.showToast('非漫画协议');
          setState(() { _loading = false; _error = '非漫画协议'; });
          return;
        }
        final raw = url.substring(7);
        urls = raw.split('&&').where((u) => u.trim().isNotEmpty).toList();
        if (urls.isEmpty) {
          SmartDialog.showToast('未解析到图片');
          setState(() { _loading = false; _error = '未解析到图片'; });
          return;
        }
        StorageManager.setCache(cacheKey, jsonEncode(urls));
      }

      // 使用 _pendingRestore 恢复书签位置（如果有）
      int savedPage = 0;
      if (_pendingRestore > 0) {
        savedPage = (_pendingRestore * urls.length).round().clamp(0, urls.length - 1);
        _pendingRestore = -1;
      } else {
        // 否则默认从第一页开始（因为章节切换时总是从头开始）
        savedPage = 0;
      }
      savedPage = savedPage.clamp(0, urls.length - 1);

      if (mounted) {
        setState(() {
          _imageUrls = urls;
          _totalPages = urls.length;
          _currentPage = savedPage;
          _loading = false;
        });
        if (_readMode == MangaReadMode.strip) {
          _resetStripScroll();
        }
        _pageController?.dispose();
        _pageController = PageController(initialPage: _currentPage);
        if (MangaReaderSettings.autoScroll) {
          _startAutoScroll();
        }
        _saveProgress();   // 保存当前章节
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

  void _saveProgress() {
    final key = 'manga_progress_$_vodId';
    final progress = {'chapter': _currentChapterIdx};
    StorageManager.setCache(key, progress);
  }

  void _onPageChanged(int index) {
    if (index < 0 || index >= _totalPages) return;
    setState(() { _currentPage = index; });
  }

  void _prevPage() {
    if (_readMode == MangaReadMode.strip) {
      if (_stripScrollController.hasClients) {
        final pos = _stripScrollController.position;
        final target = (pos.pixels - pos.viewportDimension * 0.8).clamp(0.0, pos.maxScrollExtent);
        _stripScrollController.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
      return;
    }
    if (_currentPage > 0) {
      _pageController?.animateToPage(_currentPage - 1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      _prevChapter();
    }
  }

  void _nextPage() {
    if (_readMode == MangaReadMode.strip) {
      if (_stripScrollController.hasClients) {
        final pos = _stripScrollController.position;
        final target = (pos.pixels + pos.viewportDimension * 0.8).clamp(0.0, pos.maxScrollExtent);
        _stripScrollController.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
      return;
    }
    if (_currentPage < _totalPages - 1) {
      _pageController?.animateToPage(_currentPage + 1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      _nextChapter();
    }
  }

  void _prevChapter() {
    if (_currentChapterIdx > 0) {
      _loadChapter(_currentChapterIdx - 1);
    } else {
      SmartDialog.showToast('已经是第一话');
    }
  }

  void _nextChapter() {
    if (_currentChapterIdx < _episodes.length - 1) {
      _loadChapter(_currentChapterIdx + 1);
    } else {
      SmartDialog.showToast('已经是最后一话');
    }
  }

  void _openToc() async {
    final titles = _episodes.map((e) => e.name).toList();
    final picked = await showChapterSheet(context, titles: titles, current: _currentChapterIdx);
    if (picked != null && picked != _currentChapterIdx) {
      _loadChapter(picked);
    }
  }

  void _toggleReadMode() {
    MangaReaderSettings.toggleReadMode();
    MangaReaderSettings.save();
    setState(() { _currentPage = 0; });
    _pageController?.dispose();
    _pageController = PageController(initialPage: 0);
    if (_readMode == MangaReadMode.strip) {
      _resetStripScroll(); // 安全重置
    }
    SmartDialog.showToast('已切换为: ${_readMode.displayName}');
    _saveProgress();
  }

  void _toggleAutoScroll() {
    MangaReaderSettings.toggleAutoScroll();
    MangaReaderSettings.save();
    if (MangaReaderSettings.autoScroll) {
      _startAutoScroll();
    } else {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
    }
    setState(() {});
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    final speed = MangaReaderSettings.autoScrollSpeed;
    if (speed <= 0) return;
    _autoScrollTimer = Timer.periodic(
      Duration(milliseconds: (speed * 1000).round()),
      (timer) {
        if (_readMode == MangaReadMode.strip) {
          if (_stripScrollController.hasClients) {
            final max = _stripScrollController.position.maxScrollExtent;
            final current = _stripScrollController.position.pixels;
            if (current < max) {
              _stripScrollController.animateTo(current + MediaQuery.of(context).size.height * 0.05, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
            } else {
              _nextChapter();
            }
          }
        } else {
          if (_currentPage < _totalPages - 1) {
            _nextPage();
          } else {
            _nextChapter();
          }
        }
      },
    );
  }

  void _zoomIn() {
    setState(() { _scale = (_scale + 0.1).clamp(0.3, 3.0); _saveProgress(); });
  }

  void _zoomOut() {
    setState(() { _scale = (_scale - 0.1).clamp(0.3, 3.0); _saveProgress(); });
  }

  void _resetZoom() {
    setState(() { _scale = 1.0; _saveProgress(); });
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            void refresh() { setSheet(() {}); setState(() {}); MangaReaderSettings.save(); }
            return Container(
              padding: EdgeInsets.fromLTRB(22, 18, 22, 28 + MediaQuery.of(ctx).padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('漫画设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(ctx).colorScheme.onSurface)),
                  const SizedBox(height: 20),
                  Text('阅读模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(ctx).colorScheme.onSurface)),
                  const SizedBox(height: 8),
                  Row(
                    children: MangaReadMode.values.map((mode) {
                      final isSelected = MangaReaderSettings.readMode == mode;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ChoiceChip(
                          label: Text(mode.displayName, style: const TextStyle(fontSize: 13)),
                          selected: isSelected,
                          onSelected: (_) {
                            MangaReaderSettings.readMode = mode;
                            refresh();
                            setState(() {
                              _currentPage = 0;
                              _pageController?.dispose();
                              _pageController = PageController(initialPage: 0);
                              if (mode == MangaReadMode.strip) {
                                _resetStripScroll(); // 安全重置
                              }
                            });
                            SmartDialog.showToast('已切换到: ${mode.displayName}');
                          },
                          selectedColor: Theme.of(ctx).colorScheme.primaryContainer,
                          labelStyle: TextStyle(color: isSelected ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.onSurface),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Text('自动翻页', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(ctx).colorScheme.onSurface))),
                      Switch(
                        value: MangaReaderSettings.autoScroll,
                        onChanged: (v) {
                          MangaReaderSettings.autoScroll = v;
                          refresh();
                          if (v) _startAutoScroll(); else { _autoScrollTimer?.cancel(); _autoScrollTimer = null; }
                        },
                        activeColor: Theme.of(ctx).colorScheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: MangaReaderSettings.autoScrollSpeed,
                          min: 1.0, max: 10.0, divisions: 18,
                          onChanged: (v) {
                            MangaReaderSettings.autoScrollSpeed = v;
                            refresh();
                            if (MangaReaderSettings.autoScroll) _startAutoScroll();
                          },
                          activeColor: Theme.of(ctx).colorScheme.primary,
                          inactiveColor: Theme.of(ctx).colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      Text('${MangaReaderSettings.autoScrollSpeed.toStringAsFixed(1)}s', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(ctx).colorScheme.primary)),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: MangaReaderSettings.speedPresets.map((speed) {
                      final isSelected = (MangaReaderSettings.autoScrollSpeed - speed).abs() < 0.01;
                      return ChoiceChip(
                        label: Text('${speed.toInt()}s', style: const TextStyle(fontSize: 12)),
                        selected: isSelected,
                        onSelected: (_) {
                          MangaReaderSettings.autoScrollSpeed = speed;
                          refresh();
                          if (MangaReaderSettings.autoScroll) _startAutoScroll();
                        },
                        selectedColor: Theme.of(ctx).colorScheme.primaryContainer,
                        labelStyle: TextStyle(color: isSelected ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.onSurface),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _handleTapZone(TapUpDetails details) {
    if (_loading) return;
    final size = MediaQuery.sizeOf(context);
    final x = details.localPosition.dx / size.width;
    if (x < 1 / 3) {
      _prevPage();
    } else if (x > 2 / 3) {
      _nextPage();
    } else {
      _toggleToolbar();
    }
  }

  void _toggleToolbar() {
    setState(() { _toolbar = !_toolbar; });
    try {
      SystemChrome.setEnabledSystemUIMode(_toolbar ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final hasContent = _imageUrls.isNotEmpty;
    final safePadding = MediaQuery.of(context).padding;
    final screenSize = MediaQuery.sizeOf(context);

    const Color darkBackground = Colors.black;
    const Color appBarIconColor = Colors.white;
    const Color appBarTextColor = Colors.white70;
    const Color appBarSubTextColor = Colors.white60;

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _onBackPressed();
      },
      child: Scaffold(
        backgroundColor: darkBackground,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _handleTapZone,
                child: SafeArea(
                  bottom: false,
                  child: _loading
                      ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                      : _error != null
                          ? _errorView(_error!, retry: () => _loadChapter(_currentChapterIdx))
                          : hasContent
                              ? _buildContent(screenSize)
                              : Center(child: Text('暂无图片', style: TextStyle(color: appBarTextColor))),
                ),
              ),
            ),
            if (NovelReaderSettings.screenDim > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(color: Colors.black.withValues(alpha: NovelReaderSettings.screenDim)),
                ),
              ),
            // 顶部栏
            Positioned(
              top: 0, left: 0, right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: Matrix4.translationValues(0, _toolbar ? 0 : -100, 0),
                padding: EdgeInsets.only(top: safePadding.top, left: 8, right: 8, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 19), color: appBarIconColor, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 40, minHeight: 40), onPressed: _onBackPressed),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_vodName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: appBarTextColor, height: 1.2), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (_episodes.isNotEmpty)
                            Text(_episodes[_currentChapterIdx].name, style: const TextStyle(fontSize: 12, color: appBarSubTextColor, height: 1.2), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: appBarIconColor, size: 24),
                      tooltip: '阅读设置',
                      color: Colors.grey[850],
                      onSelected: (value) { if (value == 'settings') _showSettings(); },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(value: 'settings', child: Row(children: [Icon(Icons.settings_outlined, size: 20, color: Colors.white70), SizedBox(width: 10), Text('阅读设置', style: TextStyle(color: Colors.white70))])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // 底部栏
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: Matrix4.translationValues(0, _toolbar ? 0 : 220, 0),
                padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + safePadding.bottom),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, -4))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_readMode != MangaReadMode.strip) ...[
                      Row(
                        children: [
                          Text('${_currentPage + 1}', style: const TextStyle(fontSize: 13, color: appBarTextColor, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Slider(
                              value: _totalPages > 1 ? _currentPage.toDouble() : 0,
                              min: 0, max: (_totalPages - 1).toDouble().clamp(0, double.infinity),
                              onChanged: (v) {
                                final target = v.round().clamp(0, _totalPages - 1);
                                _pageController?.jumpToPage(target);
                                _onPageChanged(target);
                              },
                              activeColor: appBarTextColor, inactiveColor: Colors.white30, thumbColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('$_totalPages', style: const TextStyle(fontSize: 13, color: appBarTextColor, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Text('共 $_totalPages 页', style: const TextStyle(fontSize: 13, color: appBarSubTextColor)),
                          const Spacer(),
                          Text('条漫模式', style: const TextStyle(fontSize: 12, color: appBarTextColor)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('缩放', style: TextStyle(fontSize: 12, color: appBarSubTextColor)),
                        const SizedBox(width: 16),
                        _buildZoomButton(Icons.remove, _zoomOut),
                        const SizedBox(width: 12),
                        Text('${(_scale * 100).toInt()}%', style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 12),
                        _buildZoomButton(Icons.add, _zoomIn),
                        const SizedBox(width: 16),
                        _buildResetButton(_resetZoom),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildActionBtn(icon: Icons.skip_previous, label: '上一话', onTap: _prevChapter, color: appBarTextColor),
                        _buildActionBtn(icon: Icons.list_alt, label: '目录', onTap: _openToc, color: appBarTextColor),
                        _buildActionBtn(
                          icon: MangaReaderSettings.autoScroll ? Icons.pause_circle_outline : Icons.play_circle_outline,
                          label: MangaReaderSettings.autoScroll ? '暂停' : '自动',
                          onTap: _toggleAutoScroll,
                          color: MangaReaderSettings.autoScroll ? theme.primaryColor : appBarTextColor,
                        ),
                        _buildActionBtn(
                          icon: _readMode == MangaReadMode.horizontal ? Icons.swap_horiz : _readMode == MangaReadMode.vertical ? Icons.swap_vert : Icons.view_day,
                          label: '模式',
                          onTap: _toggleReadMode,
                          color: appBarTextColor,
                        ),
                        _buildActionBtn(icon: Icons.skip_next, label: '下一话', onTap: _nextChapter, color: appBarTextColor),
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

  Widget _buildZoomButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  Widget _buildResetButton(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
        child: const Text('重置', style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildActionBtn({required IconData icon, required String label, required VoidCallback? onTap, required Color color}) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: disabled ? color.withValues(alpha: 0.25) : color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: disabled ? color.withValues(alpha: 0.25) : color.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Size screenSize) {
    switch (_readMode) {
      case MangaReadMode.vertical:
        return _buildVerticalMode(screenSize);
      case MangaReadMode.horizontal:
        return _buildHorizontalMode(screenSize);
      case MangaReadMode.strip:
        return _buildStripMode(screenSize);
    }
  }

  Widget _buildVerticalMode(Size screenSize) {
    _pageController ??= PageController(initialPage: _currentPage);
    return PageView.builder(
      controller: _pageController,
      itemCount: _totalPages,
      onPageChanged: _onPageChanged,
      scrollDirection: Axis.vertical,
      itemBuilder: (context, index) => _buildImageItem(screenSize, index),
    );
  }

  Widget _buildHorizontalMode(Size screenSize) {
    _pageController ??= PageController(initialPage: _currentPage);
    return PageView.builder(
      controller: _pageController,
      itemCount: _totalPages,
      onPageChanged: _onPageChanged,
      scrollDirection: Axis.horizontal,
      itemBuilder: (context, index) => _buildImageItem(screenSize, index),
    );
  }

  // 条漫模式：ClipRect + SingleChildScrollView + Transform.scale
  Widget _buildStripMode(Size screenSize) {
    return ClipRect(
      child: SingleChildScrollView(
        controller: _stripScrollController,
        child: Transform.scale(
          scale: _scale,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _imageUrls.map((url) {
              return Image.network(
                url,
                width: screenSize.width,
                fit: BoxFit.fitWidth,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3)));
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    constraints: const BoxConstraints(minHeight: 100),
                    width: screenSize.width,
                    color: Colors.white.withValues(alpha: 0.05),
                    child: const Center(child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.white30)),
                  );
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildImageItem(Size screenSize, int index) {
    if (index >= _imageUrls.length) return const SizedBox.shrink();
    final url = _imageUrls[index];
    final bool isStrip = _readMode == MangaReadMode.strip;

    if (isStrip) {
      return const SizedBox.shrink();
    }

    return Container(
      width: screenSize.width,
      height: screenSize.height,
      color: Colors.transparent,
      child: ClipRect(
        child: Center(
          child: Transform.scale(
            scale: _scale,
            alignment: Alignment.center,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: SizedBox(
                    width: 40, height: 40,
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                      color: _theme.primaryColor,
                      strokeWidth: 3,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 200,
                  width: screenSize.width,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image_outlined, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                      const SizedBox(height: 8),
                      Text('图片加载失败', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView(String msg, {required VoidCallback retry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6)),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: retry,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white70)),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}