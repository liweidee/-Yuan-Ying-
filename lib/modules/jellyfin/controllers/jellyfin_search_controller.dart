import 'package:get/get.dart';
import '../models/jellyfin_media_item.dart';
import '../services/jellyfin_api_service.dart';
import 'jellyfin_server_controller.dart';

class JellyfinSearchController extends GetxController {
  final JellyfinServerController serverController = Get.find<JellyfinServerController>();
  final JellyfinApiService api = JellyfinApiService();

  final RxList<JellyfinMediaItem> results = <JellyfinMediaItem>[].obs;
  final RxBool isLoading = false.obs;
  final RxString keyword = ''.obs;
  final RxString error = ''.obs;

  void search(String query) {
    keyword.value = query.trim();
    if (keyword.isEmpty) {
      results.clear();
      return;
    }
    _doSearch();
  }

  Future<void> _doSearch() async {
    final server = serverController.currentServer;
    if (server == null || server.userId == null) {
      error.value = '未选择服务器';
      return;
    }
    final token = serverController.getToken(server.id);
    if (token == null) {
      error.value = '未登录';
      return;
    }

    isLoading.value = true;
    error.value = '';
    try {
      final data = await api.getLibraryItems(
        userId: server.userId!,
        token: token,
        baseUrl: server.baseUrl,
        parentId: '', // 搜索需要传空 ParentId 或省略
        searchTerm: keyword.value,
        includeItemTypes: 'Movie,Series,Episode,Audio,MusicAlbum',
        limit: 50,
        startIndex: 0,
      );
      final items = (data['Items'] as List?)?.map((e) => JellyfinMediaItem.fromJson(e as Map<String, dynamic>)).toList() ?? [];
      results.value = items;
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }
}