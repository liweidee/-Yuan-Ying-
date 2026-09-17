import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import '../models/jellyfin_media_item.dart';
import '../services/jellyfin_api_service.dart';
import 'jellyfin_server_controller.dart';

class JellyfinHomeController extends GetxController {
  final JellyfinServerController serverController =
      Get.find<JellyfinServerController>();
  final JellyfinApiService api = JellyfinApiService();

  final RxList<JellyfinMediaItem> libraries = <JellyfinMediaItem>[].obs;
  final RxList<JellyfinMediaItem> resumeItems = <JellyfinMediaItem>[].obs;
  final RxMap<String, List<JellyfinMediaItem>> latestItems =
      <String, List<JellyfinMediaItem>>{}.obs;
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;

  final RxList<JellyfinMediaItem> recentlyAddedItems =
      <JellyfinMediaItem>[].obs;

  @override
  void onInit() {
    super.onInit();
    debugPrint('===== JellyfinHomeController.onInit =====');
    ever(serverController.currentServerId, (_) {
      debugPrint('===== 服务器切换 =====');
      loadHomeData();
    });
    Future.microtask(() {
      debugPrint('===== 初始化加载 =====');
      loadHomeData();
    });
  }

  Future<void> loadHomeData() async {
    debugPrint('===== loadHomeData 执行 =====');

    final server = serverController.currentServer;
    if (server == null) {
      error.value = '未选择服务器';
      return;
    }

    final token = serverController.getToken(server.id);
    if (token == null || server.userId == null) {
      error.value = '未登录或用户信息缺失';
      return;
    }

    isLoading.value = true;
    error.value = '';

    try {
      // 1. 获取所有媒体库（不过滤，音乐库也保留）
      final libs =
          await api.getUserViews(server.userId!, token, server.baseUrl);
      debugPrint('媒体库数量: ${libs.length}');
      libraries.value = libs;

      // 2. 继续观看（只显示视频，排除音乐）
      final resume =
          await api.getResumeItems(server.userId!, token, server.baseUrl);
      final videoResume = resume.where((i) => !i.isAudio).toList();
      debugPrint('继续观看数量: ${videoResume.length}');
      resumeItems.value = videoResume;

      // 3. 最近添加（只显示视频，排除音乐）
      final recent = await api.getRecentItems(server.userId!, token,
          server.baseUrl, limit: 20);
      final videoRecent = recent.where((i) => !i.isAudio).toList();
      recentlyAddedItems.value = videoRecent;
      debugPrint('最近添加数量: ${videoRecent.length}');

      // 4. 每个库的最新内容
      final latestMap = <String, List<JellyfinMediaItem>>{};
      for (final lib in libs) {
        try {
          final items = await api.getLatestItems(
              server.userId!, token, server.baseUrl, lib.id,
              limit: 16);
          latestMap[lib.id] = items;
          debugPrint('${lib.name}: 最新 ${items.length} 个');
        } catch (e) {
          debugPrint('${lib.name} 加载失败: $e');
          latestMap[lib.id] = [];
        }
      }
      latestItems.value = latestMap;
      debugPrint('latestItems 包含 ${latestItems.keys.length} 个库');
    } catch (e) {
      debugPrint('loadHomeData 错误: $e');
      error.value = '加载失败: $e';
    } finally {
      isLoading.value = false;
    }
  }
}