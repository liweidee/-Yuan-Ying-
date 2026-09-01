import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/core/constants/app_constants.dart';

class HistoryController extends GetxController {
  final videoList = <VideoItem>[].obs;
  final progressMap = <String, String>{}.obs;
  final timeMap = <String, int>{}.obs;
  final _apiUrlMap = <String, String>{}.obs;
  final _siteKeyMap = <String, String>{}.obs;
  final _configKeyMap = <String, String>{}.obs;
  final _detailTypeMap = <String, String>{}.obs;

  // 过滤类型
  final filterType = 'all'.obs;  // 'all', 'video', 'audio', 'novel', 'manga'
  final isLoading = false.obs;

  String? getConfigKey(String vodId) => _configKeyMap[vodId];

  final SourceManager _sourceManager = Get.find<SourceManager>();

  // 计算属性：过滤后的列表
  List<VideoItem> get filteredList {
    if (filterType.value == 'all') return videoList;
    return videoList.where((item) {
      return _detailTypeMap[item.vodId] == filterType.value;
    }).toList();
  }

  @override
  void onInit() {
    super.onInit();
    loadHistory();
  }

  void loadHistory() {
    isLoading.value = true;
    try {
      final data = GStorage.getHistory();
      final list = <VideoItem>[];
      final progress = <String, String>{};
      final times = <String, int>{};
      final urlMap = <String, String>{};
      final siteKeyMap = <String, String>{};
      for (final item in data) {
        final videoItem = VideoItem.fromJson(item);
        if (item['config_key'] != null) {
          _configKeyMap[videoItem.vodId] = item['config_key'].toString();
        }
        list.add(videoItem);
        if (item['progress'] != null) {
          progress[videoItem.vodId] = item['progress'].toString();
        }
        if (item['watchTime'] != null) {
          times[videoItem.vodId] = item['watchTime'] as int;
        }
        if (item['api_url'] != null) {
          urlMap[videoItem.vodId] = item['api_url'].toString();
        }
        if (item['site_key'] != null) {
          siteKeyMap[videoItem.vodId] = item['site_key'].toString();
        }
        // 解析 detail_type，兼容旧数据
        final type = item['detail_type']?.toString() ?? 'video';
        _detailTypeMap[videoItem.vodId] = type;
      }
      videoList.value = list;
      progressMap.value = progress;
      timeMap.value = times;
      _apiUrlMap.value = urlMap;
      _siteKeyMap.value = siteKeyMap;
    } catch (e) {
      print('加载历史失败: $e');
      videoList.clear();
      progressMap.clear();
      timeMap.clear();
      _apiUrlMap.clear();
      _siteKeyMap.clear();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> clearAll() async {
    await GStorage.clearHistory();
    videoList.clear();
    progressMap.clear();
    timeMap.clear();
    _apiUrlMap.clear();
  }

  Future<void> removeHistory(String vodId) async {
    await GStorage.removeHistory(vodId);
    videoList.removeWhere((item) => item.vodId == vodId);
    progressMap.remove(vodId);
    timeMap.remove(vodId);
    _apiUrlMap.remove(vodId);
  }

  String? getProgress(String vodId) => progressMap[vodId];
  int? getWatchTime(String vodId) => timeMap[vodId];
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

  // ===== 跳转时使用存储的 api_url，并根据类型路由 =====
  void navigateToDetail(VideoItem item) {
    final type = _detailTypeMap[item.vodId] ?? 'video';

    // ---- 小说路由 ----
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

    // ---- 漫画路由 ----
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

    // ---- 音频 ----
    if (type == 'audio') {
      final storedConfigKey = getConfigKey(item.vodId);
      final currentConfigKey = _sourceManager.currentConfigKey.value;
      if (storedConfigKey != null && storedConfigKey != currentConfigKey) {
        SmartDialog.showToast('该音频所属配置接口 "$storedConfigKey" 已切换，请切换回该配置后重试');
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
      Get.toNamed('/musicDetail', arguments: {
        'vodId': item.vodId,
        'pwd': pwd,
        'site': targetSite,
      });
      return;
    }

    // 配置一致性检查
    final storedConfigKey = getConfigKey(item.vodId);
    final currentConfigKey = _sourceManager.currentConfigKey.value;
    if (storedConfigKey != null && storedConfigKey != currentConfigKey) {
      SmartDialog.showToast('该收藏所属配置接口 "$storedConfigKey" 已切换，请切换回该配置后重试');
      return;
    }
    // 1. 优先使用存储的 site_key 查找完整站点
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
    // 2. 如果找不到站点，尝试用 api_url 回退
    if (targetSite == null) {
      final apiUrl = getApiUrl(item.vodId);
      if (apiUrl != null && apiUrl.isNotEmpty) {
        Get.toNamed('/detail', arguments: {
          'vodId': item.vodId,
          'apiUrl': apiUrl,
        });
        return;
      }
      SmartDialog.showToast('该历史记录已失效，请重新播放生成新记录');
      return;
    }
    // 3. 判断是否为 drpy2 / Catvod 且非当前源
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
    // 非当前源且非 drpy2/catvod → 传入 site
    if (!isCurrent && !isDrpy2 && !isCatvod) {
      args['site'] = targetSite;
    }
    Get.toNamed('/detail', arguments: args);
  }
}