// lib/modules/manga/controllers/manga_detail_controller.dart
import 'package:get/get.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/core/constants/app_constants.dart';

class MangaDetailController extends GetxController {
  final RxBool isLoading = true.obs;
  final RxString error = ''.obs;
  final Rxn<VideoDetail> detail = Rxn<VideoDetail>();
  final RxList<Episode> episodes = <Episode>[].obs;
  final RxString sourceName = ''.obs;
  final RxBool isFavorite = false.obs;

  late String vodId;
  late String pwd;
  Map<String, dynamic>? site;

  void init(String vodId, String pwd, Map<String, dynamic>? site) {
    this.vodId = vodId;
    this.pwd = pwd;
    this.site = site;
    loadDetail();
  }

  @override
  void onInit() {
    super.onInit();
  }

  Future<void> loadDetail() async {
    isLoading.value = true;
    error.value = '';
    try {
      final api = site != null
          ? Get.find<SourceManager>().createIndependentService(site!)
          : Get.find<SourceManager>().currentApiService;
      final result = await api.getDetail(vodId: vodId, pwd: pwd);
      if (result != null && result.playSources.isNotEmpty) {
        detail.value = result;
        episodes.value = result.playSources.first.episodes;
        sourceName.value = result.playSources.first.name;
        _loadFavoriteStatus();
      } else {
        error.value = '未获取到章节信息';
      }
    } catch (e) {
      error.value = '加载失败：$e';
    } finally {
      isLoading.value = false;
    }
  }

  void _loadFavoriteStatus() {
    final favorites = GStorage.getFavorites();
    isFavorite.value = favorites.any((item) => item['vod_id'] == vodId);
  }

  void toggleFavorite() {
    final detail = this.detail.value;
    if (detail == null) return;

    final site = this.site ?? Get.find<SourceManager>().currentSite.value;
    final sourceName = site?['name']?.toString() ?? (detail.typeName ?? '');
    final apiUrl = site?['api']?.toString() ?? '';
    final siteKey = site?['key']?.toString() ?? '';
    final configKey = Get.find<SourceManager>().currentConfigKey.value;
    final detailType = SourceManager.getDetailTypeFromSite(site);

    if (isFavorite.value) {
      GStorage.removeFavorite(vodId);
      isFavorite.value = false;
    } else {
      final item = {
        'vod_id': vodId,
        'vod_name': detail.vodName,
        'vod_pic': detail.vodPic,
        'vod_remarks': detail.vodRemarks ?? '',
        'vod_tag': detail.vodTag ?? '',
        'type_name': sourceName,
        'api_url': apiUrl,
        'site_key': siteKey,
        'config_key': configKey,
        'detail_type': detailType,
      };
      GStorage.addFavorite(item);
      isFavorite.value = true;
    }
  }

  void openReader(int index) {
    if (detail.value == null || episodes.isEmpty) return;
    _addToHistory(index);

    Get.toNamed(
      '/mangaReader',
      arguments: {
        'vodId': vodId,
        'vodName': detail.value!.vodName,
        'vodPic': detail.value!.vodPic,
        'episodes': episodes.map((e) => {'name': e.name, 'url': e.url}).toList(),
        'initialChapter': index,
        'pwd': pwd,
        'site': site,
        'sourceName': sourceName.value,
      },
    );
  }

  void _addToHistory(int index) {
    final detail = this.detail.value;
    if (detail == null || episodes.isEmpty) return;
    final episode = episodes[index];
    final site = this.site ?? Get.find<SourceManager>().currentSite.value;
    final apiUrl = site?['api']?.toString() ?? '';
    if (apiUrl.isEmpty) return;

    final historyList = GStorage.getHistory();
    final existingIndex = historyList.indexWhere(
      (item) => item['vod_id'] == vodId && item['api_url'] == apiUrl,
    );

    final historyItem = {
      'vod_id': vodId,
      'vod_name': detail.vodName,
      'vod_pic': detail.vodPic,
      'vod_remarks': episode.name,
      'vod_tag': detail.vodTag ?? '',
      'type_name': sourceName.value,
      'api_url': apiUrl,
      'site_key': site?['key']?.toString() ?? '',
      'config_key': Get.find<SourceManager>().currentConfigKey.value,
      'progress': '第${index+1}话',   // 漫画用“话”
      'watchTime': DateTime.now().millisecondsSinceEpoch,
      'detail_type': SourceManager.getDetailTypeFromSite(site),
    };

    if (existingIndex != -1) {
      historyList[existingIndex] = historyItem;
    } else {
      historyList.insert(0, historyItem);
    }
    GStorage.saveHistory(historyList);
  }
}