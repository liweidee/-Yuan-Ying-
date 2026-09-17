import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/jellyfin_media_item.dart';
import '../services/jellyfin_api_service.dart';
import 'jellyfin_server_controller.dart';

/// Jellyfin 收藏列表控制器
/// 结构与 [JellyfinLibraryController] 一致：分页加载 + 下拉刷新 + 无限滚动
class JellyfinFavoriteController extends GetxController {
  final JellyfinServerController serverController =
      Get.find<JellyfinServerController>();
  final JellyfinApiService api = JellyfinApiService();

  final RxList<JellyfinMediaItem> items = <JellyfinMediaItem>[].obs;
  final RxInt totalCount = 0.obs;
  final RxInt startIndex = 0.obs;
  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxString error = ''.obs;

  final ScrollController scrollController = ScrollController();

  @override
  void onInit() {
    super.onInit();
    loadFavorites(refresh: true);
    scrollController.addListener(() {
      if (scrollController.position.pixels >=
              scrollController.position.maxScrollExtent - 200 &&
          !isLoading.value &&
          hasMore.value) {
        loadFavorites(refresh: false);
      }
    });
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  Future<void> loadFavorites({bool refresh = true}) async {
    final server = serverController.currentServer;
    if (server == null || server.userId == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;

    if (isLoading.value) return;
    isLoading.value = true;
    error.value = '';

    try {
      if (refresh) {
        startIndex.value = 0;
        items.clear();
        hasMore.value = true;
      }

      final result = await api.getFavoriteItems(
        userId: server.userId!,
        token: token,
        baseUrl: server.baseUrl,
        startIndex: startIndex.value,
        limit: 40,
      );

      final list = (result['Items'] as List?)
              ?.map((e) =>
                  JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
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

  Future<void> refreshData() => loadFavorites(refresh: true);
}