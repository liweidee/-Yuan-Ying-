import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/storage.dart';

class FavoriteController extends GetxController {
  final videoList = <VideoItem>[].obs;
  final isLoading = false.obs;
  final _apiUrlMap = <String, String>{}.obs;  // vodId -> api_url
  final _siteKeyMap = <String, String>{}.obs;  // vodId -> site_key

  final SourceManager _sourceManager = Get.find<SourceManager>();

  @override
  void onInit() {
    super.onInit();
    loadFavorites();
  }

  void loadFavorites() {
    isLoading.value = true;
    try {
      final data = GStorage.getFavorites();
      final list = <VideoItem>[];
      final urlMap = <String, String>{};
      final siteKeyMap = <String, String>{};
      for (final item in data) {
        final videoItem = VideoItem.fromJson(item);
        list.add(videoItem);
        if (item['api_url'] != null) {
          urlMap[videoItem.vodId] = item['api_url'].toString();
        }
        if (item['site_key'] != null) {   // 新增
          siteKeyMap[videoItem.vodId] = item['site_key'].toString();
        }
      }
      videoList.value = list;
      _apiUrlMap.value = urlMap;
      _siteKeyMap.value = siteKeyMap;
    } catch (e) {
      print('加载收藏失败: $e');
      videoList.clear();
      _apiUrlMap.clear();
      _siteKeyMap.clear();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> clearAll() async {
    await GStorage.clearFavorites();
    videoList.clear();
    _apiUrlMap.clear();
  }

  Future<void> removeFavorite(String vodId) async {
    await GStorage.removeFavorite(vodId);
    videoList.removeWhere((item) => item.vodId == vodId);
    _apiUrlMap.remove(vodId);
  }

  String? getApiUrl(String vodId) => _apiUrlMap[vodId];
  String? getSiteKey(String vodId) => _siteKeyMap[vodId];

  String formatTimeAgo(int timestamp) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - timestamp;
    final seconds = diff ~/ 1000;
    final minutes = seconds ~/ 60;
    final hours = minutes ~/ 60;
    final days = hours ~/ 24;

    if (seconds < 60) return '刚刚';
    if (minutes < 60) return '$minutes分钟前';
    if (hours < 24) return '$hours小时前';
    if (days < 7) return '$days天前';
    if (days < 30) return '${days ~/ 7}周前';
    if (days < 365) return '${days ~/ 30}月前';
    return '${days ~/ 365}年前';
  }

  // ===== 跳转时使用存储的 api_url =====
  void navigateToDetail(VideoItem item) {
    // 1. 优先使用存储的 site_key
    final siteKey = getSiteKey(item.vodId);
    Map<String, dynamic>? targetSite;
    bool isCurrent = false;

    if (siteKey != null && siteKey.isNotEmpty) {
      try {
        targetSite = _sourceManager.sites.firstWhere(
          (s) => s['key']?.toString() == siteKey,
        );
        final current = _sourceManager.currentSite.value;
        if (current != null && current['key']?.toString() == siteKey) {
          isCurrent = true;
        }
      } catch (_) {
        targetSite = null;
      }
    }

    // 2. 找不到站点，回退 api_url
    if (targetSite == null) {
      final apiUrl = getApiUrl(item.vodId);
      if (apiUrl != null && apiUrl.isNotEmpty) {
        Get.toNamed('/detail', arguments: {
          'vodId': item.vodId,
          'apiUrl': apiUrl,
        });
        return;
      }
      SmartDialog.showToast('该收藏已失效，请重新收藏');
      return;
    }

    // 3. drpy2 / Catvod 非当前源拦截
    final isDrpy2 = SourceManager.isDrpy2Site(targetSite);
    final isCatvod = SourceManager.isCatVodOpenSite(targetSite);
    if ((isDrpy2 || isCatvod) && !isCurrent) {
      SmartDialog.showToast('该源暂不支持跳转，请切换到该源后重试');
      return;
    }

    // 4. 提取 pwd
    String pwd = 'tinydust';
    final ext = targetSite['ext'];
    if (ext is Map && ext['pwd'] != null) {
      pwd = ext['pwd'].toString();
    }

    // 5. 构建路由参数
    final args = <String, dynamic>{
      'vodId': item.vodId,
      'pwd': pwd,
    };

    if (!isCurrent && !isDrpy2 && !isCatvod) {
      args['site'] = targetSite;
    }

    Get.toNamed('/detail', arguments: args);
  }
}