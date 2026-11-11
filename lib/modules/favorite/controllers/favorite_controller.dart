import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/core/constants/app_constants.dart';

class FavoriteController extends GetxController {
  final videoList = <VideoItem>[].obs;

  // ===== 所有辅助 map 统一使用复合 key =====
  final _apiUrlMap     = <String, String>{}.obs;
  final _siteKeyMap    = <String, String>{}.obs;
  final _configKeyMap  = <String, String>{}.obs;
  final _detailTypeMap = <String, String>{}.obs;

  // 与 videoList 一一对应的复合 key
  final List<String> _recordKeys = [];

  final filterType = 'all'.obs;
  final isLoading = false.obs;

  final SourceManager _sourceManager = Get.find<SourceManager>();

  // ==========================================================================
  // 复合 key 工具
  // ==========================================================================

  static String _makeKey(String vodId, String apiUrl) =>
      apiUrl.isEmpty ? vodId : '$vodId|$apiUrl';

  String _keyOf(VideoItem item) {
    final idx = videoList.indexOf(item);
    if (idx >= 0 && idx < _recordKeys.length) return _recordKeys[idx];
    return item.vodId;
  }

  // ==========================================================================
  // 过滤
  // ==========================================================================

  List<VideoItem> get filteredList {
    if (filterType.value == 'all') return videoList;
    final result = <VideoItem>[];
    for (int i = 0; i < videoList.length; i++) {
      final key = i < _recordKeys.length
          ? _recordKeys[i]
          : videoList[i].vodId;
      if (_detailTypeMap[key] == filterType.value) {
        result.add(videoList[i]);
      }
    }
    return result;
  }

  @override
  void onInit() {
    super.onInit();
    loadFavorites();
  }

  // ==========================================================================
  // 加载
  // ==========================================================================

  void loadFavorites() {
    isLoading.value = true;
    try {
      final data = GStorage.getFavorites();
      final list     = <VideoItem>[];
      final keys     = <String>[];
      final urlM     = <String, String>{};
      final siteM    = <String, String>{};
      final configM  = <String, String>{};
      final typeM    = <String, String>{};

      for (final item in data) {
        final v = VideoItem.fromJson(item);
        final apiUrl = item['api_url']?.toString() ?? '';
        final key = _makeKey(v.vodId, apiUrl);

        list.add(v);
        keys.add(key);

        if (apiUrl.isNotEmpty) urlM[key] = apiUrl;
        if (item['site_key'] != null) {
          siteM[key] = item['site_key'].toString();
        }
        if (item['config_key'] != null) {
          configM[key] = item['config_key'].toString();
        }
        typeM[key] = item['detail_type']?.toString() ?? 'video';
      }

      videoList.value = list;
      _recordKeys
        ..clear()
        ..addAll(keys);
      _apiUrlMap.value     = urlM;
      _siteKeyMap.value    = siteM;
      _configKeyMap.value  = configM;
      _detailTypeMap.value = typeM;
    } catch (e) {
      print('加载收藏失败: $e');
      _clearState();
    } finally {
      isLoading.value = false;
    }
  }

  void _clearState() {
    videoList.clear();
    _recordKeys.clear();
    _apiUrlMap.clear();
    _siteKeyMap.clear();
    _configKeyMap.clear();
    _detailTypeMap.clear();
  }

  // ==========================================================================
  // 删除 / 清空
  // ==========================================================================

  Future<void> clearAll() async {
    await GStorage.clearFavorites();
    _clearState();
  }

  Future<void> removeFavorite(VideoItem item) async {
    final key = _keyOf(item);
    final apiUrl = _apiUrlMap[key] ?? '';
    await GStorage.removeFavorite(item.vodId, apiUrl);

    final idx = videoList.indexOf(item);
    if (idx >= 0) {
      videoList.removeAt(idx);
      if (idx < _recordKeys.length) _recordKeys.removeAt(idx);
    }

    _apiUrlMap.remove(key);
    _siteKeyMap.remove(key);
    _configKeyMap.remove(key);
    _detailTypeMap.remove(key);
  }

  // ==========================================================================
  // 时间格式化
  // ==========================================================================

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

  // ==========================================================================
  // 跳转
  // ==========================================================================

  void navigateToDetail(VideoItem item) {
    final key = _keyOf(item);
    final type = _detailTypeMap[key] ?? 'video';

    // ---- 小说 ----
    if (type == 'novel') {
      final storedConfigKey = _configKeyMap[key];
      final currentConfigKey = _sourceManager.currentConfigKey.value;
      if (storedConfigKey != null && storedConfigKey != currentConfigKey) {
        SmartDialog.showToast('该小说所属配置接口 "$storedConfigKey" 已切换，请切换回该配置后重试');
        return;
      }
      final siteKey = _siteKeyMap[key];
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
      final storedConfigKey = _configKeyMap[key];
      final currentConfigKey = _sourceManager.currentConfigKey.value;
      if (storedConfigKey != null && storedConfigKey != currentConfigKey) {
        SmartDialog.showToast('该漫画所属配置接口 "$storedConfigKey" 已切换，请切换回该配置后重试');
        return;
      }
      final siteKey = _siteKeyMap[key];
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

    // ---- 音频 ----
    if (type == 'audio') {
      final storedConfigKey = _configKeyMap[key];
      final currentConfigKey = _sourceManager.currentConfigKey.value;
      if (storedConfigKey != null && storedConfigKey != currentConfigKey) {
        SmartDialog.showToast('该音频所属配置接口 "$storedConfigKey" 已切换，请切换回该配置后重试');
        return;
      }
      final siteKey = _siteKeyMap[key];
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
      Get.toNamed('/musicDetail', arguments: {
        'vodId': item.vodId,
        'pwd': pwd,
        'site': targetSite,
      });
      return;
    }

    // ---- 视频 ----
    final storedConfigKey = _configKeyMap[key];
    final currentConfigKey = _sourceManager.currentConfigKey.value;
    if (storedConfigKey != null && storedConfigKey != currentConfigKey) {
      SmartDialog.showToast('该收藏所属配置接口 "$storedConfigKey" 已切换，请切换回该配置后重试');
      return;
    }
    final siteKey = _siteKeyMap[key];
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
      final apiUrl = _apiUrlMap[key];
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