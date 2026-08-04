import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/t4_api_service.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:collection/collection.dart';
import 'package:yuanying/models/common/card_layout_mode.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/t4/services/drpy2_api_service.dart';
import 'package:yuanying/t4/services/catvod_open_service.dart';

// ============================================================================
// 内部辅助类：分页管理
// ============================================================================
class _Pagination {
  int page = 1;
  bool isEnd = false;
  bool isLoadingMore = false;

  void reset() {
    page = 1;
    isEnd = false;
    isLoadingMore = false;
  }

  void nextPage() => page++;
  bool get canLoadMore => !isEnd && !isLoadingMore;
}

// ============================================================================
// 内部辅助类：分类缓存管理
// ============================================================================
class _CategoryCache {
  int page = 1;
  bool isEnd = false;
  List<VideoItem> items = [];
}

class _CacheManager {
  final Map<String, _CategoryCache> _data = {};

  bool contains(String categoryId) => _data.containsKey(categoryId);

  _CategoryCache? get(String categoryId) => _data[categoryId];

  void save(String categoryId, int page, bool isEnd, List<VideoItem> items) {
    _data[categoryId] = _CategoryCache()
      ..page = page
      ..isEnd = isEnd
      ..items = List.from(items);
  }

  void remove(String categoryId) => _data.remove(categoryId);

  void clear() => _data.clear();
}

// ============================================================================
// HomeController（主控制器）
// ============================================================================
class HomeController extends GetxController {
  late ISpiderService _apiService;
  final SourceManager _sourceManager = Get.find<SourceManager>();

  // ===== 公开状态 =====
  final ScrollController scrollController = ScrollController();
  final videoList = <VideoItem>[].obs;
  final categories = <Category>[].obs;
  final currentCategory = Rx<Category?>(null);
  final hasFilter = false.obs;
  final filters = <String, List<FilterGroup>>{}.obs;
  final currentFilterValues = <String, String>{}.obs;
  final filterBarVisibility = <String, bool>{}.obs;
  final isLoading = false.obs;
  final isSwitchingSource = false.obs;
  final isHomeLoading = false.obs;
  final isHomeError = false.obs;
  final errorMsg = ''.obs;
  final cardLayoutMode = CardLayoutMode.grid3.obs;
  final RxBool hideTopBar = SettingPref.hideTopBar.obs;

  // ===== 内部状态（封装） =====
  final _pagination = _Pagination();
  final _cache = _CacheManager();

  // ===== 请求版本号（核心防竞态） =====
  int _requestId = 0;

  // 记录上一次加载更多时的最后一项（用于检测分页无效）
  VideoItem? _lastLoadedItem;
  int _lastLoadedCount = 0;

  // ===== 存储键常量 =====
  static const String _layoutModeKeyPrefix = 'card_layout_mode_';
  static const String _filterBarKeyPrefix = 'filter_bar_visibility_';

  // ==========================================================================
  // 布局模式管理
  // ==========================================================================
  String _getLayoutKey(String siteKey) => '$_layoutModeKeyPrefix$siteKey';

  void _loadLayoutForCurrentSite() {
    final site = _sourceManager.currentSite.value;
    if (site == null) return;
    final siteKey = site['key']?.toString() ?? '';
    if (siteKey.isEmpty) return;
    final savedIndex = StorageManager.getSetting<int>(_getLayoutKey(siteKey));
    final mode = savedIndex != null
        ? CardLayoutMode.fromIndex(savedIndex)
        : CardLayoutMode.grid3;
    if (cardLayoutMode.value != mode) {
      cardLayoutMode.value = mode;
    }
  }

  void toggleCardLayout() {
    final site = _sourceManager.currentSite.value;
    if (site == null) return;
    final siteKey = site['key']?.toString() ?? '';
    if (siteKey.isEmpty) return;
    final newMode = cardLayoutMode.value.next();
    cardLayoutMode.value = newMode;
    StorageManager.setSetting(_getLayoutKey(siteKey), newMode.modeIndex);
  }

  // ==========================================================================
  // 筛选状态管理
  // ==========================================================================
  String _getFilterKey(String siteKey) => '$_filterBarKeyPrefix$siteKey';

  void _loadFilterVisibilityForCurrentSite() {
    final site = _sourceManager.currentSite.value;
    if (site == null) return;
    final siteKey = site['key']?.toString() ?? '';
    if (siteKey.isEmpty) return;
    final saved = StorageManager.getSetting<bool>(_getFilterKey(siteKey));
    filterBarVisibility[siteKey] = saved ?? true;
  }

  void toggleFilterBar(String siteKey) {
    final current = filterBarVisibility[siteKey] ?? true;
    final newValue = !current;
    filterBarVisibility[siteKey] = newValue;
    StorageManager.setSetting(_getFilterKey(siteKey), newValue);
  }

  bool getFilterVisibility(String siteKey) {
    return filterBarVisibility[siteKey] ?? true;
  }

  // ==========================================================================
  // 生命周期
  // ==========================================================================
  @override
  void onInit() {
    super.onInit();
    _apiService = Get.find<SourceManager>().currentApiService;

    _loadLayoutForCurrentSite();
    _loadFilterVisibilityForCurrentSite();

    ever(_sourceManager.currentSite, (_) {
      _loadLayoutForCurrentSite();
      _loadFilterVisibilityForCurrentSite();
    });

    ever(_sourceManager.isConfigLoaded, (loaded) {
      if (loaded) {
        _loadLayoutForCurrentSite();
        _loadFilterVisibilityForCurrentSite();
        _loadHomeData();
      }
    });

    // 主动检查：如果配置已加载完成，直接加载数据
    if (_sourceManager.isConfigLoaded.value) {
      _loadLayoutForCurrentSite();
      _loadFilterVisibilityForCurrentSite();
      _loadHomeData();
    }

    scrollController.addListener(_onScroll);

    // ===== 监听 drpy2 ready，自动重新加载 =====
    final drpy2Service = Get.find<Drpy2ApiService>();
    ever<bool>(drpy2Service.isReady, (ready) {
      if (!ready) return;
      final site = _sourceManager.currentSite.value;
      if (site == null) return;
      final siteKey = site['key']?.toString() ?? '';
      if (siteKey.startsWith('drpy2_')) {
        print('[HomeController] drpy2 ready detected, reloading');
        onSiteChanged();
      }
    });
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  // ==========================================================================
  // 滚动监听（加载更多）
  // ==========================================================================
  void _onScroll() {
    if (!_pagination.canLoadMore) return;
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 200) {
      loadMore();
    }
  }

  // ==========================================================================
  // 切换源
  // ==========================================================================
  void onSiteChanged() {
    _requestId++;
    _pagination.reset();
    categories.clear();
    videoList.clear();
    currentCategory.value = null;
    currentFilterValues.clear();
    filters.clear();
    hasFilter.value = false;
    _cache.clear();
    isSwitchingSource.value = true;
    isHomeError.value = false;
    errorMsg.value = '';
    _loadHomeData();
  }

  // ==========================================================================
  // 加载首页数据（入口）
  // ==========================================================================
  Future<void> _loadHomeData() async {
    final int loadId = ++_requestId;
    if (loadId == _requestId) {
      isHomeLoading.value = true;
      isHomeError.value = false;
    }

    try {
      await loadData(refresh: true, requestId: loadId);
      if (loadId != _requestId) return;

      // 如果推荐无数据且无分类，视为错误（但保留此逻辑）
      if (categories.isEmpty && videoList.isEmpty) {
        isHomeError.value = true;
        return;
      }

      // ===== 自动请求第一个非推荐分类 =====
      // 只有当前分类不是推荐，且列表为空时，才自动请求
      if (currentCategory.value != null &&
          currentCategory.value!.typeId != 'recommend' &&
          videoList.isEmpty &&
          categories.isNotEmpty &&
          !_isNoDataIndicator(videoList)) {
        _pagination.reset();
        await loadData(refresh: true, requestId: loadId);
        if (loadId != _requestId) return;
      }

      isHomeError.value = false;
    } catch (e) {
      if (loadId == _requestId) {
        isHomeError.value = true;
      }
    } finally {
      // 关闭切换源状态（无论是否最新，只要为 true 就关）
      if (isSwitchingSource.value) {
        isSwitchingSource.value = false;
      }
      // 只有最新任务才关闭 isHomeLoading
      if (loadId == _requestId) {
        isHomeLoading.value = false;
      }
    }
  }

  bool get hasConfig {
    final site = _sourceManager.currentSite.value;
    return site != null && site['api']?.toString().isNotEmpty == true;
  }

  // ==========================================================================
  // 核心数据加载方法
  // ==========================================================================
  // Future<void> loadData({bool refresh = true, int? requestId}) async {
  //   // ===== 判断是否为 catvod，直接获取服务 =====
  //   final site = _sourceManager.currentSite.value;
  //   final bool isCatvod = site != null && SourceManager.isCatVodOpenSite(site);

  //   if (isCatvod) {
  //     _apiService = Get.find<SourceManager>().currentApiService;
  //   } else {
  //     _apiService = Get.find<SourceManager>().currentApiService;
  //   }

  //   if (isLoading.value && !refresh) return;

  //   if (refresh) {
  //     _pagination.reset();
  //     isLoading.value = true;
  //     errorMsg.value = '';
  //     _lastLoadedItem = null;
  //     _lastLoadedCount = 0;
  //   }

  //   try {
  //     // catvod 跳过 requestId 检查
  //     if (!isCatvod && requestId != null && requestId != _requestId) {
  //       isLoading.value = false;
  //       return;
  //     }

  //     if (site == null) {
  //       if (_sourceManager.isConfigLoaded.value) {
  //         errorMsg.value = '暂无配置，请去设置页添加接口';
  //       } else {
  //         errorMsg.value = '正在加载配置...';
  //       }
  //       isLoading.value = false;
  //       return;
  //     }

  //     dynamic result;
  //     final bool isRecommend = currentCategory.value == null;
  //     if (isRecommend) {
  //       result = await _apiService.fetchHome();
  //     } else {
  //       result = await _apiService.fetchCate(
  //         currentCategory.value!.typeId,
  //         _pagination.page,
  //         ext: _buildFilterExt(),
  //       );
  //     }

  //     if (!isCatvod && requestId != null && requestId != _requestId) {
  //       isLoading.value = false;
  //       return;
  //     }

  //     final newList = _parseVideoList(result);

  //     if (isRecommend && refresh && result is Map<String, dynamic>) {
  //       _parseCategories(result);
  //       _parseFilters(result);
  //       if (newList.isNotEmpty) {
  //         final recommend = categories.firstWhereOrNull((c) => c.typeId == 'recommend');
  //         if (recommend == null) {
  //           categories.insert(0, Category(typeId: 'recommend', typeName: '推荐'));
  //         }
  //       } else {
  //         categories.removeWhere((c) => c.typeId == 'recommend');
  //       }
  //       if (categories.isNotEmpty && currentCategory.value == null) {
  //         _autoSelectDefaultCategory();
  //       }
  //     }

  //     if (_isNoDataIndicator(newList)) {
  //       _pagination.isEnd = true;
  //       if (refresh) {
  //         videoList.value = newList;
  //         _updateCategoryCache();
  //         _lastLoadedItem = newList.isNotEmpty ? newList.last : null;
  //         _lastLoadedCount = newList.length;
  //       } else {
  //         videoList.removeWhere((item) =>
  //             item.vodId == 'no_data' ||
  //             item.vodName.contains('无数据') ||
  //             item.vodName.contains('防无限请求'));
  //         videoList.addAll(newList);
  //         _updateCategoryCache();
  //         _lastLoadedItem = newList.isNotEmpty ? newList.last : null;
  //         _lastLoadedCount = newList.length;
  //       }
  //       isLoading.value = false;
  //       return;
  //     }

  //     if (refresh) {
  //       videoList.value = newList;
  //       _updateCategoryCache();
  //       _lastLoadedItem = newList.isNotEmpty ? newList.last : null;
  //       _lastLoadedCount = newList.length;
  //     } else {
  //       if (newList.isNotEmpty && _lastLoadedItem != null && _lastLoadedCount == newList.length) {
  //         final last = newList.last;
  //         if (last.vodId == _lastLoadedItem!.vodId && last.vodName == _lastLoadedItem!.vodName) {
  //           _pagination.isEnd = true;
  //           isLoading.value = false;
  //           _pagination.isLoadingMore = false;
  //           return;
  //         }
  //       }
  //       videoList.addAll(newList);
  //       _updateCategoryCache();
  //       _lastLoadedItem = newList.isNotEmpty ? newList.last : null;
  //       _lastLoadedCount = newList.length;
  //     }

  //     if (newList.isEmpty) _pagination.isEnd = true;
  //     final currentCat = currentCategory.value;
  //     if (currentCat != null && currentCat.typeId != 'recommend') {
  //       _pagination.nextPage();
  //     }
  //     _updateFilterStatus();

  //     isLoading.value = false;
  //   } catch (e) {
  //     print('加载数据失败: $e');
  //     isLoading.value = false;
  //   }
  // }

  Future<void> loadData({bool refresh = true, int? requestId}) async {
    // ===== 统一从 SourceManager 获取当前服务 =====
    _apiService = Get.find<SourceManager>().currentApiService;

    if (isLoading.value && !refresh) return;

    if (refresh) {
      _pagination.reset();
      isLoading.value = true;
      errorMsg.value = '';
      _lastLoadedItem = null;
      _lastLoadedCount = 0;
    }

    try {
      final site = _sourceManager.currentSite.value;

      // ===== 移除 isCatvod 判断，所有源统一处理 =====
      if (requestId != null && requestId != _requestId) {
        isLoading.value = false;
        return;
      }

      if (site == null) {
        if (_sourceManager.isConfigLoaded.value) {
          errorMsg.value = '暂无配置，请去设置页添加接口';
        } else {
          errorMsg.value = '正在加载配置...';
        }
        isLoading.value = false;
        return;
      }

      dynamic result;
      final bool isRecommend = currentCategory.value == null;
      if (isRecommend) {
        result = await _apiService.fetchHome();
      } else {
        result = await _apiService.fetchCate(
          currentCategory.value!.typeId,
          _pagination.page,
          ext: _buildFilterExt(),
        );
      }

      // 再次检查版本号（因为异步请求可能跨越版本变化）
      if (requestId != null && requestId != _requestId) {
        isLoading.value = false;
        return;
      }

      final newList = _parseVideoList(result);

      if (isRecommend && refresh && result is Map<String, dynamic>) {
        _parseCategories(result);
        _parseFilters(result);
        if (newList.isNotEmpty) {
          final recommend = categories.firstWhereOrNull((c) => c.typeId == 'recommend');
          if (recommend == null) {
            categories.insert(0, Category(typeId: 'recommend', typeName: '推荐'));
          }
        } else {
          categories.removeWhere((c) => c.typeId == 'recommend');
        }
        if (categories.isNotEmpty && currentCategory.value == null) {
          _autoSelectDefaultCategory();
        }
      }

      if (_isNoDataIndicator(newList)) {
        _pagination.isEnd = true;
        if (refresh) {
          videoList.value = newList;
          _updateCategoryCache();
          _lastLoadedItem = newList.isNotEmpty ? newList.last : null;
          _lastLoadedCount = newList.length;
        } else {
          videoList.removeWhere((item) =>
              item.vodId == 'no_data' ||
              item.vodName.contains('无数据') ||
              item.vodName.contains('防无限请求'));
          videoList.addAll(newList);
          _updateCategoryCache();
          _lastLoadedItem = newList.isNotEmpty ? newList.last : null;
          _lastLoadedCount = newList.length;
        }
        isLoading.value = false;
        return;
      }

      if (refresh) {
        videoList.value = newList;
        _updateCategoryCache();
        _lastLoadedItem = newList.isNotEmpty ? newList.last : null;
        _lastLoadedCount = newList.length;
      } else {
        if (newList.isNotEmpty && _lastLoadedItem != null && _lastLoadedCount == newList.length) {
          final last = newList.last;
          if (last.vodId == _lastLoadedItem!.vodId && last.vodName == _lastLoadedItem!.vodName) {
            _pagination.isEnd = true;
            isLoading.value = false;
            _pagination.isLoadingMore = false;
            return;
          }
        }
        videoList.addAll(newList);
        _updateCategoryCache();
        _lastLoadedItem = newList.isNotEmpty ? newList.last : null;
        _lastLoadedCount = newList.length;
      }

      if (newList.isEmpty) _pagination.isEnd = true;
      final currentCat = currentCategory.value;
      if (currentCat != null && currentCat.typeId != 'recommend') {
        _pagination.nextPage();
      }
      _updateFilterStatus();

      isLoading.value = false;
    } catch (e) {
      print('加载数据失败: $e');
      isLoading.value = false;
    }
  }

  // ==========================================================================
  // 缓存管理
  // ==========================================================================
  void _updateCategoryCache() {
    if (currentCategory.value == null) return;
    final key = currentCategory.value!.typeId;
    _cache.save(key, _pagination.page, _pagination.isEnd, videoList);
  }

  void _restoreFromCache(String categoryId) {
    final cache = _cache.get(categoryId);
    if (cache != null) {
      _pagination.page = cache.page;
      _pagination.isEnd = cache.isEnd;
      videoList.value = cache.items;
    }
  }

  // ==========================================================================
  // 分类管理
  // ==========================================================================
  void _autoSelectDefaultCategory() {
    if (categories.isEmpty) return;
    final recommend = categories.firstWhereOrNull((c) => c.typeId == 'recommend');
    if (recommend != null) {
      currentCategory.value = recommend;
    } else {
      currentCategory.value = categories.first;
    }
  }

  void switchCategory(Category category) {
    if (currentCategory.value?.typeId == category.typeId) return;

    if (scrollController.hasClients && scrollController.offset > 0) {
      scrollController.jumpTo(0);
    }

    currentCategory.value = category;
    currentFilterValues.clear();
    _pagination.reset();

    final key = category.typeId;

    if (_cache.contains(key)) {
      _restoreFromCache(key);
      isLoading.value = false;
    } else {
      videoList.clear();
      loadData(refresh: true);
    }
    _updateFilterStatus();
  }

  // ==========================================================================
  // 筛选管理
  // ==========================================================================
  String? _buildFilterExt() {
    if (currentFilterValues.isEmpty) return null;
    final jsonStr = jsonEncode(Map.from(currentFilterValues));
    return base64Encode(utf8.encode(jsonStr));
  }

  void updateFilter(String groupKey, String value) {
    if (currentFilterValues[groupKey] == value) {
      currentFilterValues.remove(groupKey);
    } else {
      currentFilterValues[groupKey] = value;
    }

    _pagination.reset();
    if (currentCategory.value != null) {
      _cache.remove(currentCategory.value!.typeId);
    }
    videoList.clear();
    isLoading.value = true;
    loadData(refresh: true);
  }

  // ==========================================================================
  // 刷新 & 加载更多
  // ==========================================================================
  Future<void> refreshData() async {
    _pagination.reset();
    if (currentCategory.value != null) {
      _cache.remove(currentCategory.value!.typeId);
    }
    videoList.clear();
    isLoading.value = true;
    // 直接调用 _loadHomeData，它会递增版本号并处理所有逻辑
    await _loadHomeData();
  }

  void loadMore() async {
    if (currentCategory.value == null) return;
    if (!_pagination.canLoadMore) return;
    if (isLoading.value) return;
    _pagination.isLoadingMore = true;
    try {
      await loadData(refresh: false, requestId: _requestId);
    } catch (e) {
      // 理论上 loadData 不会再抛出异常，但保留以防万一
      print('loadMore 捕获异常: $e');
    } finally {
      // 确保重置标志，无论成功或失败
      _pagination.isLoadingMore = false;
    }
  }

  // ==========================================================================
  // 解析辅助方法
  // ==========================================================================
  void _parseCategories(Map<String, dynamic> result) {
    final newCategories = <Category>[];
    if (result['class'] is List) {
      for (final item in result['class']) {
        newCategories.add(Category(
          typeId: item['type_id']?.toString() ?? '',
          typeName: item['type_name']?.toString() ?? '',
        ));
      }
    }
    categories.value = newCategories;
  }

  void _parseFilters(Map<String, dynamic> result) {
    if (result['filters'] is! Map) return;
    final Map<String, List<FilterGroup>> parsedFilters = {};
    (result['filters'] as Map).forEach((cateId, filterList) {
      if (filterList is! List) return;
      final groups = <FilterGroup>[];
      for (final item in filterList) {
        final values = <FilterValue>[];
        if (item['value'] is List) {
          for (final v in item['value']) {
            values.add(FilterValue(
              name: v['n']?.toString() ?? '',
              value: v['v']?.toString() ?? '',
            ));
          }
        }
        groups.add(FilterGroup(
          key: item['key']?.toString() ?? '',
          name: item['name']?.toString() ?? '',
          values: values,
        ));
      }
      parsedFilters[cateId.toString()] = groups;
    });
    filters.value = parsedFilters;
  }

  List<VideoItem> _parseVideoList(dynamic result) {
    final List<VideoItem> list = [];
    final listData = result is Map ? result['list'] : result;
    if (listData is List) {
      for (final item in listData) {
        if (item is Map) {
          final Map<String, dynamic> castMap = {};
          item.forEach((k, v) {
            castMap[k.toString()] = v;
          });
          list.add(VideoItem.fromJson(castMap));
        }
      }
    }
    return list;
  }

  bool _isNoDataIndicator(List<VideoItem> list) {
    if (list.length != 1) return false;
    final item = list.first;
    return item.vodId == 'no_data' ||
        item.vodName.contains('无数据') ||
        item.vodName.contains('防无限请求');
  }

  void _updateFilterStatus() {
    final cid = currentCategory.value?.typeId;
    hasFilter.value = cid != null && filters.containsKey(cid) && filters[cid]!.isNotEmpty;
  }

  // ===== 刷新顶栏收齐状态（设置变化时调用） =====
  void refreshHideTopBar() {
    hideTopBar.value = SettingPref.hideTopBar;
  }

  // ============================================================================
  // 对外暴露的数据获取方法（供 RecommendTab 使用）
  // ============================================================================

  /// 获取推荐分类的缓存数据（typeId == 'recommend'）
  /// 返回 List<VideoItem>，如果不存在返回空列表
  List<VideoItem> getRecommendCachedItems() {
    const recommendKey = 'recommend';
    if (_cache.contains(recommendKey)) {
      final cached = _cache.get(recommendKey);
      if (cached != null && cached.items.isNotEmpty) {
        return List.from(cached.items);
      }
    }
    return [];
  }

  /// 获取指定分类的缓存数据
  /// [categoryId] 分类的 typeId
  /// [maxCount] 最多返回多少条，默认 6
  /// 返回 List<VideoItem>，如果不存在返回空列表
  List<VideoItem> getCachedItemsByCategory(String categoryId, {int maxCount = 6}) {
    if (categoryId.isEmpty) return [];
    if (!_cache.contains(categoryId)) return [];
    
    final cached = _cache.get(categoryId);
    if (cached == null || cached.items.isEmpty) return [];
    
    final count = cached.items.length > maxCount ? maxCount : cached.items.length;
    return cached.items.sublist(0, count);
  }

  /// 获取第一个非推荐分类的缓存数据（备选方案）
  /// [maxCount] 最多返回多少条，默认 6
  List<VideoItem> getFirstNonRecommendCachedItems({int maxCount = 6}) {
    final nonRecommend = categories.firstWhereOrNull(
      (c) => c.typeId != 'recommend',
    );
    if (nonRecommend == null) return [];
    return getCachedItemsByCategory(nonRecommend.typeId, maxCount: maxCount);
  }

  /// 获取所有分类的缓存数据（用于调试或特殊场景）
  Map<String, List<VideoItem>> getAllCachedItems() {
    final result = <String, List<VideoItem>>{};
    // 遍历所有分类（包括推荐）
    for (final category in categories) {
      if (_cache.contains(category.typeId)) {
        final cached = _cache.get(category.typeId);
        if (cached != null && cached.items.isNotEmpty) {
          result[category.typeId] = List.from(cached.items);
        }
      }
    }
    return result;
  }
}

// ============================================================================
// 数据模型
// ============================================================================
class Category {
  final String typeId;
  final String typeName;
  Category({required this.typeId, required this.typeName});
}

class FilterGroup {
  final String key;
  final String name;
  final List<FilterValue> values;
  FilterGroup({required this.key, required this.name, required this.values});
}

class FilterValue {
  final String name;
  final String value;
  FilterValue({required this.name, required this.value});
}