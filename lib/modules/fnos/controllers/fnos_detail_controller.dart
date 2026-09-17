import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/fnos_media_item.dart';
import '../services/fnos_api_service.dart';
import 'fnos_server_controller.dart';

class FnosDetailController extends GetxController {
  final String itemGuid;

  final String? initialPoster;
  final String? initialBackdrops;
  final String? initialTitle;
  final String? initialTvTitle;
  final String? initialType;
  final String? initialOverview;

  FnosDetailController({
    required this.itemGuid,
    this.initialPoster,
    this.initialBackdrops,
    this.initialTitle,
    this.initialTvTitle,
    this.initialType,
    this.initialOverview,
  });

  final FnosServerController serverController =
      Get.find<FnosServerController>();
  final FnosApiService api = FnosApiService();

  final Rxn<FnosPlayInfoResponse> playInfo = Rxn();
  final Rxn<FnosItemInfo> item = Rxn();
  final RxList<FnosPlayListItem> seasons = <FnosPlayListItem>[].obs;
  final RxList<FnosPlayListItem> episodes = <FnosPlayListItem>[].obs;
  final RxInt selectedSeasonIndex = 0.obs;
  final RxList<Map<String, dynamic>> persons = <Map<String, dynamic>>[].obs;

  final RxBool isLoading = true.obs;
  final RxBool isLoadingEpisodes = false.obs;
  final RxString error = ''.obs;

  final RxInt episodeViewMode = 0.obs;
  final RxBool episodeSortAscending = true.obs;

  // ===== 收藏 / 已看状态（本地缓存，用于 UI 立即反馈）=====
  final RxBool isFavorite = false.obs;
  final RxBool isWatched = false.obs;
  final RxBool isFavoriteLoading = false.obs;
  final RxBool isWatchedLoading = false.obs;

  String get bestPoster {
    final p = item.value?.poster;
    if (p != null && p.isNotEmpty) return p;
    if (initialPoster != null && initialPoster!.isNotEmpty) {
      return initialPoster!;
    }
    return '';
  }

  String get bestBackdrops {
    final b = item.value?.backdrops;
    if (b != null && b.isNotEmpty) return b;
    if (initialBackdrops != null && initialBackdrops!.isNotEmpty) {
      return initialBackdrops!;
    }
    // 没 backdrops 就用 poster 兜底（fntv 同逻辑）
    return bestPoster;
  }

  String get bestTitle {
    final t = item.value?.title;
    if (t != null && t.isNotEmpty) return t;
    return initialTitle ?? '';
  }

  String get bestTvTitle {
    final t = item.value?.tvTitle;
    if (t != null && t.isNotEmpty) return t;
    return initialTvTitle ?? '';
  }

  // ============================================================
  // 类型判断（保留上次放宽逻辑，避免剧集区块消失）
  // ============================================================
  bool get isSeries {
    final t = playInfo.value?.type ?? initialType;
    if (t == 'TV') return true;
    final it = item.value;
    if ((it?.numberOfEpisodes ?? 0) > 0) return true;
    if ((it?.numberOfSeasons ?? 0) > 0) return true;
    return false;
  }

  bool get isEpisode => (playInfo.value?.type ?? initialType) == 'Episode';

  bool get showEpisodes =>
      isSeries || isEpisode || episodes.isNotEmpty || seasons.isNotEmpty;

  // ============================================================
  // 展示用 getter
  // ============================================================
  String get displayTitle {
    if (isEpisode) {
      final t = bestTvTitle;
      return t.isNotEmpty ? t : bestTitle;
    }
    final tv = bestTvTitle;
    if (tv.isNotEmpty) return tv;
    return bestTitle;
  }

  String? get displaySubtitle {
    if (isEpisode) {
      final t = bestTitle;
      if (t.isNotEmpty) return t;
    }
    final pt = item.value?.parentTitle;
    if (pt != null && pt.isNotEmpty) return pt;
    return null;
  }

  FnosPlayListItem? get continueEpisode {
    if (episodes.isEmpty) return null;
    for (final ep in episodes) {
      if (ep.ts > 0 && ep.watched == 0) return ep;
    }
    for (final ep in episodes) {
      if (ep.watched == 0) return ep;
    }
    return null;
  }

  int get watchedCount => episodes.where((e) => e.watched > 0).length;

  double get watchProgress {
    if (episodes.isEmpty) return 0;
    final total = episodes.length;
    final done = episodes.where((e) => e.watched > 0).length;
    final partial =
        episodes.where((e) => e.ts > 0 && e.watched == 0).length;
    return ((done + partial * 0.3) / total).clamp(0.0, 1.0);
  }

  List<FnosPlayListItem> get sortedEpisodes {
    final list = List<FnosPlayListItem>.from(episodes);
    list.sort((a, b) {
      final an = a.episodeNumber > 0 ? a.episodeNumber : 9999;
      final bn = b.episodeNumber > 0 ? b.episodeNumber : 9999;
      return episodeSortAscending.value
          ? an.compareTo(bn)
          : bn.compareTo(an);
    });
    return list;
  }

  String get playButtonLabel {
    final cont = continueEpisode;
    if (cont != null && cont.ts > 0) {
      final epNum = cont.episodeNumber > 0 ? cont.episodeNumber : 1;
      return '继续观看 · 第$epNum集';
    }
    if (showEpisodes && episodes.isNotEmpty) return '播放第1集';
    return '播放';
  }

  // String get playButtonLabel {
  //   // 有播放记录 → 继续播放
  //   final it = item.value;
  //   if (it != null && it.watched > 0) return '继续播放';
  //   final cont = continueEpisode;
  //   if (cont != null && cont.ts > 0) return '继续播放';
  //   // 无播放记录 → 立即播放
  //   return '立即播放';
  // }

  // ============================================================
  // 生命周期
  // ============================================================
  @override
  void onInit() {
    super.onInit();
    loadDetail();
  }

  // ============================================================
  // 加载详情 —— 与 fntv loadPlayInfo 对齐
  // ============================================================
  Future<void> loadDetail() async {
    final server = serverController.currentServer;
    if (server == null) {
      error.value = '服务器未配置';
      isLoading.value = false;
      return;
    }
    final token = serverController.getToken(server.id);
    if (token == null) {
      error.value = '未登录';
      isLoading.value = false;
      return;
    }

    isLoading.value = true;
    error.value = '';

    try {
      final info = await api.getPlayInfo(
        baseUrl: server.baseUrl,
        token: token,
        itemGuid: itemGuid,
      );
      playInfo.value = info;
      item.value = info.item;

      if (info.item != null) {
        isFavorite.value = info.item!.isFavorite > 0;
        isWatched.value = info.item!.watched > 0;
      }

      final type = info.type ?? initialType ?? '';
      debugPrint('FnosDetail type=$type guid=$itemGuid');
      debugPrint('FnosDetail play/info poster=${info.item?.poster}');

      // fntv 就是无论类型都调 _loadItemDetail
      _loadItemDetail(itemGuid);
      _loadPersons(itemGuid);

      // 剧集加载
      if (type == 'TV') {
        await _loadSeasonsByTvGuid(itemGuid);
      } else if (type == 'Episode') {
        final seasonGuid = info.parentGuid;
        if (seasonGuid != null && seasonGuid.isNotEmpty) {
          final tvGuid = await _resolveTvGuid(seasonGuid);
          if (tvGuid != null && tvGuid.isNotEmpty) {
            await _loadSeasonsByTvGuid(
              tvGuid,
              currentSeasonGuid: seasonGuid,
            );
          } else {
            await _loadEpisodesBySeasonGuid(seasonGuid);
          }
        }
      }
    } catch (e) {
      error.value = e.toString();
      debugPrint('loadDetail error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<String?> _resolveTvGuid(String seasonGuid) async {
    final server = serverController.currentServer;
    if (server == null) return null;
    final token = serverController.getToken(server.id);
    if (token == null) return null;
    try {
      final detail = await api.getItemDetail(
        baseUrl: server.baseUrl,
        token: token,
        guid: seasonGuid,
      );
      final data = detail['data'];
      if (data is Map) {
        final pg = data['parent_guid']?.toString();
        if (pg != null && pg.isNotEmpty) return pg;
      }
    } catch (e) {
      debugPrint('resolveTvGuid error: $e');
    }
    return null;
  }

  Future<void> _loadSeasonsByTvGuid(
    String tvGuid, {
    String? currentSeasonGuid,
  }) async {
    final server = serverController.currentServer;
    if (server == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;

    try {
      final list = await api.getSeasonList(
        baseUrl: server.baseUrl,
        token: token,
        tvGuid: tvGuid,
      );
      debugPrint('loadSeasons tvGuid=$tvGuid count=${list.length}');

      list.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      seasons.value = list;
      if (list.isEmpty) return;

      int idx = 0;
      if (currentSeasonGuid != null) {
        final found =
            list.indexWhere((s) => s.guid == currentSeasonGuid);
        if (found >= 0) idx = found;
      }
      selectedSeasonIndex.value = idx;
      await _loadEpisodesBySeasonGuid(list[idx].guid);
    } catch (e) {
      debugPrint('loadSeasons error: $e');
    }
  }

  Future<void> _loadEpisodesBySeasonGuid(String seasonGuid) async {
    final server = serverController.currentServer;
    if (server == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;

    isLoadingEpisodes.value = true;
    try {
      final list = await api.getEpisodeList(
        baseUrl: server.baseUrl,
        token: token,
        seasonGuid: seasonGuid,
      );
      debugPrint('loadEpisodes count=${list.length}');

      list.sort((a, b) {
        final an = a.episodeNumber > 0 ? a.episodeNumber : 9999;
        final bn = b.episodeNumber > 0 ? b.episodeNumber : 9999;
        return an.compareTo(bn);
      });
      episodes.value = list;
    } catch (e) {
      debugPrint('loadEpisodes error: $e');
    } finally {
      isLoadingEpisodes.value = false;
    }
  }

  Future<void> selectSeason(int index) async {
    if (index < 0 || index >= seasons.length) return;
    selectedSeasonIndex.value = index;
    await _loadEpisodesBySeasonGuid(seasons[index].guid);
  }

  void toggleEpisodeViewMode(int mode) => episodeViewMode.value = mode;
  void toggleSortOrder() =>
      episodeSortAscending.value = !episodeSortAscending.value;

  Future<void> _loadItemDetail(String guid) async {
    final server = serverController.currentServer;
    if (server == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;

    try {
      final resp = await api.getItemDetail(
        baseUrl: server.baseUrl,
        token: token,
        guid: guid,
      );
      final data = resp['data'];
      if (data is! Map) return;

      debugPrint('item/$guid poster=${data['poster']}');

      final info = item.value;
      if (info == null) return;

      // fntv 的合并策略：优先保留已有值（play/info 返回的），空则用 item 详情的
      final updated = FnosItemInfo(
        guid: info.guid,
        title: info.title,
        tvTitle: info.tvTitle,
        parentTitle: info.parentTitle,
        overview: info.overview ?? data['overview']?.toString(),
        poster: info.poster ?? data['poster']?.toString(),
        backdrops:
            info.backdrops ?? data['backdrops']?.toString(),
        logo: info.logo ??
            (data['logos'] ?? data['logo'])?.toString(),
        voteAverage: info.voteAverage,
        runtime: info.runtime,
        duration: info.duration,
        episodeNumber: info.episodeNumber,
        seasonNumber: info.seasonNumber,
        numberOfEpisodes: info.numberOfEpisodes,
        numberOfSeasons: info.numberOfSeasons,
        airDate: info.airDate,
        releaseDate: info.releaseDate,
        status: info.status,
        watched: info.watched,
        isFavorite: info.isFavorite,
      );
      item.value = updated;
    } catch (e) {
      debugPrint('loadItemDetail error: $e');
    }
  }

  Future<void> _loadPersons(String guid) async {
    final server = serverController.currentServer;
    if (server == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;
    try {
      final list = await api.getPersonList(
        baseUrl: server.baseUrl,
        token: token,
        itemGuid: guid,
      );
      persons.value = list;
    } catch (e) {
      debugPrint('loadPersons error: $e');
    }
  }
}