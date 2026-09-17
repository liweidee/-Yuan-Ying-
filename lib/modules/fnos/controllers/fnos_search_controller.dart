import 'dart:async';
import 'package:get/get.dart';
import '../models/fnos_media_item.dart';
import '../services/fnos_api_service.dart';
import 'fnos_server_controller.dart';

class FnosSearchController extends GetxController {
  final FnosServerController serverController =
      Get.find<FnosServerController>();
  final FnosApiService api = FnosApiService();

  /// 6 个分类 Tab（与 FlyNarwhal 对齐）
  static const List<String> tabs = [
    '全部',
    '电影',
    '电视剧',
    '电视直播',
    '人物',
    '其他',
  ];

  // ===== 状态 =====
  final RxString keyword = ''.obs;
  final RxInt selectedTabIndex = 0.obs;
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;
  final RxList<FnosPlayListItem> rawResults = <FnosPlayListItem>[].obs;

  Timer? _debounce;
  int _requestToken = 0;

  /// 按当前 Tab 过滤后的结果
  List<FnosPlayListItem> get filteredResults {
    if (selectedTabIndex.value == 0) return rawResults;
    final tab = tabs[selectedTabIndex.value];
    return rawResults.where((item) {
      final t = item.type ?? '';
      switch (tab) {
        case '电影':
          return t == 'Movie';
        case '电视剧':
          return t == 'TV' || t == 'Season' || t == 'Episode';
        case '电视直播':
          return t == 'LiveChannel';
        case '人物':
          return t == 'Person';
        case '其他':
          return t != 'Movie' &&
              t != 'TV' &&
              t != 'Season' &&
              t != 'Episode' &&
              t != 'LiveChannel' &&
              t != 'Person';
        default:
          return true;
      }
    }).toList();
  }

  /// 是否有已搜索（用于区分"初始态"和"无结果"）
  bool get hasSearched => keyword.value.trim().isNotEmpty &&
      !isLoading.value &&
      error.value.isEmpty;

  // ===== 输入 =====
  void onKeywordChanged(String value) {
    keyword.value = value;
    _debounce?.cancel();

    // 空输入 → 重置
    if (value.trim().isEmpty) {
      _requestToken++;
      rawResults.clear();
      isLoading.value = false;
      error.value = '';
      return;
    }

    // 300ms 防抖
    isLoading.value = true;
    error.value = '';
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _doSearch(value);
    });
  }

  /// 切换分类 Tab
  void switchTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    selectedTabIndex.value = index;
  }

  /// 清空搜索
  void clear() {
    _debounce?.cancel();
    _requestToken++;
    keyword.value = '';
    rawResults.clear();
    isLoading.value = false;
    error.value = '';
    selectedTabIndex.value = 0;
  }

  /// 手动触发搜索（用于重试）
  Future<void> retry() async {
    if (keyword.value.trim().isEmpty) return;
    await _doSearch(keyword.value);
  }

  Future<void> _doSearch(String query) async {
    final server = serverController.currentServer;
    if (server == null) {
      error.value = '未选择服务器';
      isLoading.value = false;
      return;
    }
    final token = serverController.getToken(server.id);
    if (token == null) {
      error.value = '未登录';
      isLoading.value = false;
      return;
    }

    final token0 = ++_requestToken;

    try {
      final list = await api.search(
        baseUrl: server.baseUrl,
        token: token,
        keyword: query.trim(),
      );

      // 丢弃过期响应
      if (token0 != _requestToken) return;

      rawResults.value = list;
      error.value = '';
    } catch (e) {
      if (token0 != _requestToken) return;
      error.value = e.toString();
      rawResults.clear();
    } finally {
      if (token0 == _requestToken) {
        isLoading.value = false;
      }
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }
}