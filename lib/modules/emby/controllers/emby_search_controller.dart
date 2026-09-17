import 'package:get/get.dart';
import '../models/emby_media_item.dart';
import '../services/emby_api_service.dart';
import 'emby_server_controller.dart';

class EmbySearchController extends GetxController {
  final EmbyServerController serverController = Get.find<EmbyServerController>();
  final EmbyApiService api = EmbyApiService();

  final RxList<EmbyMediaItem> results = <EmbyMediaItem>[].obs;
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
      final items = (data['Items'] as List?)?.map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>)).toList() ?? [];
      results.value = items;
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }
}