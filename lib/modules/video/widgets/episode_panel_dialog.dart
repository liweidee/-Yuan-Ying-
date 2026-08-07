import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/button/icon_button.dart';
import 'package:yuanying/common/widgets/scroll_behavior.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/modules/video/controllers/intro_controller.dart';
import 'package:yuanying/t4/models/video_detail.dart';

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
  late final TabController _sourceTabController;
  late final RxInt _currentTabIndex;
  late final RxInt _currentItemIndex;
  late final List<ScrollController> _itemScrollControllers;
  late final List<bool> _isReversed;
  late final int _initialTabIndex;

  final RxInt _groupCount = 1.obs;

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

  List<Episode> _getGroupedEpisodes(int tabIndex, int groupIndex) {
    final all = _getCurrEpisodes(tabIndex);
    final total = all.length;
    if (total <= 50) return all;
    final start = groupIndex * 50;
    final end = (start + 50).clamp(0, total);
    return all.sublist(start, end);
  }

  void _updateGroupCount(int tabIndex) {
    final total = _getCurrEpisodes(tabIndex).length;
    final newCount = (total + 49) ~/ 50;
    if (_groupCount.value != newCount) {
      _groupCount.value = newCount > 0 ? newCount : 1;
    }
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

    _sourceTabController = TabController(
      initialIndex: _initialTabIndex,
      length: sourceNames.length > 1 ? sourceNames.length : 1,
      vsync: this,
    );
    _currentTabIndex = _sourceTabController.index.obs;
    _currentItemIndex = _findCurrentItemIndexInSource(_initialTabIndex).obs;

    _sourceTabController.addListener(() {
      final newTabIndex = _sourceTabController.index;
      _currentTabIndex.value = newTabIndex;
      _introController.switchDisplaySource(newTabIndex);
      final newIndex = _findCurrentItemIndexInSource(newTabIndex);
      if (_currentItemIndex.value != newIndex) {
        _currentItemIndex.value = newIndex;
      }
      _updateGroupCount(newTabIndex);
    });

    final sourceCount = sourceNames.length > 1 ? sourceNames.length : 1;
    _itemScrollControllers = List.generate(
      sourceCount,
      (i) => ScrollController(initialScrollOffset: 0),
      growable: false,
    );
    _isReversed = List.filled(sourceCount, false);

    _updateGroupCount(_initialTabIndex);
  }

  @override
  void dispose() {
    _sourceTabController.dispose();
    for (final e in _itemScrollControllers) {
      e.dispose();
    }
    _currentItemIndex.close();
    _groupCount.close();
    super.dispose();
  }

  void _animToTopOrBottom({bool top = true}) {
    final tabIndex = _currentTabIndex.value;
    final groupIndex = _getCurrentGroupIndex();
    final episodes = _getGroupedEpisodes(tabIndex, groupIndex);
    final maxOffset = ((episodes.length / 3).ceil() * 52 + 7).toDouble();
    final target = top ^ _isReversed[tabIndex] ? 0.0 : maxOffset;
    _itemScrollControllers[tabIndex].animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  int _getCurrentGroupIndex() {
    final defaultController = DefaultTabController.maybeOf(context);
    if (defaultController != null && defaultController.length > 1) {
      return defaultController.index;
    }
    return 0;
  }

  void _jumpToCurrent() {
    final tabIndex = _currentTabIndex.value;
    final all = _getCurrEpisodes(tabIndex);
    final currentIndex = all.indexWhere(
      (e) => e.name == _introController.currentPlayEpisode?.name,
    );
    if (currentIndex == -1) return;
    final groupIndex = currentIndex ~/ 50;
    final localIndex = currentIndex % 50;

    final total = all.length;
    if (total > 50) {
      final defaultController = DefaultTabController.maybeOf(context);
      if (defaultController != null && defaultController.length > groupIndex) {
        defaultController.animateTo(groupIndex);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _itemScrollControllers[tabIndex].jumpTo(
          (localIndex / 3).floor() * 52 + 7,
        );
      } catch (_) {}
    });
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
            Container(
              height: 44,
              child: TabBar(
                controller: _sourceTabController,
                tabAlignment: TabAlignment.start, 
                padding: EdgeInsets.zero,
                isScrollable: true,
                labelStyle: const TextStyle(fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontSize: 12),
                tabs: sourceNames.map((name) => Tab(text: name)).toList(),
                dividerHeight: 1,
                dividerColor: theme.dividerColor.withValues(alpha: 0.1),
              ),
            ),
          Obx(() {
            final tabIndex = _currentTabIndex.value;
            final allEpisodes = _getCurrEpisodes(tabIndex);
            final total = allEpisodes.length;
            final showGroupTabs = total > 50;
            final itemIndex = _currentItemIndex.value;
            final groupCount = _groupCount.value;

            Widget buildDirectContent() {
              return _buildEpisodeGrid(
                episodes: allEpisodes,
                allEpisodes: allEpisodes,
                tabIndex: tabIndex,
                itemIndex: itemIndex,
                isWide: isWide,
                theme: theme,
                colorScheme: colorScheme,
              );
            }

            Widget buildGroupedContent() {
              return DefaultTabController(
                key: ValueKey('group_${tabIndex}_$groupCount'),
                length: groupCount,
                initialIndex: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Container(
                      height: 34,
                      child: TabBar(
                        tabAlignment: TabAlignment.start,
                        isScrollable: true,
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), 
                        unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                        labelColor: colorScheme.primary,
                        unselectedLabelColor: colorScheme.onSurfaceVariant,
                        indicatorSize: TabBarIndicatorSize.label,
                        indicatorWeight: 1.5,
                        dividerColor: Colors.transparent,
                        dividerHeight: 0,
                        tabs: List.generate(groupCount, (index) {
                          final start = index * 50 + 1;
                          final end = (start + 49).clamp(0, total);
                          return Tab(text: '$start-$end');
                        }),
                        onTap: (index) {
                          _itemScrollControllers[tabIndex].animateTo(
                            0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: List.generate(groupCount, (groupIdx) {
                          final groupEpisodes = _getGroupedEpisodes(tabIndex, groupIdx);
                          return _buildEpisodeGrid(
                            episodes: groupEpisodes,
                            allEpisodes: allEpisodes,
                            tabIndex: tabIndex,
                            itemIndex: itemIndex,
                            isWide: isWide,
                            theme: theme,
                            colorScheme: colorScheme,
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (showGroupTabs) {
              if (isWide) {
                return Expanded(child: buildGroupedContent());
              } else {
                // 移动端分组：固定高度，内部垂直滚动网格
                return SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: buildGroupedContent(),
                );
              }
            } else {
              return buildDirectContent();
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
            '全部剧集',
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
            onPressed: _jumpToCurrent,
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

  Widget _buildEpisodeGrid({
    required List<Episode> episodes,
    required List<Episode> allEpisodes,
    required int tabIndex,
    required int itemIndex,
    required bool isWide,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    if (isWide) {
      // 桌面端保持4列网格垂直滚动
      return ScrollConfiguration(
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
                  final globalIndex = allEpisodes.indexOf(episode);
                  final isCurrentIndex =
                      tabIndex == _introController.currentSourceIndex.value &&
                      globalIndex == itemIndex;
                  return _buildEpisodeItem(
                    theme: theme,
                    episode: episode,
                    isCurrentIndex: isCurrentIndex,
                    globalIndex: globalIndex,
                  );
                },
              ),
            ),
            SliverToBoxAdapter(child: const SizedBox(height: 8)),
          ],
        ),
      );
    } else {
      // 移动端改为3列网格垂直滚动
      return GridView.builder(
        controller: _itemScrollControllers[tabIndex],
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.4,
        ),
        itemCount: episodes.length,
        itemBuilder: (context, index) {
          final episode = episodes[index];
          final globalIndex = allEpisodes.indexOf(episode);
          final isCurrentIndex =
              tabIndex == _introController.currentSourceIndex.value &&
              globalIndex == itemIndex;
          return _buildEpisodeItem(
            theme: theme,
            episode: episode,
            isCurrentIndex: isCurrentIndex,
            globalIndex: globalIndex,
          );
        },
      );
    }
  }

  Widget _buildEpisodeItem({
    required ThemeData theme,
    required Episode episode,
    required bool isCurrentIndex,
    required int globalIndex,
    bool horizontal = false,
  }) {
    final colorScheme = theme.colorScheme;
    final primary = colorScheme.primary;

    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Future.microtask(() {
          _detailController.switchEpisode(globalIndex);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        constraints: BoxConstraints(
          minWidth: horizontal ? 64 : 80,
          maxWidth: horizontal ? 100 : 120,
        ),
        decoration: BoxDecoration(
          color: isCurrentIndex
              ? primary.withValues(alpha: 0.12)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: isCurrentIndex
              ? Border.all(color: primary, width: 1.2)
              : Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.12),
                  width: 0.5,
                ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isCurrentIndex)
                Icon(
                  Icons.play_circle_outline,
                  size: 14,
                  color: primary,
                ),
              if (isCurrentIndex) const SizedBox(width: 4),
              Flexible(
                child: Text(
                  episode.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: isCurrentIndex ? primary : colorScheme.onSurface,
                    fontWeight: isCurrentIndex ? FontWeight.w600 : FontWeight.normal,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}