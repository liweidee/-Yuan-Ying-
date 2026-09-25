import 'dart:async';

import 'package:get/get.dart';

import '../models/lx_music_model.dart';
import '../services/lx_hot_search_service.dart';
import '../services/lx_music_search_service.dart';
import '../services/lx_search_suggest_service.dart';
import '../storage/lx_storage.dart';
import '../utils/lx_logger.dart';

/// 洛雪音乐搜索控制器
class LxSearchController extends GetxController {
  final LxMusicSearchService _searchService = LxMusicSearchService.instance;
  final LxHotSearchService _hotSearchService = LxHotSearchService.instance;
  final LxSearchSuggestService _suggestService =
      LxSearchSuggestService.instance;

  final RxString source = 'kw'.obs;
  final RxString query = ''.obs;
  final RxList<LxMusic> results = <LxMusic>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isLoadingMore = false.obs;
  final RxString error = ''.obs;
  final RxInt page = 1.obs;
  final RxBool hasMore = true.obs;

  final RxList<String> searchHistory = <String>[].obs;
  final RxList<String> hotSearches = <String>[].obs;
  final RxBool hotSearchLoading = false.obs;

  final RxList<String> suggestResults = <String>[].obs;
  final RxBool showSuggest = false.obs;

  Timer? _suggestDebounce;

  static const List<String> _defaultHotWords = [
    '周杰伦',
    '林俊杰',
    '陈奕迅',
    '邓紫棋',
    '薛之谦',
  ];

  @override
  void onInit() {
    super.onInit();
    // 延后到微任务，避免 initState/build 期间改 Rx
    Future.microtask(() {
      hotSearches.value = List.from(_defaultHotWords);
      _loadHistory();
      _loadHotSearch();
    });
  }

  @override
  void onClose() {
    _suggestDebounce?.cancel();
    super.onClose();
  }

  // ==================== 搜索 ====================

  Future<void> search(String keyword, {bool resetPage = true}) async {
    if (keyword.trim().isEmpty) return;

    if (resetPage) {
      page.value = 1;
      results.clear();
      hasMore.value = true;
    }

    query.value = keyword;
    isLoading.value = true;
    error.value = '';

    try {
      await _saveHistory(keyword);
      final result = await _searchService.search(
        keyword: keyword,
        source: source.value,
        page: 1,
      );
      results.value = result.list;
      hasMore.value = result.hasMore;
      page.value = 1;
    } catch (e) {
      error.value = e.toString();
      LxLogger.error('搜索失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value || query.value.isEmpty) return;

    isLoadingMore.value = true;
    try {
      final nextPage = page.value + 1;
      final result = await _searchService.search(
        keyword: query.value,
        source: source.value,
        page: nextPage,
      );

      if (result.list.isEmpty) {
        hasMore.value = false;
        return;
      }

      results.addAll(result.list);
      page.value = nextPage;
      hasMore.value = result.hasMore;
    } catch (e) {
      LxLogger.warn('加载更多失败: $e');
    } finally {
      isLoadingMore.value = false;
    }
  }

  void setSource(String newSource) {
    if (source.value == newSource) return;
    source.value = newSource;
    _loadHotSearch();
    if (query.value.isNotEmpty) {
      search(query.value);
    }
  }

  void clear() {
    query.value = '';
    results.clear();
    error.value = '';
    page.value = 1;
    hasMore.value = true;
    showSuggest.value = false;
    suggestResults.clear();
  }

  // ==================== 热搜 ====================

  Future<void> _loadHotSearch() async {
    hotSearchLoading.value = true;
    try {
      final list = await _hotSearchService.getHotSearch(source.value);
      hotSearches.value =
          list.isNotEmpty ? list : List.from(_defaultHotWords);
    } catch (_) {
      hotSearches.value = List.from(_defaultHotWords);
    } finally {
      hotSearchLoading.value = false;
    }
  }

  // ==================== 历史 ====================

  Future<void> _loadHistory() async {
    final history = await LxStorage.instance.getSearchHistory();
    searchHistory.value = history;
  }

  Future<void> _saveHistory(String keyword) async {
    await LxStorage.instance.addSearchHistory(keyword);
    searchHistory.value = await LxStorage.instance.getSearchHistory();
  }

  Future<void> clearHistory() async {
    await LxStorage.instance.clearSearchHistory();
    searchHistory.value = [];
  }

  // ==================== 联想 ====================

  void onQueryChanged(String text) {
    _suggestDebounce?.cancel();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      suggestResults.clear();
      showSuggest.value = false;
      return;
    }
    if (trimmed == query.value) {
      suggestResults.clear();
      showSuggest.value = false;
      return;
    }

    _suggestDebounce =
        Timer(const Duration(milliseconds: 500), () async {
      final serverResults =
          await _suggestService.getSuggestions(source.value, trimmed);

      final lower = trimmed.toLowerCase();
      final historyMatches = searchHistory
          .where((h) => h.toLowerCase().startsWith(lower))
          .toList();

      final seen = <String>{};
      final merged = <String>[];
      for (final h in historyMatches) {
        if (seen.add(h)) merged.add(h);
      }
      for (final s in serverResults) {
        if (seen.add(s)) merged.add(s);
      }

      suggestResults.value = merged.take(20).toList();
      showSuggest.value = suggestResults.isNotEmpty;
    });
  }

  void hideSuggest() {
    _suggestDebounce?.cancel();
    suggestResults.clear();
    showSuggest.value = false;
  }
}