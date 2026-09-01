// lib/modules/novel/controllers/novel_detail_controller.dart
import 'package:get/get.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/core/constants/app_constants.dart';

class NovelDetailController extends GetxController {
  final RxBool isLoading = true.obs;
  final RxString error = ''.obs;
  final Rxn<VideoDetail> detail = Rxn<VideoDetail>();
  final RxList<Episode> episodes = <Episode>[].obs;
  final RxString sourceName = ''.obs;
  final RxBool isFavorite = false.obs;

  // ===== 阅读进度状态 =====
  final RxInt savedChapter = 0.obs;
  final RxBool hasProgress = false.obs;

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

        // ===== 读取阅读进度（只读章节索引） =====
        final progressKey = 'novel_progress_$vodId';
        final progress = StorageManager.getCache<Map>(progressKey);
        if (progress != null && progress['chapter'] != null) {
          final chapter = progress['chapter'] as int;
          if (chapter >= 0 && chapter < episodes.length) {
            savedChapter.value = chapter;
            hasProgress.value = true;
          }
        }
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

  void openReader([int? chapterIndex]) {
    if (detail.value == null || episodes.isEmpty) return;
    final index = chapterIndex ?? savedChapter.value;
    if (index < 0 || index >= episodes.length) return;

    // 先尝试高亮（能亮就亮，不亮也不影响）
    savedChapter.value = index;
    hasProgress.value = true;

    _addToHistory(index);

    Get.toNamed(
      '/novelReader',
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
      'progress': '第${index+1}章',
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