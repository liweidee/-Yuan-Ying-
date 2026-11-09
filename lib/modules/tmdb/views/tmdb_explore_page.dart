// lib/modules/tmdb/views/tmdb_explore_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/tmdb/controllers/tmdb_explore_controller.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';

/// TMDB 探索页
///
/// 结构：
///   AppBar（标题 + 时间筛选菜单 + 搜索框）
///   ├─ TabBar（热门/电影/剧集/演员，搜索态隐藏）
///   └─ IndexedStack
///        ├─ TabBarView（4 个趋势 Tab，支持左右滑动）
///        └─ 搜索结果视图
///
/// 用 IndexedStack 保证切换搜索态时 TabBarView 的 State 不被销毁，
/// 各 Tab 的滚动位置和数据完全保留。
class TmdbExplorePage extends StatefulWidget {
  const TmdbExplorePage({super.key});

  @override
  State<TmdbExplorePage> createState() => _TmdbExplorePageState();
}

class _TmdbExplorePageState extends State<TmdbExplorePage>
    with SingleTickerProviderStateMixin {
  late final TmdbExploreController controller;
  late final TabController _tabCtrl;
  final TextEditingController _searchCtrl = TextEditingController();

  static const _tabs = ['热门', '电影', '剧集', '演员'];

  @override
  void initState() {
    super.initState();
    controller = Get.put(TmdbExploreController());
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      // backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'TMDB 探索',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: colorScheme.onSurface),
          onPressed: () => Get.back(),
        ),
        actions: [_buildTimeFilter(colorScheme)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _buildSearchBar(colorScheme),
          ),
        ),
      ),
      body: Obx(() {
        if (!controller.hasToken) return _buildNoToken(colorScheme);
        // 读取 timeWindow 建立依赖：切换时 TabBarView 的 children 用新 key 重建
        final tw = controller.timeWindow.value;
        final bgActive = SettingPref.bgActive;
        return Column(
          children: [
            if (!controller.isSearchMode)
              Material(
                color: bgActive ? Colors.transparent : colorScheme.surface,
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: colorScheme.outline,
                  indicatorColor: colorScheme.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 14),
                  tabs: _tabs.map((t) => Tab(text: t)).toList(),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: controller.isSearchMode ? 1 : 0,
                children: [
                  TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _TrendingTabView(
                        key: ValueKey('trending-0-$tw'),
                        index: 0,
                        controller: controller,
                      ),
                      _TrendingTabView(
                        key: ValueKey('trending-1-$tw'),
                        index: 1,
                        controller: controller,
                      ),
                      _TrendingTabView(
                        key: ValueKey('trending-2-$tw'),
                        index: 2,
                        controller: controller,
                      ),
                      _TrendingTabView(
                        key: ValueKey('trending-3-$tw'),
                        index: 3,
                        controller: controller,
                      ),
                    ],
                  ),
                  _buildSearchBody(colorScheme),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  // ===== 时间筛选菜单 =====
  Widget _buildTimeFilter(ColorScheme colorScheme) {
    return Obx(() {
      if (controller.isSearchMode) return const SizedBox.shrink();
      return PopupMenuButton<String>(
        icon: Icon(Icons.tune, color: colorScheme.onSurface),
        tooltip: '时间筛选',
        initialValue: controller.timeWindow.value,
        onSelected: controller.setTimeWindow,
        itemBuilder: (context) => [
          _timeMenuItem('week', '本周趋势', colorScheme),
          _timeMenuItem('day', '今日趋势', colorScheme),
        ],
      );
    });
  }

  PopupMenuItem<String> _timeMenuItem(
      String value, String label, ColorScheme colorScheme) {
    final selected = controller.timeWindow.value == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          if (selected)
            Icon(Icons.check, size: 18, color: colorScheme.primary)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  // ===== 搜索框 + 按钮 =====
  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Obx(() {
      final isSearch = controller.isSearchMode;
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: controller.onSearchChanged,
              onSubmitted: (_) => controller.submitSearch(),
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: '搜索电影、剧集、演员...',
                hintStyle: TextStyle(color: colorScheme.outline),
                prefixIcon: Icon(Icons.search, color: colorScheme.outline),
                suffixIcon: isSearch
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            color: colorScheme.outline, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          controller.clearSearch();
                        },
                      )
                    : null,
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerHighest.withOpacity(0.4),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: controller.submitSearch,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('搜索', style: TextStyle(fontSize: 13)),
          ),
        ],
      );
    });
  }

  // ===== 搜索结果 =====
  Widget _buildSearchBody(ColorScheme colorScheme) {
    return Obx(() {
      if (controller.searchLoading.value &&
          controller.searchResults.isEmpty) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      if (controller.searchError.value.isNotEmpty &&
          controller.searchResults.isEmpty) {
        return _buildError(
            colorScheme, controller.searchError.value, controller.submitSearch);
      }
      if (controller.searchResults.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 48, color: colorScheme.outline),
              const SizedBox(height: 12),
              Text('未找到相关结果',
                  style: TextStyle(color: colorScheme.outline)),
            ],
          ),
        );
      }
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 300) {
            controller.loadMoreSearch();
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: controller.searchResults.length +
              (controller.searchLoading.value ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index >= controller.searchResults.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final item =
                controller.searchResults[index] as Map<String, dynamic>;
            final mt = item['media_type'] as String?;
            if (mt == 'person') {
              return _buildPersonResultCard(item, colorScheme);
            }
            return _buildMediaResultCard(item, colorScheme);
          },
        ),
      );
    });
  }

  Widget _buildMediaResultCard(
      Map<String, dynamic> item, ColorScheme colorScheme) {
    final title =
        item['title'] as String? ?? item['name'] as String? ?? '未知';
    final poster = item['poster_path'] as String?;
    final date = item['release_date'] as String? ??
        item['first_air_date'] as String? ??
        '';
    final vote = (item['vote_average'] as num?)?.toDouble();
    final mt = item['media_type'] as String? ?? 'movie';
    final overview = item['overview'] as String? ?? '';
    final imgUrl = controller.imageUrl(poster, size: 'w185');

    return GestureDetector(
      onTap: () => controller.onItemTap(item),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 70,
                height: 100,
                color: colorScheme.surfaceContainerHighest,
                child: imgUrl.isNotEmpty
                    ? Image.network(
                        imgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                            mt == 'movie' ? Icons.movie : Icons.tv,
                            size: 30,
                            color: colorScheme.outline),
                      )
                    : Icon(mt == 'movie' ? Icons.movie : Icons.tv,
                        size: 30, color: colorScheme.outline),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (date.isNotEmpty)
                        Text(date.split('-').first,
                            style: TextStyle(
                                fontSize: 11, color: colorScheme.outline)),
                      if (date.isNotEmpty && vote != null)
                        const SizedBox(width: 8),
                      if (vote != null) ...[
                        const Icon(Icons.star, size: 12, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(vote.toStringAsFixed(1),
                            style: TextStyle(
                                fontSize: 11, color: colorScheme.outline)),
                      ],
                    ],
                  ),
                  if (overview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      overview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                mt == 'movie' ? '电影' : '剧集',
                style: TextStyle(fontSize: 10, color: colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonResultCard(
      Map<String, dynamic> item, ColorScheme colorScheme) {
    final name = item['name'] as String? ?? '未知';
    final profile = item['profile_path'] as String?;
    final dept = item['known_for_department'] as String?;
    final imgUrl = controller.imageUrl(profile, size: 'w185');

    return GestureDetector(
      onTap: () => controller.onItemTap(item),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Container(
                width: 60,
                height: 60,
                color: colorScheme.surfaceContainerHighest,
                child: imgUrl.isNotEmpty
                    ? Image.network(
                        imgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(Icons.person,
                            color: colorScheme.outline),
                      )
                    : Icon(Icons.person, color: colorScheme.outline),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _deptLabel(dept),
                    style:
                        TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('演员',
                  style: TextStyle(fontSize: 10, color: colorScheme.primary)),
            ),
          ],
        ),
      ),
    );
  }

  String _deptLabel(String? dept) {
    switch (dept) {
      case 'Acting':
        return '演员';
      case 'Directing':
        return '导演';
      case 'Writing':
        return '编剧';
      case 'Production':
        return '制片';
      default:
        return dept ?? '人物';
    }
  }

  // ===== 通用错误 / 无 Token =====
  Widget _buildError(
      ColorScheme colorScheme, String msg, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.outline, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _buildNoToken(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.vpn_key, size: 48, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              '请先在「设置 → TMDB 配置」中填写 Access Token',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.outline, fontSize: 14),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Get.toNamed('/tmdbConfig'),
              child: const Text('去配置'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 单个趋势 Tab（独立 initState / 独立 Obx / 独立滚动监听）
// ============================================================================
class _TrendingTabView extends StatefulWidget {
  final int index;
  final TmdbExploreController controller;

  const _TrendingTabView({
    super.key,
    required this.index,
    required this.controller,
  });

  @override
  State<_TrendingTabView> createState() => _TrendingTabViewState();
}

class _TrendingTabViewState extends State<_TrendingTabView> {
  @override
  void initState() {
    super.initState();
    // 首帧后触发加载，避免 build 过程中同步 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.ensureTabLoaded(widget.index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Obx(() {
      final state = widget.controller.stateOf(widget.index);
      if (state.loading.value && state.items.isEmpty) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      if (state.error.value.isNotEmpty && state.items.isEmpty) {
        return _buildError(colorScheme, state.error.value);
      }
      if (state.items.isEmpty) {
        return Center(
          child: Text('暂无数据',
              style: TextStyle(color: colorScheme.outline)),
        );
      }

      final isPerson = widget.index == 3;
      return RefreshIndicator(
        onRefresh: () => widget.controller.retryTrending(widget.index),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 300) {
              widget.controller.loadMoreTrending(widget.index);
            }
            return false;
          },
          child: GridView.builder(
            controller: state.scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: isPerson ? 110 : 140,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: isPerson ? 0.7 : 0.52,
            ),
            itemCount: state.items.length + (state.loading.value ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= state.items.length) {
                return const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final item = state.items[index] as Map<String, dynamic>;
              return isPerson
                  ? _buildPersonCard(item, colorScheme)
                  : _buildMediaCard(item, colorScheme);
            },
          ),
        ),
      );
    });
  }

  Widget _buildMediaCard(
      Map<String, dynamic> item, ColorScheme colorScheme) {
    final title =
        item['title'] as String? ?? item['name'] as String? ?? '未知';
    final poster = item['poster_path'] as String?;
    final date = item['release_date'] as String? ??
        item['first_air_date'] as String? ??
        '';
    final vote = (item['vote_average'] as num?)?.toDouble();
    final mediaType = item['media_type'] as String? ?? 'movie';
    final imgUrl = widget.controller.imageUrl(poster, size: 'w342');

    return GestureDetector(
      onTap: () => widget.controller.onItemTap(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    color: colorScheme.surfaceContainerHighest,
                    child: imgUrl.isNotEmpty
                        ? Image.network(
                            imgUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(Icons.movie,
                                  color: colorScheme.outline, size: 32),
                            ),
                          )
                        : Center(
                            child: Icon(Icons.movie,
                                color: colorScheme.outline, size: 32),
                          ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      mediaType == 'tv' ? '剧集' : '电影',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (date.isNotEmpty) ...[
                Text(
                  date.split('-').first,
                  style: TextStyle(fontSize: 10, color: colorScheme.outline),
                ),
                if (vote != null) const SizedBox(width: 4),
              ],
              if (vote != null) ...[
                const Icon(Icons.star, size: 10, color: Colors.amber),
                const SizedBox(width: 2),
                Text(
                  vote.toStringAsFixed(1),
                  style: TextStyle(fontSize: 10, color: colorScheme.outline),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPersonCard(
      Map<String, dynamic> item, ColorScheme colorScheme) {
    final name = item['name'] as String? ?? '未知';
    final profile = item['profile_path'] as String?;
    final imgUrl = widget.controller.imageUrl(profile, size: 'w185');

    return GestureDetector(
      onTap: () => widget.controller.onItemTap(item),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipOval(
                  child: Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: imgUrl.isNotEmpty
                        ? Image.network(
                            imgUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.person,
                                color: colorScheme.outline,
                                size: 40),
                          )
                        : Icon(Icons.person,
                            color: colorScheme.outline, size: 40),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme colorScheme, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.outline, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () =>
                  widget.controller.retryTrending(widget.index),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}