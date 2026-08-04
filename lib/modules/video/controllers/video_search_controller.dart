// lib/modules/video/controllers/video_search_controller.dart
import 'package:get/get.dart';
import 'package:yuanying/services/search_filter_service.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/t4/services/t4_api_service.dart';
import 'package:yuanying/t4/services/drpy2_api_service.dart';
import 'package:yuanying/t4/services/xbpq_service.dart';
import 'package:yuanying/t4/services/catvod_open_service.dart';
import 'package:yuanying/t4/services/py3_spider_service.dart';

/// 每个源的分页状态
class _SearchPagination {
  int page = 1;
  bool isEnd = false;
  bool isLoading = false;
  List<VideoItem> items = [];

  void reset() {
    page = 1;
    isEnd = false;
    isLoading = false;
    items.clear();
  }

  bool get canLoadMore => !isEnd && !isLoading;
}

class DetailSearchController extends GetxController {
  final SourceManager _sourceManager = Get.find<SourceManager>();
  final SearchFilterService _filterService = Get.find<SearchFilterService>();

  // ===== 输入状态 =====
  final keyword = ''.obs;
  final isLoading = false.obs;
  final isError = false.obs;
  final errorMsg = ''.obs;

  // ===== 当前选中的源 key =====
  final currentSourceKey = ''.obs;

  // ===== 【修复】sourceKeys 改为 RxList =====
  final sourceKeys = <String>[].obs;

  // ===== 各源数据 =====
  final Map<String, _SearchPagination> _sourceData = {};
  final Map<String, int> sourceCounts = {};

  // ===== 【修复】currentItems 改为 RxList =====
  final currentItems = <VideoItem>[].obs;

  // ===== 更新 sourceKeys =====
  void _updateSourceKeys() {
    List<String> keys;
    if (_filterService.onlyDefaultSource.value) {
      final current = _sourceManager.currentSite.value;
      final key = current?['key']?.toString() ?? '';
      keys = key.isNotEmpty ? [key] : [];
    } else {
      keys = _filterService.enabledSourceKeyList;
    }
    sourceKeys.value = keys;
  }

  // ===== 更新 currentItems =====
  void _updateCurrentItems() {
    final key = currentSourceKey.value;
    if (key.isEmpty) {
      currentItems.clear();
      return;
    }
    final items = _sourceData[key]?.items ?? [];
    currentItems.value = items;
  }

  // ===== 重新初始化源（当 onlyDefaultSource 变化时调用） =====
  void reinitSources() {
    _updateSourceKeys();
    // 重置所有数据
    for (final key in _sourceData.keys.toList()) {
      _sourceData[key]?.reset();
    }
    sourceCounts.clear();
    if (sourceKeys.isNotEmpty) {
      currentSourceKey.value = sourceKeys.first;
      _updateCurrentItems();
    } else {
      currentSourceKey.value = '';
      currentItems.clear();
    }
  }

  // ===== 获取当前源的结果数量 =====
  int getCurrentCount(String key) {
    return sourceCounts[key] ?? 0;
  }

  // ===== 获取源名称 =====
  String getSourceName(String key) {
    final site = _sourceManager.sites.firstWhere(
      (s) => s['key']?.toString() == key,
      orElse: () => {},
    );
    return site['name']?.toString() ?? key;
  }

  // ===== 判断是否选中 =====
  bool isSelected(String key) => currentSourceKey.value == key;

  // ===== 初始化 =====
  @override
  void onInit() {
    super.onInit();
    
    // 监听 onlyDefaultSource 和 enabledSourceKeys 的变化，自动更新源列表
    ever(_filterService.onlyDefaultSource, (_) {
      reinitSources();
    });
    ever(_filterService.enabledSourceKeys, (_) {
      if (!_filterService.onlyDefaultSource.value) {
        reinitSources();
      }
    });
    
    _updateSourceKeys();
    _initSources();
  }

  void _initSources() {
    for (final key in sourceKeys) {
      if (!_sourceData.containsKey(key)) {
        _sourceData[key] = _SearchPagination();
      }
    }
    if (sourceKeys.isNotEmpty) {
      currentSourceKey.value = sourceKeys.first;
      _updateCurrentItems();
    }
  }

  // ===== 执行搜索 =====
  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      isError.value = true;
      errorMsg.value = '请输入搜索关键词';
      return;
    }

    keyword.value = q;
    isLoading.value = true;
    isError.value = false;
    errorMsg.value = '';

    // 重置所有分页状态
    for (final key in sourceKeys) {
      _sourceData[key]?.reset();
    }
    sourceCounts.clear();

    try {
      final futures = sourceKeys.map((key) => _searchSource(key, 1)).toList();
      await Future.wait(futures);

      final totalCount = sourceCounts.values.fold(0, (sum, c) => sum + c);
      if (totalCount == 0) {
        isError.value = true;
        errorMsg.value = '未找到相关结果';
      }
    } catch (e) {
      isError.value = true;
      errorMsg.value = '搜索失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  // ===== 搜索单个源 =====
  Future<void> _searchSource(String sourceKey, int page) async {
    final state = _sourceData[sourceKey];
    if (state == null) return;

    final site = _sourceManager.sites.firstWhere(
      (s) => s['key']?.toString() == sourceKey,
      orElse: () => {},
    );
    if (site.isEmpty) {
      state.isEnd = true;
      return;
    }

    final api = site['api']?.toString() ?? '';
    final ext = site['ext'];

    try {
      final service = _getServiceForSite(site);
      final result = await service.searchDirect(
        baseUrl: api,
        ext: ext,
        wd: keyword.value,
        page: page,
        quick: 0,
      );

      final list = _parseVideoList(result, sourceKey);

      if (list.isEmpty) {
        state.isEnd = true;
        if (page == 1) {
          sourceCounts[sourceKey] = 0;
        }
        return;
      }

      final existingIds = state.items.map((item) => item.vodId).toSet();
      final newItems = list.where((item) => !existingIds.contains(item.vodId)).toList();

      if (newItems.isEmpty) {
        state.isEnd = true;
        return;
      }

      if (page == 1) {
        state.items = newItems;
        sourceCounts[sourceKey] = newItems.length;
      } else {
        state.items.addAll(newItems);
        sourceCounts[sourceKey] = state.items.length;
      }
      state.page = page + 1;

      if (currentSourceKey.value == sourceKey) {
        _updateCurrentItems();
      }
    } catch (e) {
      print('搜索源 $sourceKey 失败: $e');
      if (page == 1) {
        sourceCounts[sourceKey] = 0;
        state.isEnd = true;
      }
    }
  }

  // ===== 获取对应类型的服务 =====
  ISpiderService _getServiceForSite(Map<String, dynamic> site) {
    final key = site['key']?.toString() ?? '';
    final api = site['api']?.toString() ?? '';

    if (SourceManager.isDrpy2Site(site)) {
      return Get.find<Drpy2ApiService>();
    }
    if (SourceManager.isXbpqSite(site)) {
      final tag = 'xbpq_$key';
      if (!Get.isRegistered<XbpqService>(tag: tag)) {
        Get.put(XbpqService(key, api, site['ext']?.toString() ?? '', []), tag: tag, permanent: true);
      }
      return Get.find<XbpqService>(tag: tag);
    }
    if (SourceManager.isCatVodOpenSite(site)) {
      return Get.find<CatvodOpenService>();
    }
    if (SourceManager.isPurePy3Site(site)) {
      final tag = 'py3_$key';
      if (!Get.isRegistered<Py3SpiderService>(tag: tag)) {
        Get.put(Py3SpiderService(key), tag: tag, permanent: true);
      }
      return Get.find<Py3SpiderService>(tag: tag);
    }
    return Get.find<T4ApiService>();
  }

  // ===== 解析视频列表，并注入 sourceKey =====
  List<VideoItem> _parseVideoList(dynamic result, String sourceKey) {
    final list = <VideoItem>[];
    final listData = result is Map ? result['list'] : result;

    if (listData is List) {
      for (final item in listData) {
        if (item is Map<String, dynamic>) {
          final videoItem = VideoItem.fromJson(item);
          list.add(VideoItem(
            vodId: videoItem.vodId,
            vodName: videoItem.vodName,
            vodPic: videoItem.vodPic,
            vodRemarks: videoItem.vodRemarks,
            vodActor: videoItem.vodActor,
            typeName: videoItem.typeName,
            vodTag: sourceKey,
          ));
        } else if (item is Map) {
          final Map<String, dynamic> castMap = {};
          item.forEach((k, v) {
            castMap[k.toString()] = v;
          });
          final videoItem = VideoItem.fromJson(castMap);
          list.add(VideoItem(
            vodId: videoItem.vodId,
            vodName: videoItem.vodName,
            vodPic: videoItem.vodPic,
            vodRemarks: videoItem.vodRemarks,
            vodActor: videoItem.vodActor,
            typeName: videoItem.typeName,
            vodTag: sourceKey,
          ));
        }
      }
    }
    return list;
  }

  // ===== 加载更多 =====
  Future<void> loadMore() async {
    final key = currentSourceKey.value;
    if (key.isEmpty) return;

    final state = _sourceData[key];
    if (state == null || !state.canLoadMore) return;

    await _searchSource(key, state.page);
  }

  // ===== 切换源 =====
  void switchSource(String key) {
    if (currentSourceKey.value == key) return;
    currentSourceKey.value = key;
    _updateCurrentItems();
  }

  // ===== 刷新当前源 =====
  Future<void> refreshCurrent() async {
    final key = currentSourceKey.value;
    if (key.isEmpty) return;

    final state = _sourceData[key];
    if (state != null) {
      state.reset();
      sourceCounts.remove(key);
      await _searchSource(key, 1);
      _updateCurrentItems();
    }
  }

  // ===== 重置 =====
  void reset() {
    for (final key in sourceKeys) {
      _sourceData[key]?.reset();
    }
    sourceCounts.clear();
    isError.value = false;
    errorMsg.value = '';
    if (sourceKeys.isNotEmpty) {
      currentSourceKey.value = sourceKeys.first;
      _updateCurrentItems();
    }
  }

  @override
  void onClose() {
    _sourceData.clear();
    sourceCounts.clear();
    currentItems.close();
    sourceKeys.close();
    super.onClose();
  }
}