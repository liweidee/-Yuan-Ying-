import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/core/constants/app_constants.dart';

class FavoriteController extends GetxController {
  final videoList = <VideoItem>[].obs;
  final _apiUrlMap = <String, String>{}.obs;
  final _siteKeyMap = <String, String>{}.obs;
  final _configKeyMap = <String, String>{}.obs;
  final _detailTypeMap = <String, String>{}.obs;

  // 过滤类型
  final filterType = 'all'.obs;  // 'all', 'video', 'novel', 'manga'
  final isLoading = false.obs;

  String? getConfigKey(String vodId) => _configKeyMap[vodId];

  final SourceManager _sourceManager = Get.find<SourceManager>();

  // 计算属性
  List<VideoItem> get filteredList {
    if (filterType.value == 'all') return videoList;
    return videoList.where((item) {
      return _detailTypeMap[item.vodId] == filterType.value;
    }).toList();
  }

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
        if (item['config_key'] != null) {
          _configKeyMap[videoItem.vodId] = item['config_key'].toString();
        }
        list.add(videoItem);
        if (item['api_url'] != null) {
          urlMap[videoItem.vodId] = item['api_url'].toString();
        }
        if (item['site_key'] != null) {
          siteKeyMap[videoItem.vodId] = item['site_key'].toString();
        }
        final type = item['detail_type']?.toString() ?? 'video';
        _detailTypeMap[videoItem.vodId] = type;
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

  void navigateToDetail(VideoItem item) {
    final type = _detailTypeMap[item.vodId] ?? 'video';

    // ---- 小说 ----
    if (type == 'novel') {
      final storedConfigKey = getConfigKey(item.vodId);
      final currentConfigKey = _sourceManager.currentConfigKey.value;
      if (storedConfigKey != null && storedConfigKey != currentConfigKey) {
        SmartDialog.showToast('该小说所属配置接口 "$storedConfigKey" 已切换，请切换回该配置后重试');
        return;
      }
      final siteKey = getSiteKey(item.vodId);
      Map<String, dynamic>? targetSite;
      if (siteKey != null && siteKey.isNotEmpty) {
        try {
          targetSite = _sourceManager.sites.firstWhere(
            (s) => s['key']?.toString() == siteKey,
          );
        } catch (_) {
          targetSite = null;
        }
      }
      if (targetSite == null) {
        SmartDialog.showToast('该记录已失效');
        return;
      }
      String pwd = 'tinydust';
      final ext = targetSite['ext'];
      if (ext is Map && ext['pwd'] != null) pwd = ext['pwd'].toString();
      Get.toNamed('/novelDetail', arguments: {
        'vodId': item.vodId,
        'pwd': pwd,
        'site': targetSite,
      });
      return;
    }

    // ---- 漫画 ----
    if (type == 'manga') {
      final storedConfigKey = getConfigKey(item.vodId);
      final currentConfigKey = _sourceManager.currentConfigKey.value;
      if (storedConfigKey != null && storedConfigKey != currentConfigKey) {
        SmartDialog.showToast('该漫画所属配置接口 "$storedConfigKey" 已切换，请切换回该配置后重试');
        return;
      }
      final siteKey = getSiteKey(item.vodId);
      Map<String, dynamic>? targetSite;
      if (siteKey != null && siteKey.isNotEmpty) {
        try {
          targetSite = _sourceManager.sites.firstWhere(
            (s) => s['key']?.toString() == siteKey,
          );
        } catch (_) {
          targetSite = null;
        }
      }
      if (targetSite == null) {
        SmartDialog.showToast('该记录已失效');
        return;
      }
      String pwd = 'tinydust';
      final ext = targetSite['ext'];
      if (ext is Map && ext['pwd'] != null) pwd = ext['pwd'].toString();
      Get.toNamed('/mangaDetail', arguments: {
        'vodId': item.vodId,
        'pwd': pwd,
        'site': targetSite,
      });
      return;
    }

    // ---- 原有视频逻辑 ----
    final storedConfigKey = getConfigKey(item.vodId);
    final currentConfigKey = _sourceManager.currentConfigKey.value;
    if (storedConfigKey != null && storedConfigKey != currentConfigKey) {
      SmartDialog.showToast('该收藏所属配置接口 "$storedConfigKey" 已切换，请切换回该配置后重试');
      return;
    }
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
    final isDrpy2 = SourceManager.isDrpy2Site(targetSite);
    final isCatvod = SourceManager.isCatVodOpenSite(targetSite);
    if ((isDrpy2 || isCatvod) && !isCurrent) {
      SmartDialog.showToast('该源暂不支持跳转，请切换到该源后重试');
      return;
    }
    String pwd = 'tinydust';
    final ext = targetSite['ext'];
    if (ext is Map && ext['pwd'] != null) {
      pwd = ext['pwd'].toString();
    }
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