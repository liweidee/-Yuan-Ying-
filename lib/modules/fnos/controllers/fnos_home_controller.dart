import 'package:get/get.dart';
import '../models/fnos_media_item.dart';
import '../services/fnos_api_service.dart';
import 'fnos_server_controller.dart';

class FnosHomeController extends GetxController {
  final FnosServerController serverController =
      Get.find<FnosServerController>();
  final FnosApiService api = FnosApiService();

  final RxList<FnosMediaDbItem> libraries = <FnosMediaDbItem>[].obs;
  final RxMap<String, List<FnosPlayListItem>> previews =
      <String, List<FnosPlayListItem>>{}.obs;
  final RxList<FnosPlayListItem> resumeItems = <FnosPlayListItem>[].obs;
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;

  @override
  void onInit() {
    super.onInit();
    ever(serverController.currentServerId, (_) => loadHomeData());
    Future.microtask(loadHomeData);
  }

  Future<void> loadHomeData() async {
    final server = serverController.currentServer;
    if (server == null) {
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
      // 1. 媒体库
      final libs = await api.getMediaDbList(
        baseUrl: server.baseUrl,
        token: token,
      );
      libraries.value = libs;

      // 2. 继续观看
      try {
        final resume = await api.getPlayList(
          baseUrl: server.baseUrl,
          token: token,
        );
        resumeItems.value =
            resume.where((e) => e.duration > 0).toList();
      } catch (_) {
        resumeItems.value = [];
      }

      // 3. 每个库的前 10 条预览
      final map = <String, List<FnosPlayListItem>>{};
      for (final lib in libs) {
        try {
          final list = await api.getItemList(
            baseUrl: server.baseUrl,
            token: token,
            ancestorGuid: lib.guid,
            pageSize: 10,
          );
          map[lib.guid] = list;
        } catch (_) {
          map[lib.guid] = [];
        }
      }
      previews.value = map;
    } catch (e) {
      error.value = '加载失败: $e';
    } finally {
      isLoading.value = false;
    }
  }
}