import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/emby_media_item.dart';
import '../services/emby_api_service.dart';
import 'emby_server_controller.dart';

class EmbyLibraryController extends GetxController {
  final String libraryId;
  final String libraryName;
  /// 库类型：movies / tvshows / music / homevideos / ...
  final String? collectionType;

  EmbyLibraryController({
    required this.libraryId,
    required this.libraryName,
    this.collectionType,
  });

  final EmbyServerController serverController =
      Get.find<EmbyServerController>();
  final EmbyApiService api = EmbyApiService();

  final RxList<EmbyMediaItem> items = <EmbyMediaItem>[].obs;
  final RxInt totalCount = 0.obs;
  final RxInt startIndex = 0.obs;
  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxString error = ''.obs;
  final ScrollController scrollController = ScrollController();
  final RxString searchKeyword = ''.obs;
  final RxString sortBy = 'SortName'.obs;
  final RxString sortOrder = 'Ascending'.obs;

  /// 根据库类型决定请求的条目类型
  String get _includeItemTypes {
    // 音乐库：只列专辑（MusicAlbum）
    if (collectionType == 'music') return 'MusicAlbum';
    // 视频库：电影 + 剧集
    return 'Movie,Series';
  }

  /// 库类型标签（新增，用于 UI 显示）
  String get libraryTypeLabel {
    switch (collectionType) {
      case 'music':
        return '音乐库';
      case 'movies':
        return '电影库';
      case 'tvshows':
        return '剧集库';
      case 'homevideos':
        return '家庭视频';
      case 'boxsets':
        return '合集';
      default:
        return '媒体库';
    }
  }

  @override
  void onInit() {
    super.onInit();
    loadData(refresh: true);
    scrollController.addListener(() {
      if (scrollController.position.pixels >=
              scrollController.position.maxScrollExtent - 200 &&
          !isLoading.value &&
          hasMore.value) {
        loadData(refresh: false);
      }
    });
    debounce(searchKeyword, (_) => loadData(refresh: true),
        time: const Duration(milliseconds: 500));
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  Future<void> loadData({bool refresh = true}) async {
    final server = serverController.currentServer;
    if (server == null || server.userId == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;

    if (isLoading.value) return;
    isLoading.value = true;

    try {
      if (refresh) {
        startIndex.value = 0;
        items.clear();
        hasMore.value = true;
      }

      final result = await api.getLibraryItems(
        userId: server.userId!,
        token: token,
        baseUrl: server.baseUrl,
        parentId: libraryId,
        startIndex: startIndex.value,
        limit: 40,
        searchTerm: searchKeyword.value.isNotEmpty
            ? searchKeyword.value
            : null,
        includeItemTypes: _includeItemTypes, // ← 动态类型
        sortBy: sortBy.value,
        sortOrder: sortOrder.value,
      );
      final list = (result['Items'] as List?)
              ?.map((e) =>
                  EmbyMediaItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final total = result['TotalRecordCount'] as int? ?? 0;
      if (refresh) {
        items.value = list;
      } else {
        items.addAll(list);
      }
      totalCount.value = total;
      startIndex.value += list.length;
      hasMore.value = startIndex.value < total;
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  void setSort(String by, String order) {
    sortBy.value = by;
    sortOrder.value = order;
    loadData(refresh: true);
  }

  Future<void> refreshData() => loadData(refresh: true);
}