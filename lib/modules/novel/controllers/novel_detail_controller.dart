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
        final progress = _readProgress();
        if (progress != null && progress['chapter'] != null) {
            final chapter = (progress['chapter'] as num).toInt();
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

  /// 当前生效的 apiUrl（site 优先，回退全局源）
  String get _currentApiUrl =>
      site?['api']?.toString() ??
      Get.find<SourceManager>().currentSite.value?['api']?.toString() ??
      '';

  /// 读取阅读进度（新 key miss 时读旧 key 并一次性迁移）
  Map? _readProgress() {
      final apiUrl = _currentApiUrl;
      final newKey = StorageManager.progressKey('novel_progress', vodId, apiUrl);
      var progress = StorageManager.getCache<Map>(newKey);
      if (progress == null && apiUrl.isNotEmpty) {
          // 回退：读旧 key 并迁移到新 key，再删旧 key
          final legacyKey = 'novel_progress_$vodId';
          final legacy = StorageManager.getCache<Map>(legacyKey);
          if (legacy != null) {
              StorageManager.setCache(newKey, legacy);
              StorageManager.deleteCache(legacyKey);
              progress = legacy;
          }
      }
      return progress;
  }

  void _loadFavoriteStatus() {
    final favorites = GStorage.getFavorites();
    final api = site?['api']?.toString() ??
        Get.find<SourceManager>().currentSite.value?['api']?.toString() ??
        '';
    isFavorite.value = favorites.any((item) =>
        item['vod_id'] == vodId &&
        (item['api_url']?.toString() ?? '') == api);
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
      GStorage.removeFavorite(vodId, apiUrl);
      isFavorite.value = false;
    } else {
      final typeLabel = SourceManager.sourceTypeLabel(site);
      final typeName = typeLabel.isEmpty
          ? sourceName
          : '$sourceName ($typeLabel)';
          
      final item = {
        'vod_id': vodId,
        'vod_name': detail.vodName,
        'vod_pic': detail.vodPic,
        'vod_remarks': detail.vodRemarks ?? '',
        'vod_tag': detail.vodTag ?? '',
        'type_name': typeName,
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

    // ===== 拼装带源类型标签的显示名，用于区分同名不同源 =====
    final typeLabel = SourceManager.sourceTypeLabel(site);
    final typeName = typeLabel.isEmpty
        ? sourceName.value
        : '${sourceName.value} ($typeLabel)';

    final historyItem = {
      'vod_id': vodId,
      'vod_name': detail.vodName,
      'vod_pic': detail.vodPic,
      'vod_remarks': episode.name,
      'vod_tag': detail.vodTag ?? '',
      'type_name': typeName,
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

  /// 从 storage 重新读取阅读进度（轻量，不重拉详情）
  /// 由详情页在 didPopNext 时调用。
  void refreshProgress() {
    if (episodes.isEmpty) return;
    final progress = _readProgress();
    if (progress == null) return;
    final raw = progress['chapter'];
    if (raw == null) return;
    final chapter = (raw as num).toInt();
    if (chapter >= 0 && chapter < episodes.length) {
        savedChapter.value = chapter;
        hasProgress.value = true;
    }
  }
}