import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/services/search_filter_service.dart';
import 'package:yuanying/t4/services/t4_api_service.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';

/// 分页状态
class _PaginationState {
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

/// 搜索结果控制器
class SearchResultController extends GetxController {
  late ISpiderService _apiService;
  final SearchFilterService _filterService = Get.find<SearchFilterService>();
  final SourceManager _sourceManager = Get.find<SourceManager>();

  // ===== 路由参数 =====
  late String keyword;
  late List<String> sourceKeys;
  late bool onlyDefault;

  // ===== 状态 =====
  final currentSourceKey = 'all'.obs;
  final isLoading = false.obs;
  final isError = false.obs;
  final errorMsg = ''.obs;

  // 源选项列表（响应式）
  final sourceOptions = <String>[].obs;

  // ===== 各源数据 =====
  final Map<String, _PaginationState> _sourceData = {};
  final Map<String, int> sourceCounts = {};

  // ===== 获取当前显示的数据 =====
  List<VideoItem> get currentItems {
    if (currentSourceKey.value == 'all') {
      return _getAllItems();
    }
    return _sourceData[currentSourceKey.value]?.items ?? [];
  }

  // ===== 获取当前源的结果数量 =====
  int getCurrentCount() {
    if (currentSourceKey.value == 'all') {
      return _getAllItems().length;
    }
    return sourceCounts[currentSourceKey.value] ?? 0;
  }

  // ===== 获取源名称 =====
  String getSourceName(String? sourceKey) {
    if (sourceKey == null || sourceKey.isEmpty) return '未知来源';
    final site = _sourceManager.sites.firstWhere(
      (s) => s['key']?.toString() == sourceKey,
      orElse: () => {},
    );
    return site['name']?.toString() ?? '未知来源';
  }

  // ===== 获取源显示数量 =====
  String getSourceCountDisplay(String key) {
    if (key == 'all') {
      final count = _getAllItems().length;
      return '$count 个结果';
    }
    final count = sourceCounts[key] ?? 0;
    return '$count 个结果';
  }

  // ===== 判断是否选中 =====
  bool isSelected(String key) => currentSourceKey.value == key;

  // ===== 合并所有源结果（去重） =====
  List<VideoItem> _getAllItems() {
    final allItems = <VideoItem>[];
    final seenIds = <String>{};
    for (final key in sourceKeys) {
      final items = _sourceData[key]?.items ?? [];
      for (final item in items) {
        if (!seenIds.contains(item.vodId)) {
          seenIds.add(item.vodId);
          allItems.add(item);
        }
      }
    }
    return allItems;
  }

  // ===== 更新源选项列表（触发 UI 更新） =====
  void _updateSourceOptions() {
    final list = <String>['all'];
    list.addAll(sourceKeys);
    sourceOptions.value = list;
  }

  // ===== 初始化 =====
  @override
  void onInit() {
    super.onInit();
    _apiService = Get.find<SourceManager>().currentApiService;
    final args = Get.arguments as Map<String, dynamic>?;
    if (args == null) {
      isError.value = true;
      errorMsg.value = '参数错误';
      return;
    }

    keyword = args['keyword']?.toString() ?? '';
    sourceKeys = (args['sources'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    onlyDefault = args['onlyDefault'] ?? false;

    if (keyword.isEmpty || sourceKeys.isEmpty) {
      isError.value = true;
      errorMsg.value = '搜索参数错误';
      return;
    }

    // 初始化各源分页状态
    for (final key in sourceKeys) {
      _sourceData[key] = _PaginationState();
    }

    // 初始化选项列表
    _updateSourceOptions();

    // 开始搜索
    _searchAll();
  }

  // ===== 搜索所有源 =====
  Future<void> _searchAll() async {
    isLoading.value = true;
    isError.value = false;
    errorMsg.value = '';

    // 重置所有分页状态
    for (final key in sourceKeys) {
      _sourceData[key]?.reset();
    }
    sourceCounts.clear();

    try {
      // 顺序请求所有源的第一页
      for (final key in sourceKeys) {
        await _searchSource(key, 1);
      }
      // 更新选项列表
      _updateSourceOptions();
    } catch (e) {
      isError.value = true;
      errorMsg.value = '搜索失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  // ===== 搜索单个源 =====
  Future<void> _searchSource(String sourceKey, int page) async {
    _apiService = Get.find<SourceManager>().currentApiService;
    final state = _sourceData[sourceKey];
    if (state == null) return;

    final site = _sourceManager.sites.firstWhere(
      (s) => s['key']?.toString() == sourceKey,
      orElse: () => {},
    );
    if (site.isEmpty) {
      print('站点不存在: $sourceKey');
      state.isEnd = true;
      _updateSourceOptions();
      update();
      return;
    }

    final api = site['api']?.toString() ?? '';
    final ext = site['ext'];

    try {
      final result = await _apiService.searchDirect(
        baseUrl: api,
        ext: ext,
        wd: keyword,
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

      // 去重：只添加新的数据
      final existingIds = state.items.map((item) => item.vodId).toSet();
      final newItems = list.where((item) => !existingIds.contains(item.vodId)).toList();

      if (newItems.isEmpty) {
        // 没有新数据，停止分页
        print('搜索源 $sourceKey 第 $page 页没有新数据（已去重），停止分页');
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
    } catch (e) {
      print('搜索源 $sourceKey 失败: $e');
      if (page == 1) {
        sourceCounts[sourceKey] = 0;
        state.isEnd = true;
      }
    } finally {
      _updateSourceOptions();
      update();
    }
  }

  // ===== 加载更多 =====
  Future<void> loadMore() async {
    final key = currentSourceKey.value;
    if (key == 'all') {
      // "全部" 加载更多：检查所有源是否都已完成
      bool allEnd = true;
      for (final k in sourceKeys) {
        final state = _sourceData[k];
        if (state != null && state.canLoadMore) {
          allEnd = false;
          break;
        }
      }
      if (allEnd) return;

      // 为每个未完成的源加载下一页
      for (final k in sourceKeys) {
        final state = _sourceData[k];
        if (state != null && state.canLoadMore) {
          await _searchSource(k, state.page);
        }
      }
    } else {
      // 单个源加载更多
      final state = _sourceData[key];
      if (state == null || !state.canLoadMore) return;
      await _searchSource(key, state.page);
    }

    // 强制更新 UI
    _updateSourceOptions();
    update();
  }

  // ===== 切换源 =====
  void switchSource(String key) {
    if (currentSourceKey.value == key) return;
    currentSourceKey.value = key;
    update();
  }

  // ===== 刷新当前源 =====
  Future<void> refreshCurrent() async {
    final key = currentSourceKey.value;
    if (key == 'all') {
      await _searchAll();
    } else {
      final state = _sourceData[key];
      if (state != null) {
        state.reset();
        sourceCounts.remove(key);
        await _searchSource(key, 1);
        _updateSourceOptions();
        update();
      }
    }
  }

  // ===== 解析视频列表 =====
  List<VideoItem> _parseVideoList(dynamic result, String sourceKey) {
    final list = <VideoItem>[];
    final listData = result is Map ? result['list'] : result;

    if (listData is List) {
      for (final item in listData) {
        if (item is Map<String, dynamic>) {
          final videoItem = VideoItem.fromJson(item);
          // 保留原始 vodTag，同时用 vodSource 存储来源 key
          list.add(VideoItem(
            vodId: videoItem.vodId,
            vodName: videoItem.vodName,
            vodPic: videoItem.vodPic,
            vodRemarks: videoItem.vodRemarks,
            vodActor: videoItem.vodActor,
            typeName: videoItem.typeName,
            vodTag: videoItem.vodTag,      // 保留原值（可能为 'folder' 等）
            vodSource: sourceKey,          // 新增来源标识
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
            vodTag: videoItem.vodTag,
            vodSource: sourceKey,
          ));
        }
      }
    }
    return list;
  }

  // ===== 点击结果项 =====
  void onItemTap(VideoItem item) {
    final String? sourceKey = item.vodSource; // 改为使用 vodSource
    Map<String, dynamic>? targetSite;
    bool isCurrent = false;

    if (sourceKey != null && sourceKey.isNotEmpty) {
      try {
        targetSite = _sourceManager.sites.firstWhere(
          (s) => s['key']?.toString() == sourceKey,
        );
        final current = _sourceManager.currentSite.value;
        if (current != null && current['key']?.toString() == sourceKey) {
          isCurrent = true;
        }
      } catch (_) {
        targetSite = null;
      }
    }

    // 兜底：使用当前站点
    if (targetSite == null) {
      final current = _sourceManager.currentSite.value;
      if (current != null) {
        targetSite = current;
        isCurrent = true;
      } else {
        SmartDialog.showToast('无法获取播放源');
        return;
      }
    }

    // drpy2 / Catvod 且非当前源，拒绝跳转
    final isDrpy2 = SourceManager.isDrpy2Site(targetSite!);
    final isCatvod = SourceManager.isCatVodOpenSite(targetSite);
    if ((isDrpy2 || isCatvod) && !isCurrent) {
      SmartDialog.showToast('该源暂不支持从聚合搜索跳转，请切换到该源后重试');
      return;
    }

    // 提取 pwd
    String pwd = 'tinydust';
    final ext = targetSite['ext'];
    if (ext is Map && ext['pwd'] != null) {
      pwd = ext['pwd'].toString();
    }

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

  // ===== 重新搜索 =====
  void retry() {
    _searchAll();
  }

  // ===== 返回 =====
  void goBack() {
    Get.back();
  }

  // ===== 关闭页面 =====
  void closePage() {
    Get.back();
  }

  // ===== 重新执行搜索 =====
  void reSearch() {
    _searchAll();
  }
}