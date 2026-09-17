import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/jellyfin_media_item.dart';
import '../services/jellyfin_api_service.dart';
import 'jellyfin_server_controller.dart';

/// Jellyfin 播放历史控制器
///
/// 结构与 [JellyfinFavoriteController] / [JellyfinLibraryController] 一致：
/// 分页加载 + 下拉刷新 + 无限滚动。
class JellyfinHistoryController extends GetxController {
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
    loadHistory(refresh: true);
    scrollController.addListener(() {
      if (scrollController.position.pixels >=
              scrollController.position.maxScrollExtent - 200 &&
          !isLoading.value &&
          hasMore.value) {
        loadHistory(refresh: false);
      }
    });
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  Future<void> loadHistory({bool refresh = true}) async {
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

      final result = await api.getPlayHistory(
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

  Future<void> refreshData() => loadHistory(refresh: true);

  // ============================================================
  // 删除历史（单条 / 全部）
  // ============================================================

  /// 从历史中删除单条记录
  ///
  /// 调 Jellyfin 的 `PlayedItems/{itemId}` 取消已播状态，
  /// 成功后本地列表立即移除，无需整页刷新。
  Future<void> removeOne(JellyfinMediaItem item) async {
    final server = serverController.currentServer;
    if (server == null || server.userId == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;

    try {
      await api.removeFromHistory(
        userId: server.userId!,
        token: token,
        baseUrl: server.baseUrl,
        itemId: item.id,
      );
      // 本地移除
      items.removeWhere((i) => i.id == item.id);
      if (totalCount.value > 0) {
        totalCount.value = totalCount.value - 1;
      }
    } catch (e) {
      // 抛出给调用方弹 Toast
      rethrow;
    }
  }

  /// 清空所有历史记录
  ///
  /// Jellyfin 没有"批量清空历史"的端点，需要：
  /// 1. 分页拉全量历史（本地只加载了部分）
  /// 2. 逐个调用 removeFromHistory
  ///
  /// [onProgress] 每删除一条回调一次，参数 `(当前序号, 总数)`
  Future<void> clearAllHistory({
    void Function(int current, int total)? onProgress,
  }) async {
    final server = serverController.currentServer;
    if (server == null || server.userId == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;

    // ---- 1. 分页拉全量 ----
    final all = <JellyfinMediaItem>[];
    int start = 0;
    const pageSize = 200;
    while (true) {
      final result = await api.getPlayHistory(
        userId: server.userId!,
        token: token,
        baseUrl: server.baseUrl,
        startIndex: start,
        limit: pageSize,
      );
      final list = (result['Items'] as List?)
              ?.map((e) =>
                  JellyfinMediaItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      if (list.isEmpty) break;
      all.addAll(list);
      if (list.length < pageSize) break;
      start += pageSize;
    }

    if (all.isEmpty) {
      items.clear();
      totalCount.value = 0;
      return;
    }

    // ---- 2. 逐个删除 ----
    for (int i = 0; i < all.length; i++) {
      onProgress?.call(i + 1, all.length);
      try {
        await api.removeFromHistory(
          userId: server.userId!,
          token: token,
          baseUrl: server.baseUrl,
          itemId: all[i].id,
        );
      } catch (_) {
        // 忽略单条失败，继续处理其余
      }
    }

    // ---- 3. 本地清空 ----
    items.clear();
    totalCount.value = 0;
  }
}