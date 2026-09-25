import 'package:get/get.dart';

import '../models/lx_music_model.dart';
import '../models/lx_songlist_model.dart';
import '../services/lx_songlist_service.dart';
import '../utils/lx_logger.dart';

/// 洛雪音乐歌单控制器
class LxSonglistController extends GetxController {
  final LxSonglistService _service = LxSonglistService.instance;

  final RxList<LxSonglistInfo> recommendPlaylists = <LxSonglistInfo>[].obs;
  final RxBool isLoadingRecommend = false.obs;

  final RxString searchSource = 'tx'.obs;
  final RxList<LxSonglistInfo> searchResults = <LxSonglistInfo>[].obs;
  final RxBool isSearching = false.obs;
  final RxString searchError = ''.obs;

  @override
  void onInit() {
    super.onInit();
    // 延后到微任务，避免 initState/build 期间改 Rx
    Future.microtask(() => loadRecommend());
  }

  Future<void> loadRecommend() async {
    isLoadingRecommend.value = true;
    try {
      final list =
          await _service.getRecommendSonglists(page: 1, pageSize: 10);
      recommendPlaylists.value = list;
    } catch (e) {
      LxLogger.error('推荐歌单加载失败: $e');
    } finally {
      isLoadingRecommend.value = false;
    }
  }

  Future<void> refreshQQRecommend() async {
    isLoadingRecommend.value = true;
    try {
      final page = DateTime.now().millisecondsSinceEpoch % 6;
      final list = await _service.getQQRecommendSonglists(
        page: page,
        pageSize: 20,
      );
      if (list.isNotEmpty) {
        recommendPlaylists.value = list;
      }
    } catch (e) {
      LxLogger.error('QQ推荐歌单刷新失败: $e');
    } finally {
      isLoadingRecommend.value = false;
    }
  }

  Future<void> searchSonglists(String keyword) async {
    if (keyword.trim().isEmpty) return;
    isSearching.value = true;
    searchError.value = '';
    try {
      final list = await _service.searchSonglists(
        keyword,
        source: searchSource.value,
        page: 1,
        pageSize: 30,
      );
      searchResults.value = list;
    } catch (e) {
      searchResults.value = [];
      searchError.value = '歌单搜索失败，请检查网络';
      LxLogger.error('歌单搜索失败: $e');
    } finally {
      isSearching.value = false;
    }
  }

  void setSearchSource(String newSource) {
    if (searchSource.value == newSource) return;
    searchSource.value = newSource;
  }

  Future<({String name, String imgUrl, List<LxMusic> songs})?> loadDetail({
    required String songlistId,
    required String source,
  }) async {
    return _service.getSonglistDetail(
      songlistId: songlistId,
      source: source,
    );
  }

  Future<({String name, String imgUrl, List<LxMusic> songs})?> importFromShareLink(
      String input) async {
    final parsed = LxSonglistService.parseShareLink(input);
    if (parsed == null) {
      throw Exception('无法识别链接');
    }

    String source = parsed.source;
    String id = parsed.id;

    if (source == 'redirect') {
      final resolvedId = await LxSonglistService.resolveRedirectId(parsed.id);
      if (resolvedId == null) {
        throw Exception('链接解析失败');
      }
      id = resolvedId;
      source = input.contains('163.com') || input.contains('163cn.tv')
          ? 'wy'
          : 'tx';
    }

    final detail = source == 'wy'
        ? await _service.getWYPlaylistDetail(id)
        : await _service.getQQPlaylistDetail(id);

    return detail;
  }
}