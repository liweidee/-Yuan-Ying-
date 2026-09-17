import 'package:get/get.dart';
import '../models/fnos_media_item.dart';
import '../services/fnos_api_service.dart';
import 'fnos_server_controller.dart';

class FnosFavoriteController extends GetxController {
  final FnosServerController serverController =
      Get.find<FnosServerController>();
  final FnosApiService api = FnosApiService();

  /// 6 个 Tab（与 FlyNarwhal 对齐）
  static const List<String> tabs = [
    '全部',
    '电影',
    '电视节目',
    '电视直播',
    '单集',
    '人物',
  ];

  /// 每个 Tab 的类型映射
  static List<String> typesForTab(int index) {
    switch (index) {
      case 1:
        return ['Movie'];
      case 2:
        return ['TV', 'Season'];
      case 3:
        return ['LiveChannel'];
      case 4:
        return ['Episode'];
      case 5:
        return ['Person'];
      case 0:
      default:
        return [
          'Movie', 'TV', 'Season', 'Episode',
          'Person', 'Directory', 'Video',
        ];
    }
  }

  // ===== 每个 Tab 独立状态 =====
  final RxInt currentTabIndex = 0.obs;

  final Map<int, List<FnosPlayListItem>> _itemsMap = {};
  final Map<int, bool> _loadingMap = {};
  final Map<int, bool> _hasMoreMap = {};
  final Map<int, int> _pageMap = {};
  final Map<int, String> _errorMap = {};

  final RxInt _version = 0.obs; // 用于触发 UI 刷新

  @override
  void onInit() {
    super.onInit();
    loadTab(0, refresh: true);
  }

  // ===== 状态访问（供 UI 使用）=====
  List<FnosPlayListItem> itemsOf(int index) =>
      _itemsMap[index] ?? const [];

  bool loadingOf(int index) => _loadingMap[index] ?? false;

  bool hasMoreOf(int index) => _hasMoreMap[index] ?? true;

  String errorOf(int index) => _errorMap[index] ?? '';

  int get version => _version.value;

  // ===== 加载逻辑 =====

  Future<void> loadTab(int index, {bool refresh = false}) async {
    if (_loadingMap[index] == true) return;

    final server = serverController.currentServer;
    if (server == null) {
      _errorMap[index] = '未选择服务器';
      _version.value++;
      return;
    }
    final token = serverController.getToken(server.id);
    if (token == null) {
      _errorMap[index] = '未登录';
      _version.value++;
      return;
    }

    _loadingMap[index] = true;
    _errorMap[index] = '';
    _version.value++;

    final targetPage = refresh ? 1 : (_pageMap[index] ?? 1);

    try {
      final list = await api.getFavoriteList(
        baseUrl: server.baseUrl,
        token: token,
        types: typesForTab(index),
        page: targetPage,
        pageSize: 40,
      );

      if (refresh) {
        _itemsMap[index] = list;
      } else {
        _itemsMap[index] = [..._itemsMap[index] ?? [], ...list];
      }
      _pageMap[index] = targetPage + 1;
      _hasMoreMap[index] = list.length >= 40;
    } catch (e) {
      _errorMap[index] = e.toString();
    } finally {
      _loadingMap[index] = false;
      _version.value++;
    }
  }

  Future<void> refreshCurrent() async {
    final idx = currentTabIndex.value;
    await loadTab(idx, refresh: true);
  }

  Future<void> loadMore() async {
    final idx = currentTabIndex.value;
    if (_loadingMap[idx] == true || _hasMoreMap[idx] == false) return;
    await loadTab(idx);
  }

  void switchTab(int index) {
    if (index == currentTabIndex.value) return;
    currentTabIndex.value = index;
    // 首次进入该 Tab 时才加载
    if (!_itemsMap.containsKey(index)) {
      loadTab(index, refresh: true);
    }
  }

  /// 取消收藏（同时从本地列表移除）
  Future<bool> removeFavorite(FnosPlayListItem item) async {
    final server = serverController.currentServer;
    if (server == null) return false;
    final token = serverController.getToken(server.id);
    if (token == null) return false;

    try {
      final ok = await api.removeFavorite(
        baseUrl: server.baseUrl,
        token: token,
        itemGuid: item.guid,
      );
      if (ok) {
        // 所有 Tab 里都移除这个 guid
        for (final entry in _itemsMap.entries) {
          entry.value.removeWhere((e) => e.guid == item.guid);
        }
        _version.value++;
      }
      return ok;
    } catch (_) {
      return false;
    }
  }
}