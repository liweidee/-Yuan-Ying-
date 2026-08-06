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

  final RxList<VideoItem> videoList = <VideoItem>[].obs;

  int _page = 1;
  bool _isEnd = false;

  final RxBool isLoading = false.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool isError = false.obs;
  final RxString errorMsg = ''.obs;

  // ===== 新增：表示是否已完成首次加载 =====
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
  });

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);

    // ===== 推荐分类：直接使用 initialData，绝不发起网络请求 =====
    if (categoryId == 'recommend') {
      videoList.value = initialData ?? [];
      hasLoaded.value = true;
      return;
    }

    // ===== 非推荐分类 =====
    if (initialData != null && initialData!.isNotEmpty) {
      videoList.value = initialData!;
      hasLoaded.value = true;
    } else {
      // 先设置加载状态，再加载数据
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

  /// 加载数据（非推荐分类使用）
  Future<void> loadData({bool refresh = true}) async {
    // 推荐分类禁止加载
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
        // ===== 标记加载完成，即使失败也要标记 =====
        hasLoaded.value = true;
        return;
      }

      String? ext;
      if (filterValues.isNotEmpty) {
        final jsonStr = jsonEncode(Map.from(filterValues));
        ext = base64Encode(utf8.encode(jsonStr));
      }

      print('[CategoryController] 请求: $categoryId, page: $_page, filter: $filterValues');

      final result = await apiService.fetchCate(
        categoryId,
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
        // ===== 标记加载完成 =====
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
            // ===== 标记加载完成 =====
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
      // ===== 无论成功或失败，都标记加载完成 =====
      hasLoaded.value = true;
    }
  }

  Future<void> refreshData() async {
    if (categoryId == 'recommend') return;
    // 刷新时重置加载完成标志，以便显示加载圈
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
    // 清空列表，显示全屏加载
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