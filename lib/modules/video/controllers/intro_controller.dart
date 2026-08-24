import 'package:get/get.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/storage.dart';

/// 简介控制器 - 管理详情数据
class IntroController extends GetxController {
  final Rx<VideoDetail?> videoDetail = Rx<VideoDetail?>(null);
  final RxInt displaySourceIndex = 0.obs;
  final RxInt currentSourceIndex = 0.obs;
  final RxInt currentEpisodeIndex = 0.obs;
  final RxBool isExpanded = false.obs;
  final RxBool isFavorite = false.obs;
  final RxString sourceName = ''.obs;

  // 路由传入的原始 vodId（完整 URL）
  String? originalVodId;

  // 新增：当前源的完整 API URL
  String? currentApiUrl;

  // setter 方法
  void setOriginalVodId(String id) {
    originalVodId = id;
  }

  void setCurrentApiUrl(String url) {
    currentApiUrl = url;
  }

  void setVideoDetail(VideoDetail detail) {
    videoDetail.value = detail;
    displaySourceIndex.value = 0;
    currentSourceIndex.value = 0;
    currentEpisodeIndex.value = 0;

    _loadFavoriteStatus(); // 使用 originalVodId 检查收藏
  }

  void setSourceName(String name) {
    sourceName.value = name;
  }

  void _loadFavoriteStatus() {
    final vodId = originalVodId;
    if (vodId == null || vodId.isEmpty) {
      isFavorite.value = false;
      return;
    }
    try {
      final favorites = GStorage.getFavorites();
      isFavorite.value = favorites.any((item) => item['vod_id'] == vodId);
    } catch (e) {
      isFavorite.value = false;
    }
  }

  // ===== 收藏时存储 api_url =====
  void toggleFavorite() {
    final detail = videoDetail.value;
    if (detail == null || originalVodId == null) return;

    final site = Get.find<SourceManager>().currentSite.value;
    final sourceName = site?['name']?.toString() ?? (detail.typeName ?? '');
    final apiUrl = currentApiUrl ?? site?['api']?.toString() ?? '';
    final siteKey = site?['key']?.toString() ?? '';

    if (isFavorite.value) {
      GStorage.removeFavorite(detail.vodId);
      isFavorite.value = false;
    } else {
      final item = {
        'vod_id': originalVodId!,
        'vod_name': detail.vodName,
        'vod_pic': detail.vodPic,
        'vod_remarks': detail.vodRemarks ?? '',
        'vod_tag': detail.vodTag ?? '',
        'type_name': sourceName,
        'api_url': apiUrl,
        'site_key': siteKey,
        'config_key': Get.find<SourceManager>().currentConfigKey.value,
      };
      GStorage.addFavorite(item);
      isFavorite.value = true;
    }
  }

  // ===== 以下方法保持不变 =====
  PlaySource? getSource(int index) {
    final detail = videoDetail.value;
    if (detail == null || detail.playSources.isEmpty) return null;
    if (index >= detail.playSources.length) return null;
    return detail.playSources[index];
  }

  PlaySource? getCurrentPlaySource() {
    return getSource(currentSourceIndex.value);
  }

  PlaySource? getDisplaySource() {
    return getSource(displaySourceIndex.value);
  }

  void switchDisplaySource(int index) {
    if (displaySourceIndex.value != index) {
      displaySourceIndex.value = index;
    }
  }

  void switchPlaySource(int index) {
    if (currentSourceIndex.value != index) {
      currentSourceIndex.value = index;
    }
  }

  void switchEpisode(int index) {
    if (currentEpisodeIndex.value != index) {
      currentEpisodeIndex.value = index;
    }
  }

  void toggleExpand() {
    isExpanded.value = !isExpanded.value;
  }

  List<Episode> get displayEpisodes {
    final source = getDisplaySource();
    return source?.episodes ?? [];
  }

  List<Episode> get playEpisodes {
    final source = getCurrentPlaySource();
    return source?.episodes ?? [];
  }

  Episode? get currentPlayEpisode {
    final episodes = playEpisodes;
    if (episodes.isEmpty) return null;
    if (currentEpisodeIndex.value >= episodes.length) return null;
    return episodes[currentEpisodeIndex.value];
  }

  List<Episode> get currentEpisodes {
    return playEpisodes;
  }

  Episode? get currentEpisode {
    return currentPlayEpisode;
  }

  List<String> get sourceNames {
    final detail = videoDetail.value;
    if (detail == null) return [];
    return detail.playSources.map((s) => s.name).toList();
  }

  @override
  void onClose() {
    videoDetail.value = null;
    super.onClose();
  }
}