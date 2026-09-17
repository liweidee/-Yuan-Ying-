import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/emby_media_item.dart';
import '../services/emby_api_service.dart';
import 'emby_server_controller.dart';

/// Emby 收藏列表控制器
/// 结构与 [EmbyLibraryController] 一致：分页加载 + 下拉刷新 + 无限滚动
class EmbyFavoriteController extends GetxController {
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

  Future<void> refreshData() => loadFavorites(refresh: true);
}