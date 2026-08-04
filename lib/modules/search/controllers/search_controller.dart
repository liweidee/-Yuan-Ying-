import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/services/search_filter_service.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/t4_api_service.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';

/// 热搜项模型
class HotItem {
  final String title;
  final String cover;
  final String comment;
  final String upinfo;
  final String pv;
  final List<String> moviecat;
  final String pubdate;
  final String url;

  HotItem({
    required this.title,
    required this.cover,
    required this.comment,
    required this.upinfo,
    required this.pv,
    required this.moviecat,
    required this.pubdate,
    required this.url,
  });

  factory HotItem.fromJson(Map<String, dynamic> json) {
    final moviecatRaw = json['moviecat'] as List? ?? [];
    final moviecat = moviecatRaw.map((e) => e.toString()).toList();
    return HotItem(
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      comment: json['comment']?.toString() ?? '',
      upinfo: json['upinfo']?.toString() ?? '',
      pv: json['pv']?.toString() ?? '',
      moviecat: moviecat,
      pubdate: json['pubdate']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }
}

class SearchPageController extends GetxController {
  final SourceManager _sourceManager = Get.find<SourceManager>();
  late ISpiderService _apiService;
  final SearchFilterService _filterService = Get.find<SearchFilterService>();

  // ===== 搜索状态 =====
  final searchKeyword = ''.obs;
  final isSearching = false.obs;

  // ===== 搜索历史 =====
  final historyList = <String>[].obs;
  static const int maxHistoryCount = 20;

  // ===== 热搜 =====
  final hotList = <HotItem>[].obs;
  final isLoadingHot = false.obs;
  final isHotError = false.obs;

  // ===== 获取启用的源 key 列表 =====
  List<String> get enabledSourceKeyList {
    return _filterService.enabledSourceKeyList;
  }

  // ===== 生命周期 =====
  @override
  void onInit() {
    super.onInit();
    _apiService = Get.find<SourceManager>().currentApiService;
    _loadHistory();
    _loadHotData();
  }

  // ===== 搜索历史 =====
  void _loadHistory() {
    final data = GStorage.historyWord.get('search_history');
    if (data is List) {
      historyList.value = data.map((e) => e.toString()).toList();
    }
  }

  void _saveHistory() {
    GStorage.historyWord.put('search_history', historyList.toList());
  }

  void addHistory(String keyword) {
    if (keyword.trim().isEmpty) return;
    historyList.remove(keyword);
    historyList.insert(0, keyword);
    if (historyList.length > maxHistoryCount) {
      historyList.removeLast();
    }
    _saveHistory();
  }

  void clearHistory() {
    historyList.clear();
    _saveHistory();
  }

  void removeHistory(String keyword) {
    historyList.remove(keyword);
    _saveHistory();
  }

  // ===== 热搜数据 =====
  Future<void> _loadHotData() async {
    isLoadingHot.value = true;
    isHotError.value = false;
    try {
      final dio = Dio();
      final response = await dio.get(
        'https://api.web.360kan.com/v1/rank?cat=1',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['errno'] == 0 && data['data'] is List) {
          final list = (data['data'] as List).map((item) => HotItem.fromJson(item)).toList();
          hotList.value = list;
        } else {
          isHotError.value = true;
        }
      } else {
        isHotError.value = true;
      }
    } catch (e) {
      print('加载热搜失败: $e');
      isHotError.value = true;
    } finally {
      isLoadingHot.value = false;
    }
  }

  Future<void> refreshHotData() async {
    await _loadHotData();
  }

  // ===== 执行搜索 =====
  void doSearch({String? keyword}) {
    final query = (keyword ?? searchKeyword.value).trim();
    if (query.isEmpty) return;

    final sources = enabledSourceKeyList;
    if (sources.isEmpty) {
      SmartDialog.showToast('当前源暂不支持搜索');
      return;
    }

    addHistory(query);
    final onlyDefault = _filterService.onlyDefaultSource.value;
    Get.toNamed(
      '/search_result',
      arguments: {
        'keyword': query,
        'sources': sources,
        'onlyDefault': onlyDefault,
      },
    );
  }

  // ===== 点击热搜项 =====
  void onHotItemTap(HotItem item) {
    doSearch(keyword: item.title);
  }

  // ===== 点击历史标签 =====
  void onHistoryTap(String keyword) {
    searchKeyword.value = keyword;
    doSearch(keyword: keyword);
  }

  // ===== 清空搜索框 =====
  void clearSearch() {
    searchKeyword.value = '';
  }
}