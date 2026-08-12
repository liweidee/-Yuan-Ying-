import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/models/common/card_layout_mode.dart';

class CategoryController extends GetxController {
  final String categoryId;
  final String categoryName;
  final ISpiderService apiService;
  final SourceManager sourceManager = Get.find<SourceManager>();
  final List<VideoItem>? initialData;

  // 当前实际请求的 ID（可变）
  String _currentRequestCategoryId;

  final RxList<VideoItem> videoList = <VideoItem>[].obs;

  int _page = 1;
  bool _isEnd = false;

  final RxBool isLoading = false.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool isError = false.obs;
  final RxString errorMsg = ''.obs;

  final RxBool hasLoaded = false.obs;

  final RxMap<String, String> filterValues = <String, String>{}.obs;

  final ScrollController scrollController = ScrollController();

  VideoItem? _lastItem;
  int _lastCount = 0;

  CategoryController({
    required this.categoryId,
    required this.categoryName,
    required this.apiService,
    this.initialData,
  }) : _currentRequestCategoryId = categoryId;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);

    if (categoryId == 'recommend') {
      videoList.value = initialData ?? [];
      hasLoaded.value = true;
      return;
    }

    if (initialData != null && initialData!.isNotEmpty) {
      videoList.value = initialData!;
      hasLoaded.value = true;
    } else {
      isLoading.value = true;
      loadData(refresh: true);
    }
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  void _onScroll() {
    if (_isEnd || isLoadingMore.value || isLoading.value) return;
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 200) {
      loadMore();
    }
  }

  // 判断是否处于子目录模式
  bool get isSubCategoryMode => _currentRequestCategoryId != categoryId;

  // 切换子目录（强制刷新）
  void switchToSubCategory(String subId) {
    _currentRequestCategoryId = subId;
    _page = 1;
    _isEnd = false;
    isLoading.value = true;
    isError.value = false;
    errorMsg.value = '';
    _lastItem = null;
    _lastCount = 0;
    videoList.clear();
    hasLoaded.value = false;
    loadData(refresh: true);
  }

  // 恢复自身 ID（不清除数据）
  void ensureOwnCategory() {
    if (_currentRequestCategoryId != categoryId) {
      _currentRequestCategoryId = categoryId;
    }
  }

  Future<void> loadData({bool refresh = true}) async {
    if (categoryId == 'recommend') return;

    if (isLoading.value && !refresh) return;

    if (refresh) {
      _page = 1;
      _isEnd = false;
      isLoading.value = true;
      errorMsg.value = '';
      isError.value = false;
      _lastItem = null;
      _lastCount = 0;
    } else {
      if (_isEnd || isLoadingMore.value) return;
      isLoadingMore.value = true;
    }

    try {
      final site = sourceManager.currentSite.value;
      if (site == null) {
        errorMsg.value = '暂无配置';
        isError.value = true;
        isLoading.value = false;
        isLoadingMore.value = false;
        hasLoaded.value = true;
        return;
      }

      String? ext;
      if (filterValues.isNotEmpty) {
        final jsonStr = jsonEncode(Map.from(filterValues));
        ext = base64Encode(utf8.encode(jsonStr));
      }

      print('[CategoryController] 请求: $_currentRequestCategoryId, page: $_page, filter: $filterValues');

      final result = await apiService.fetchCate(
        _currentRequestCategoryId,
        _page,
        ext: ext,
      );

      final newList = _parseVideoList(result);

      if (_isNoDataIndicator(newList)) {
        _isEnd = true;
        if (refresh) {
          videoList.value = newList;
        } else {
          videoList.removeWhere((item) =>
              item.vodId == 'no_data' ||
              item.vodName.contains('无数据') ||
              item.vodName.contains('防无限请求'));
          videoList.addAll(newList);
        }
        isLoading.value = false;
        isLoadingMore.value = false;
        hasLoaded.value = true;
        return;
      }

      if (refresh) {
        videoList.value = newList;
      } else {
        if (newList.isNotEmpty && _lastItem != null && _lastCount == newList.length) {
          final last = newList.last;
          if (last.vodId == _lastItem!.vodId && last.vodName == _lastItem!.vodName) {
            _isEnd = true;
            isLoadingMore.value = false;
            hasLoaded.value = true;
            return;
          }
        }
        videoList.addAll(newList);
      }

      _lastItem = newList.isNotEmpty ? newList.last : null;
      _lastCount = newList.length;

      if (newList.isEmpty) _isEnd = true;
      else _page++;

      isError.value = false;
    } catch (e, stack) {
      print('[CategoryController] error: $e');
      print('[CategoryController] stack: $stack');
      errorMsg.value = e.toString();
      isError.value = true;
    } finally {
      isLoading.value = false;
      isLoadingMore.value = false;
      hasLoaded.value = true;
    }
  }

  Future<void> refreshData() async {
    if (categoryId == 'recommend') return;
    hasLoaded.value = false;
    await loadData(refresh: true);
  }

  void loadMore() {
    if (categoryId == 'recommend') return;
    if (!_isEnd && !isLoadingMore.value && !isLoading.value) {
      loadData(refresh: false);
    }
  }

  void updateFilter(String groupKey, String value) {
    if (categoryId == 'recommend') return;
    if (filterValues[groupKey] == value) {
      filterValues.remove(groupKey);
    } else {
      filterValues[groupKey] = value;
    }
    videoList.clear();
    hasLoaded.value = false;
    isLoading.value = true;
    loadData(refresh: true);
  }

  void clearFilters() {
    if (categoryId == 'recommend') return;
    filterValues.clear();
    videoList.clear();
    hasLoaded.value = false;
    isLoading.value = true;
    loadData(refresh: true);
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

  CardLayoutMode get layoutMode {
    return Get.find<HomeController>().cardLayoutMode.value;
  }

  bool get hasFilter {
    final filters = Get.find<HomeController>().filters;
    return filters.containsKey(categoryId) && filters[categoryId]!.isNotEmpty;
  }

  List<FilterGroup>? get filterGroups {
    final filters = Get.find<HomeController>().filters;
    return filters[categoryId];
  }
}