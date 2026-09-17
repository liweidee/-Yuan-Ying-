import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/fnos_media_item.dart';
import '../services/fnos_api_service.dart';
import 'fnos_server_controller.dart';

class FnosLibraryController extends GetxController {
  final String libraryId;
  final String libraryName;

  FnosLibraryController({
    required this.libraryId,
    required this.libraryName,
  });

  final FnosServerController serverController =
      Get.find<FnosServerController>();
  final FnosApiService api = FnosApiService();

  final RxList<FnosPlayListItem> items = <FnosPlayListItem>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxString error = ''.obs;
  final RxString searchKeyword = ''.obs;

  final RxBool isFolderMode = false.obs;

  /// 当前文件夹名称（用于 AppBar 标题）
  final RxString currentFolderName = ''.obs;

  /// 排序状态
  final RxString sortColumn = 'create_time'.obs;
  final RxString sortType = 'DESC'.obs;

  final ScrollController scrollController = ScrollController();

  static const int _pageSize = 40;
  int _currentPage = 1;
  String _currentFolderGuid = '';
  String _currentAncestorGuid = '';

  @override
  void onInit() {
    super.onInit();
    _currentAncestorGuid = libraryId;
    loadData(refresh: true);
    scrollController.addListener(() {
      if (scrollController.position.pixels >=
              scrollController.position.maxScrollExtent - 200 &&
          !isLoading.value &&
          hasMore.value) {
        loadData(refresh: false);
      }
    });
    debounce(
      searchKeyword,
      (_) => loadData(refresh: true),
      time: const Duration(milliseconds: 500),
    );
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  /// 进入子文件夹
  Future<void> enterFolder(String folderGuid, String folderName) async {
    isFolderMode.value = true;
    currentFolderName.value = folderName;
    _currentFolderGuid = folderGuid;
    _currentAncestorGuid = folderGuid;
    items.clear();
    _currentPage = 1;
    hasMore.value = true;
    await _loadFrom(folderGuid, refresh: true);
  }

  /// 退出到顶层
  Future<void> exitFolder() async {
    isFolderMode.value = false;
    currentFolderName.value = '';
    _currentFolderGuid = '';
    _currentAncestorGuid = libraryId;
    items.clear();
    _currentPage = 1;
    hasMore.value = true;
    await _loadFrom(libraryId, refresh: true);
  }

  Future<void> loadData({bool refresh = true}) async {
    await _loadFrom(_currentAncestorGuid, refresh: refresh);
  }

  Future<void> _loadFrom(
    String ancestorGuid, {
    bool refresh = true,
  }) async {
    final server = serverController.currentServer;
    if (server == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;
    if (isLoading.value) return;

    isLoading.value = true;
    try {
      if (refresh) {
        _currentPage = 1;
        hasMore.value = true;
      }

      final list = await api.getItemList(
        baseUrl: server.baseUrl,
        token: token,
        ancestorGuid: ancestorGuid,
        page: _currentPage,
        pageSize: _pageSize,
        sortColumn: sortColumn.value,
        sortType: sortType.value,
        keyword: searchKeyword.value.isNotEmpty ? searchKeyword.value : null,
      );

      if (refresh) {
        items.value = list;
      } else {
        items.addAll(list);
      }
      hasMore.value = list.length >= _pageSize;
      _currentPage += 1;
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshData() => loadData(refresh: true);

  /// 切换排序（字段 + 方向）
  Future<void> setSort(String column, String type) async {
    if (sortColumn.value == column && sortType.value == type) return;
    sortColumn.value = column;
    sortType.value = type;
    // 回到顶部，避免刷新后位置错乱
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    await loadData(refresh: true);
  }
}