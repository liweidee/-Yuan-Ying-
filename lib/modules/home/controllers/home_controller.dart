import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/drpy2_api_service.dart';
import 'package:yuanying/modules/home/controllers/category_controller.dart';
import 'package:yuanying/models/common/card_layout_mode.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';
import 'package:collection/collection.dart';

class HomeController extends GetxController with GetTickerProviderStateMixin {
  final SourceManager _sourceManager = Get.find<SourceManager>();

  // ===== 分类与筛选 =====
  final categories = <Category>[].obs;
  final currentCategory = Rx<Category?>(null);
  final hasFilter = false.obs;
  final filters = <String, List<FilterGroup>>{}.obs;
  final filterBarVisibility = <String, bool>{}.obs;

  final Rx<Category?> selectedMainCategory = Rx<Category?>(null);

  // ===== 推荐数据缓存 =====
  final RxList<VideoItem> _recommendList = <VideoItem>[].obs;
  List<VideoItem> get recommendList => _recommendList;

  // ===== 布局 =====
  final cardLayoutMode = CardLayoutMode.grid3.obs;
  final hideTopBar = SettingPref.hideTopBar.obs;

  // ===== 加载状态 =====
  final isHomeLoading = false.obs;
  final isHomeError = false.obs;
  final errorMsg = ''.obs;
  final isSwitchingSource = false.obs;

  // ===== 分类控制器缓存（仅非推荐分类） =====
  final Map<String, CategoryController> _categoryControllers = {};

  // ===== Tab 控制器 =====
  TabController? _tabController;
  TabController? get tabController => _tabController;

  // ===== 存储键常量 =====
  static const String _layoutModeKeyPrefix = 'card_layout_mode_';
  static const String _filterBarKeyPrefix = 'filter_bar_visibility_';

  // ===== 生命周期 =====
  @override
  void onInit() {
    super.onInit();

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

    if (_sourceManager.isConfigLoaded.value) {
      _loadHomeData();
    }

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
    for (var ctrl in _categoryControllers.values) {
      ctrl.dispose();
    }
    _categoryControllers.clear();
    _tabController?.dispose();
    _tabController = null;
    super.onClose();
  }

  // ===== 布局模式管理 =====
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

  // ===== 筛选栏可见性 =====
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

  // ===== 切换源 =====
  void onSiteChanged() {
    for (var ctrl in _categoryControllers.values) {
      ctrl.dispose();
    }
    _categoryControllers.clear();
    _recommendList.clear();
    categories.clear();
    currentCategory.value = null;
    selectedMainCategory.value = null;
    filters.clear();
    hasFilter.value = false;
    isSwitchingSource.value = true;
    isHomeError.value = false;
    errorMsg.value = '';

    _tabController?.dispose();
    _tabController = null;

    _loadHomeData();
  }

  // ===== 加载首页数据 =====
  Future<void> _loadHomeData() async {
    _tabController?.dispose();
    _tabController = null;

    isHomeLoading.value = true;
    isHomeError.value = false;

    try {
      final apiService = _sourceManager.currentApiService;
      final result = await apiService.fetchHome();

      _parseCategories(result);
      _parseFilters(result);

      // 解析推荐列表
      final listData = result['list'] as List?;
      if (listData != null && listData.isNotEmpty) {
        final parsed = _parseVideoList(result);
        _recommendList.value = parsed;
      } else {
        _recommendList.clear();
      }

      // 处理推荐分类
      if (_recommendList.isNotEmpty) {
        if (categories.isNotEmpty) {
          final hasRecommend = categories.any((c) => c.typeId == 'recommend');
          if (!hasRecommend) {
            categories.insert(0, Category(typeId: 'recommend', typeName: '推荐'));
          }
        }
      } else {
        categories.removeWhere((c) => c.typeId == 'recommend');
      }

      if (categories.isEmpty) {
        isHomeError.value = true;
        errorMsg.value = '暂无分类数据';
        isHomeLoading.value = false;
        return;
      }

      // 创建 TabController
      _tabController = TabController(
        length: categories.length,
        vsync: this,
      );

      // ===== 动画进度监听：实时更新高亮 =====
      _tabController!.animation?.addListener(() {
        final value = _tabController!.animation!.value;
        final index = value.round();
        if (index >= 0 && index < categories.length) {
          final category = categories[index];
          if (currentCategory.value?.typeId != category.typeId) {
            currentCategory.value = category;
            _updateFilterStatus();
          }
        }
      });

      // ===== 切换完成监听：加载数据 =====
      _tabController!.addListener(() {
        if (_tabController!.indexIsChanging) return;
        _onTabIndexChanged();
      });

      // 默认选中第一个分类
      currentCategory.value = categories.first;
      selectedMainCategory.value = categories.first;

      // 为所有非推荐分类创建控制器
      for (int i = 0; i < categories.length; i++) {
        final cat = categories[i];
        if (cat.typeId == 'recommend') continue;
        final ctrl = _getOrCreateController(cat.typeId);
        if (i == 0 && ctrl != null) {
          if (ctrl.videoList.isEmpty && !ctrl.isLoading.value) {
            ctrl.loadData(refresh: true);
          }
        }
      }

      _updateFilterStatus();
      isHomeError.value = false;

    } catch (e) {
      print('_loadHomeData error: $e');
      isHomeError.value = true;
      errorMsg.value = e.toString();
    } finally {
      isHomeLoading.value = false;
      isSwitchingSource.value = false;
    }
  }

  // ===== TabController 监听（侧滑切换） =====
  void _onTabIndexChanged() {
    if (_tabController == null) return;
    final int index = _tabController!.index;
    if (index < 0 || index >= categories.length) return;
    final Category category = categories[index];
    if (category.typeId == 'recommend') return;

    // 更新当前分类和选中的主分类
    currentCategory.value = category;
    selectedMainCategory.value = category;

    // 获取控制器
    CategoryController? ctrl = _categoryControllers[category.typeId];
    if (ctrl == null) {
      ctrl = _getOrCreateController(category.typeId);
    }
    if (ctrl == null) return;

    // 侧滑切换：不恢复 ID，保留当前状态（子目录或主分类）
    // 仅当数据为空时才加载（首次进入）
    if (ctrl.videoList.isEmpty && !ctrl.isLoading.value) {
      ctrl.loadData(refresh: true);
    }
  }

  // ===== 获取或创建分类控制器（内部使用，推荐返回 null） =====
  CategoryController? _getOrCreateController(String typeId) {
    if (typeId == 'recommend') return null;

    if (_categoryControllers.containsKey(typeId)) {
      return _categoryControllers[typeId]!;
    }

    final category = categories.firstWhereOrNull((c) => c.typeId == typeId);
    final name = category?.typeName ?? typeId;
    final apiService = _sourceManager.currentApiService;

    final ctrl = CategoryController(
      categoryId: typeId,
      categoryName: name,
      apiService: apiService,
    );

    _categoryControllers[typeId] = ctrl;
    return ctrl;
  }

  // ===== 获取或创建分类控制器（公开，推荐返回 null） =====
  CategoryController? getOrCreateController(String typeId) {
    return _getOrCreateController(typeId);
  }

  // ===== 切换分类（点击） =====
  void switchCategory(Category category) {
    // 如果点击的是当前分类
    if (currentCategory.value?.typeId == category.typeId) {
      // 如果控制器处于子目录模式，需要强制刷新恢复主分类
      final ctrl = _categoryControllers[category.typeId];
      if (ctrl != null && ctrl.isSubCategoryMode) {
        ctrl.ensureOwnCategory();
        ctrl.loadData(refresh: true);
      }
      // 否则（非子目录模式）不做任何操作，保留缓存
      return;
    }

    currentCategory.value = category;
    _updateFilterStatus();

    final int index = categories.indexOf(category);
    if (index != -1 && _tabController != null) {
      _tabController!.animateTo(index);
      selectedMainCategory.value = category;
    }

    if (index != -1) {
      // 主分类点击（切换到另一个主分类）
      CategoryController? ctrl = _categoryControllers[category.typeId];
      if (ctrl == null) {
        ctrl = _getOrCreateController(category.typeId);
      }
      if (ctrl != null) {
        final bool needRefresh = ctrl.isSubCategoryMode || ctrl.videoList.isEmpty;
        ctrl.ensureOwnCategory();
        if (needRefresh) {
          ctrl.loadData(refresh: true);
        }
      }
      return;
    }

    // 子目录分支
    Category? mainCategory = selectedMainCategory.value;
    if (mainCategory == null || !categories.contains(mainCategory)) {
      mainCategory = categories.isNotEmpty ? categories.first : null;
      if (mainCategory == null) return;
      selectedMainCategory.value = mainCategory;
    }

    CategoryController? mainCtrl = _categoryControllers[mainCategory.typeId];
    if (mainCtrl == null) {
      mainCtrl = _getOrCreateController(mainCategory.typeId);
    }

    if (mainCtrl != null) {
      mainCtrl.switchToSubCategory(category.typeId);
    }
  }

  // ===== 获取分类控制器 =====
  CategoryController? getCategoryController(String typeId) {
    // 推荐分类返回 null
    if (typeId == 'recommend') return null;
    return _categoryControllers[typeId];
  }

  CategoryController? getCurrentCategoryController() {
    final cat = currentCategory.value;
    if (cat == null) return null;
    // 推荐分类返回 null
    if (cat.typeId == 'recommend') return null;
    return getCategoryController(cat.typeId);
  }

  // ===== 刷新当前分类（兼容 action_renderer） =====
  Future<void> refreshData() async {
    final cat = currentCategory.value;
    if (cat == null) {
      await _loadHomeData();
      return;
    }
    // 推荐分类不刷新
    if (cat.typeId == 'recommend') {
      return;
    }
    final ctrl = getCurrentCategoryController();
    if (ctrl != null) {
      await ctrl.refreshData();
    } else {
      await _loadHomeData();
    }
  }

  // ===== 解析分类 =====
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

  // ===== 解析筛选 =====
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

  // ===== 解析视频列表 =====
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

  void _updateFilterStatus() {
    final cid = currentCategory.value?.typeId;
    hasFilter.value = cid != null && filters.containsKey(cid) && filters[cid]!.isNotEmpty;
  }

  // ===== 刷新顶部栏收齐状态 =====
  void refreshHideTopBar() {
    hideTopBar.value = SettingPref.hideTopBar;
    Get.find<MainController>().refreshHideTopBar();
  }

  // ===== 对外提供缓存数据（兼容旧接口） =====
  List<VideoItem> getRecommendCachedItems() {
    return List.from(_recommendList);
  }

  List<VideoItem> getCachedItemsByCategory(String categoryId, {int maxCount = 6}) {
    // 推荐分类单独处理
    if (categoryId == 'recommend') {
      final count = _recommendList.length > maxCount ? maxCount : _recommendList.length;
      return _recommendList.sublist(0, count);
    }
    final ctrl = _categoryControllers[categoryId];
    if (ctrl == null || ctrl.videoList.isEmpty) return [];
    final count = ctrl.videoList.length > maxCount ? maxCount : ctrl.videoList.length;
    return ctrl.videoList.sublist(0, count);
  }

  List<VideoItem> getFirstNonRecommendCachedItems({int maxCount = 6}) {
    final nonRecommend = categories.firstWhereOrNull(
      (c) => c.typeId != 'recommend',
    );
    if (nonRecommend == null) return [];
    return getCachedItemsByCategory(nonRecommend.typeId, maxCount: maxCount);
  }

  Map<String, List<VideoItem>> getAllCachedItems() {
    final result = <String, List<VideoItem>>{};
    // 先加入推荐数据
    if (_recommendList.isNotEmpty) {
      result['recommend'] = List.from(_recommendList);
    }
    for (final category in categories) {
      if (category.typeId == 'recommend') continue;
      final ctrl = _categoryControllers[category.typeId];
      if (ctrl != null && ctrl.videoList.isNotEmpty) {
        result[category.typeId] = List.from(ctrl.videoList);
      }
    }
    return result;
  }
}

// ===== 数据模型 =====
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