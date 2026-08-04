import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/button/icon_button.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/modules/video/controllers/intro_controller.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/common/widgets/scroll_behavior.dart';

class EpisodePanelDialog extends StatefulWidget {
  final bool isWide;
  final String controllerTag;

  const EpisodePanelDialog({
    super.key,
    this.isWide = false,
    required this.controllerTag,
  });

  @override
  State<EpisodePanelDialog> createState() => _EpisodePanelDialogState();
}

class _EpisodePanelDialogState extends State<EpisodePanelDialog>
    with TickerProviderStateMixin {
  late final DetailController _detailController;
  late final IntroController _introController;
  late final TabController _tabController;
  late final RxInt _currentTabIndex;
  late final RxInt _currentItemIndex; // 改为 RxInt
  late final List<ScrollController> _itemScrollControllers;
  late final List<bool> _isReversed;
  late final int _initialTabIndex;

  // 不再使用 getter，直接在 Obx 中获取数据
  List<Episode> _getCurrEpisodes(int tabIndex) {
    final source = _introController.getSource(tabIndex);
    return source?.episodes ?? [];
  }

  int _findCurrentItemIndexInSource(int sourceIndex) {
    final episodes = _introController.getSource(sourceIndex)?.episodes ?? [];
    if (episodes.isEmpty) return -1;
    final currentEpisode = _introController.currentPlayEpisode;
    if (currentEpisode == null) return -1;
    final index = episodes.indexWhere((e) => e.name == currentEpisode.name);
    return index;
  }

  @override
  void initState() {
    super.initState();
    _detailController = Get.find<DetailController>(tag: widget.controllerTag);
    _introController = _detailController.introController;

    final sourceNames = _introController.sourceNames;
    _initialTabIndex = _introController.displaySourceIndex.value.clamp(
      0,
      sourceNames.length - 1,
    );

    _tabController = TabController(
      initialIndex: _initialTabIndex,
      length: sourceNames.length > 1 ? sourceNames.length : 1,
      vsync: this,
    );
    _currentTabIndex = _tabController.index.obs;
    _currentItemIndex = _findCurrentItemIndexInSource(_initialTabIndex).obs;

    _tabController.addListener(() {
      final newTabIndex = _tabController.index;
      _currentTabIndex.value = newTabIndex;
      _introController.switchDisplaySource(newTabIndex);
      final newIndex = _findCurrentItemIndexInSource(newTabIndex);
      if (_currentItemIndex.value != newIndex) {
        _currentItemIndex.value = newIndex;
      }
    });

    final sourceCount = sourceNames.length > 1 ? sourceNames.length : 1;
    _itemScrollControllers = List.generate(
      sourceCount,
      (i) => ScrollController(initialScrollOffset: 0),
      growable: false,
    );
    _isReversed = List.filled(sourceCount, false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final e in _itemScrollControllers) {
      e.dispose();
    }
    _currentItemIndex.close();
    super.dispose();
  }

  void _animToTopOrBottom({bool top = true}) {
    final tabIndex = _currentTabIndex.value;
    final episodes = _getCurrEpisodes(tabIndex);
    final maxOffset = ((episodes.length / 3).ceil() * 52 + 7).toDouble();
    final target = top ^ _isReversed[tabIndex] ? 0.0 : maxOffset;
    _itemScrollControllers[tabIndex].animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  void _jumpToCurrent() {
    final tabIndex = _currentTabIndex.value;
    if (_currentItemIndex.value == -1) return;
    try {
      _itemScrollControllers[tabIndex].jumpTo(
        (_currentItemIndex.value / 3).floor() * 52 + 7,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sourceNames = _introController.sourceNames;
    final isMulti = sourceNames.length > 1;
    final isWide = widget.isWide;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: isWide
            ? const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              )
            : const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (!isWide) ...[
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                decoration: BoxDecoration(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
          _buildToolbar(theme, isWide),
          if (isMulti)
            TabBar(
              controller: _tabController,
              padding: const EdgeInsets.only(right: 60),
              isScrollable: true,
              labelStyle: const TextStyle(fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: sourceNames.map((name) => Tab(text: name)).toList(),
              dividerHeight: 1,
              dividerColor: theme.dividerColor.withValues(alpha: 0.1),
            ),
          // ===== 关键修复：用 Obx 包裹列表，依赖 _currentTabIndex 和 _currentItemIndex =====
          Obx(() {
            final tabIndex = _currentTabIndex.value;
            final episodes = _getCurrEpisodes(tabIndex);
            final itemIndex = _currentItemIndex.value;

            if (isWide) {
              return Expanded(
                child: ScrollConfiguration(
                  behavior: const NoScrollbarBehavior(),
                  child: CustomScrollView(
                    reverse: _isReversed[tabIndex],
                    controller: _itemScrollControllers[tabIndex],
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        sliver: SliverGrid.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 2.4,
                          ),
                          itemCount: episodes.length,
                          itemBuilder: (context, index) {
                            final episode = episodes[index];
                            final isCurrentIndex = tabIndex == _introController.currentSourceIndex.value && index == itemIndex;
                            return _buildEpisodeItem(
                              theme: theme,
                              episode: episode,
                              index: index,
                              isCurrentIndex: isCurrentIndex,
                            );
                          },
                        ),
                      ),
                      SliverToBoxAdapter(child: const SizedBox(height: 8)),
                    ],
                  ),
                ),
              );
            } else {
              return SizedBox(
                height: 60,
                child: ScrollConfiguration(
                  behavior: const NoScrollbarBehavior(),
                  child: ListView.builder(
                    controller: _itemScrollControllers[tabIndex],
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      final isCurrentIndex = tabIndex == _introController.currentSourceIndex.value && index == itemIndex;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildEpisodeItem(
                          theme: theme,
                          episode: episode,
                          index: index,
                          isCurrentIndex: isCurrentIndex,
                          horizontal: true,
                        ),
                      );
                    },
                  ),
                ),
              );
            }
          }),
        ],
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, bool isWide) {
    final colorScheme = theme.colorScheme;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '合集',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          iconButton(
            iconSize: 18,
            tooltip: '跳至顶部',
            icon: const Icon(Icons.vertical_align_top),
            onPressed: () => _animToTopOrBottom(top: true),
          ),
          iconButton(
            iconSize: 18,
            tooltip: '跳至底部',
            icon: const Icon(Icons.vertical_align_bottom),
            onPressed: () => _animToTopOrBottom(top: false),
          ),
          iconButton(
            iconSize: 18,
            tooltip: '跳至当前',
            icon: const Icon(Icons.my_location),
            onPressed: () {
              final currentTabIndex = _currentTabIndex.value;
              if (currentTabIndex != _initialTabIndex) {
                _tabController.animateTo(_initialTabIndex);
                Future.delayed(const Duration(milliseconds: 225), () {
                  _currentItemIndex.value = _findCurrentItemIndexInSource(_initialTabIndex);
                  _jumpToCurrent();
                });
              } else {
                _jumpToCurrent();
              }
            },
          ),
          Obx(() {
            final tabIndex = _currentTabIndex.value;
            return iconButton(
              iconSize: 18,
              tooltip: _isReversed[tabIndex] ? '顺序' : '倒序',
              icon: !_isReversed[tabIndex]
                  ? const Icon(Icons.sort_by_alpha)
                  : const Icon(Icons.sort_by_alpha),
              onPressed: () => setState(() {
                _isReversed[tabIndex] = !_isReversed[tabIndex];
              }),
            );
          }),
          const SizedBox(width: 4),
          iconButton(
            iconSize: 18,
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeItem({
    required ThemeData theme,
    required Episode episode,
    required int index,
    required bool isCurrentIndex,
    bool horizontal = false,
  }) {
    final colorScheme = theme.colorScheme;
    final primary = colorScheme.primary;

    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Future.microtask(() {
          _detailController.switchEpisode(index);
        });
      },
      child: Container(
        height: 36,
        padding: horizontal ? const EdgeInsets.symmetric(horizontal: 14) : null,
        decoration: BoxDecoration(
          color: isCurrentIndex
              ? primary.withValues(alpha: 0.15)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: isCurrentIndex
              ? Border.all(color: primary, width: 1.5)
              : Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCurrentIndex) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 13,
                  color: isCurrentIndex ? primary : colorScheme.onSurface,
                  fontWeight: isCurrentIndex ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}