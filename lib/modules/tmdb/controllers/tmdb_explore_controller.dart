// lib/modules/tmdb/controllers/tmdb_explore_controller.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:yuanying/modules/setting/controllers/tmdb_config_controller.dart';
import 'package:yuanying/modules/tmdb/views/tmdb_detail_page.dart';
import 'package:yuanying/modules/tmdb/views/tmdb_person_page.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/source_manager.dart';

/// 每个 Tab 的独立状态
class _TabState {
  final items = <dynamic>[].obs;
  final page = 1.obs;
  final hasMore = true.obs;
  final loading = false.obs;
  final error = ''.obs;
  final scrollCtrl = ScrollController();
  bool initialized = false;

  void dispose() {
    scrollCtrl.dispose();
  }
}

/// TMDB 探索页控制器
///
/// - 趋势：4 个 Tab（热门/电影/剧集/演员），每个 Tab 独立分页 + 独立滚动位置
/// - 时间窗口：全局 'week' / 'day'，切换时重置所有 Tab
/// - 搜索：按钮触发（保留回车兜底），独立于 Tab
class TmdbExploreController extends GetxController {
  late final TmdbConfigController _tmdbCtrl =
      Get.isRegistered<TmdbConfigController>()
          ? Get.find<TmdbConfigController>()
          : Get.put(TmdbConfigController());
  final SourceManager _sourceManager = Get.find<SourceManager>();
  final Dio _dio = Dio();

  // ===== 全局时间窗口 =====
  /// 'week' | 'day'
  final timeWindow = 'week'.obs;

  // ===== 搜索状态 =====
  final searchQuery = ''.obs;      // 输入框内容（实时）
  final searchActive = false.obs;  // 是否处于搜索结果视图（提交后为 true）
  final searchResults = <dynamic>[].obs;
  final searchLoading = false.obs;
  final searchError = ''.obs;
  final searchPage = 1.obs;
  final searchHasMore = true.obs;

  bool get isSearchMode => searchActive.value;
  bool get hasToken => _tmdbCtrl.accessToken.value.isNotEmpty;

  // ===== Tab 独立状态 =====
  final _tabStates = <int, _TabState>{
    0: _TabState(), // 热门
    1: _TabState(), // 电影
    2: _TabState(), // 剧集
    3: _TabState(), // 演员
  };

  _TabState stateOf(int index) => _tabStates[index]!;

  /// 请求代际：切换时间窗口时递增，用于丢弃旧请求的返回
  int _trendingEpoch = 0;

  @override
  void onClose() {
    for (final s in _tabStates.values) {
      s.dispose();
    }
    super.onClose();
  }

  // ==========================================================================
  // 趋势
  // ==========================================================================

  /// 首次加载某个 Tab（幂等，只在未初始化时实际发起请求）
  Future<void> ensureTabLoaded(int index) async {
    final state = stateOf(index);
    if (state.initialized) return;
    state.initialized = true;
    await _loadTrending(index, reset: true);
  }

  Future<void> loadMoreTrending(int index) async {
    final state = stateOf(index);
    if (state.loading.value || !state.hasMore.value) return;
    await _loadTrending(index, reset: false);
  }

  Future<void> retryTrending(int index) async {
    stateOf(index).initialized = true;
    await _loadTrending(index, reset: true);
  }

  /// 切换时间窗口：重置所有 Tab，滚动位置归零
  void setTimeWindow(String w) {
    if (timeWindow.value == w) return;
    timeWindow.value = w;
    _trendingEpoch++;
    for (final state in _tabStates.values) {
      try {
        if (state.scrollCtrl.hasClients) {
          state.scrollCtrl.jumpTo(0);
        }
      } catch (_) {}
      state.items.clear();
      state.page.value = 1;
      state.hasMore.value = true;
      state.error.value = '';
      state.loading.value = false;
      state.initialized = false;
    }
  }

  Future<void> _loadTrending(int index, {required bool reset}) async {
    if (!hasToken) {
      stateOf(index).error.value = '请先在「设置 → TMDB 配置」中填写 Access Token';
      return;
    }
    final state = stateOf(index);
    final epoch = _trendingEpoch;

    if (reset) {
      state.page.value = 1;
      state.hasMore.value = true;
      state.items.clear();
    }
    if (!state.hasMore.value && !reset) return;

    state.loading.value = true;
    state.error.value = '';
    try {
      final type = _trendingType(index);
      final base = _tmdbCtrl.apiProxy.value.trim();
      final url = '$base/3/trending/$type/${timeWindow.value}'
          '?language=zh-CN&page=${state.page.value}';
      final resp = await _dio.get(url, options: _authOptions());
      if (epoch != _trendingEpoch) return;
      if (resp.statusCode != 200) {
        state.error.value = '加载趋势失败 (${resp.statusCode})';
        return;
      }
      var list = (resp.data['results'] as List?) ?? [];
      // 热门聚合过滤掉演员
      if (type == 'all') {
        list = list.where((item) {
          final mt = item is Map ? item['media_type'] as String? : null;
          return mt == 'movie' || mt == 'tv';
        }).toList();
      }
      if (reset) {
        state.items.assignAll(list);
      } else {
        state.items.addAll(list);
      }
      state.hasMore.value = list.isNotEmpty;
      state.page.value += 1;
    } on DioException catch (e) {
      if (epoch == _trendingEpoch) {
        state.error.value = '加载趋势失败: ${e.message}';
      }
    } catch (e) {
      if (epoch == _trendingEpoch) {
        state.error.value = '加载趋势失败: $e';
      }
    } finally {
      if (epoch == _trendingEpoch) {
        state.loading.value = false;
      }
    }
  }

  String _trendingType(int index) {
    switch (index) {
      case 1:
        return 'movie';
      case 2:
        return 'tv';
      case 3:
        return 'person';
      default:
        return 'all';
    }
  }

  // ==========================================================================
  // 搜索
  // ==========================================================================

  /// 输入变化：只更新 query；清空时自动退出搜索态
  void onSearchChanged(String q) {
    searchQuery.value = q;
    if (q.trim().isEmpty && searchActive.value) {
      clearSearch();
    }
  }

  /// 按钮 / 回车提交
  void submitSearch() {
    final q = searchQuery.value.trim();
    if (q.isEmpty) return;
    searchActive.value = true;
    _doSearch(reset: true);
  }

  void clearSearch() {
    searchQuery.value = '';
    searchActive.value = false;
    searchResults.clear();
    searchError.value = '';
    searchLoading.value = false;
    searchPage.value = 1;
    searchHasMore.value = true;
  }

  Future<void> loadMoreSearch() async {
    if (searchLoading.value || !searchHasMore.value) return;
    await _doSearch(reset: false);
  }

  Future<void> _doSearch({required bool reset}) async {
    if (!hasToken) {
      searchError.value = '请先在「设置 → TMDB 配置」中填写 Access Token';
      return;
    }
    final q = searchQuery.value.trim();
    if (q.isEmpty) return;

    if (reset) {
      searchPage.value = 1;
      searchHasMore.value = true;
      searchResults.clear();
    }
    if (!searchHasMore.value && !reset) return;

    searchLoading.value = true;
    searchError.value = '';
    try {
      final base = _tmdbCtrl.apiProxy.value.trim();
      final url = '$base/3/search/multi'
          '?query=${Uri.encodeComponent(q)}'
          '&include_adult=false'
          '&language=zh-CN'
          '&page=${searchPage.value}';
      final resp = await _dio.get(url, options: _authOptions());
      if (resp.statusCode != 200) {
        searchError.value = '搜索失败 (${resp.statusCode})';
        return;
      }
      final list = (resp.data['results'] as List?) ?? [];
      final filtered = list.where((item) {
        final mt = item is Map ? item['media_type'] as String? : null;
        return mt == 'movie' || mt == 'tv' || mt == 'person';
      }).toList();
      if (reset) {
        searchResults.assignAll(filtered);
      } else {
        searchResults.addAll(filtered);
      }
      searchHasMore.value = filtered.isNotEmpty;
      searchPage.value += 1;
    } on DioException catch (e) {
      searchError.value = '搜索失败: ${e.message}';
    } catch (e) {
      searchError.value = '搜索失败: $e';
    } finally {
      searchLoading.value = false;
    }
  }

  // ==========================================================================
  // 公共
  // ==========================================================================

  Options _authOptions() => Options(headers: {
        'Authorization': 'Bearer ${_tmdbCtrl.accessToken.value}',
        'Accept': 'application/json',
      });

  /// 图片 URL 拼接（复用 tmdb_config_controller 的 imageProxy）
  String imageUrl(String? path, {String size = 'w342'}) {
    if (path == null || path.isEmpty) return '';
    String base = _tmdbCtrl.imageProxy.value.trim();
    if (base.isEmpty) base = 'https://image.tmdb.org/t/p';
    if (!base.endsWith('/')) base = '$base/';
    String cleanSize = size.startsWith('/') ? size.substring(1) : size;
    if (!cleanSize.endsWith('/')) cleanSize = '$cleanSize/';
    String cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$base$cleanSize$cleanPath';
  }

  /// 点击项：复用现有详情 / 演员页
  void onItemTap(Map<String, dynamic> item) {
    final mediaType = item['media_type'] as String?;

    if (mediaType == 'person') {
      final personId = item['id'] as int?;
      final personName = item['name'] as String? ?? '';
      if (personId != null && personName.isNotEmpty) {
        Get.to(() => TmdbPersonPage(
              personId: personId,
              personName: personName,
            ));
      }
      return;
    }

    if (mediaType != 'movie' && mediaType != 'tv') return;
    final tmdbId = item['id'] as int?;
    if (tmdbId == null) return;
    final title = item['title'] as String? ?? item['name'] as String? ?? '';
    final posterPath = item['poster_path'] as String?;

    final videoItem = VideoItem(
      vodId: 'tmdb_$tmdbId',
      vodName: title,
      vodPic: posterPath != null ? imageUrl(posterPath, size: 'w342') : '',
      vodRemarks: '',
      vodActor: '',
      typeName: '',
      vodTag: '',
    );
    final site = _sourceManager.currentSite.value ?? {};
    Get.to(() => TmdbDetailPage(
          videoItem: videoItem,
          site: site,
          fromHome: false, // 详情页播放按钮自动显示为「搜索」
          tmdbId: tmdbId,
          mediaType: mediaType,
        ));
  }
}