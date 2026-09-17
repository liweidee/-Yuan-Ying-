import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import '../controllers/emby_server_controller.dart';
import '../services/emby_api_service.dart';
import '../models/emby_media_item.dart';
import '../models/emby_server_model.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import '../controllers/emby_download_controller.dart';
import '../controllers/emby_favorite_controller.dart';

class EmbyDetailPage extends StatefulWidget {
  const EmbyDetailPage({super.key});

  @override
  State<EmbyDetailPage> createState() => _EmbyDetailPageState();
}

class _EmbyDetailPageState extends State<EmbyDetailPage> {
  late final String itemId;
  final EmbyServerController serverController =
      Get.find<EmbyServerController>();
  final EmbyApiService api = EmbyApiService();

  final Rx<EmbyMediaItem?> item = Rx(null);
  final RxList<EmbyMediaItem> seasons = <EmbyMediaItem>[].obs;
  final RxList<EmbyMediaItem> episodes = <EmbyMediaItem>[].obs;
  /// 专辑曲目
  final RxList<EmbyMediaItem> albumTracks = <EmbyMediaItem>[].obs;
  final RxInt selectedSeasonIndex = 0.obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingSeasons = false.obs;
  final RxString error = ''.obs;

  // 收藏状态
  final RxBool isFavorite = false.obs;
  final RxBool isFavoriteLoading = false.obs;

  // 从历史/继续观看进来时定位的初始集
  String? _initialEpisodeId;
  /// 定位到的 Episode/Audio（用于"继续播放 E05"按钮 + 播放指定集）
  final Rxn<EmbyMediaItem> initialEpisode = Rxn<EmbyMediaItem>();

  /// 专辑曲目的 URL 缓存（key: trackId, value: streamUrl）
  /// 避免 _playEpisode 里重复请求
  final Map<String, String> _trackUrlCache = {};

  @override
  void initState() {
    super.initState();
    itemId = Get.arguments?['itemId'] as String;
    // 从历史/继续观看进来时，携带初始集 ID
    _initialEpisodeId = Get.arguments?['initialEpisodeId'] as String?;
    _loadDetail();
  }

  /// 带半透明圆形背景的悬浮图标按钮
  ///
  /// 用 SizedBox 强制锁定尺寸，Material 承担圆形背景 + 水波纹。
  Widget _overlayCircleButton({
    required IconData icon,
    required VoidCallback? onPressed,
    Color iconColor = Colors.white,
    Color? backgroundColor,
    String? tooltip,
    double size = 44,
    double iconSize = 22,
  }) {
    final btn = SizedBox(
      width: size,
      height: size,
      child: Material(
        // ★ Material 直接承担半透明圆底
        color: backgroundColor ?? Colors.black.withOpacity(0.28),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Center(
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
        ),
      ),
    );

    if (tooltip == null || tooltip.isEmpty) return btn;
    return Tooltip(message: tooltip, child: btn);
  }

  // ============================================================
  // 计算详情页显示标题
  // 规则：剧集/电影/专辑/艺术家 → 自身名字
  //      Episode → 用 seriesName（Emby 的 SeriesName 字段）
  //      Audio   → 用 albumName（Emby 的 Album 字段）
  // 保证播放页两处标题永远显示"大标题"，不显示具体集数
  // ============================================================
  String _effectiveVodName(EmbyMediaItem item) {
    switch (item.type) {
      case 'Series':
      case 'Movie':
      case 'MusicAlbum':
      case 'MusicArtist':
        return item.name;
      case 'Episode':
        return (item.seriesName?.isNotEmpty == true)
            ? item.seriesName!
            : item.name;
      case 'Audio':
        return (item.albumName?.isNotEmpty == true)
            ? item.albumName!
            : item.name;
      default:
        // 兜底：优先 seriesName，其次 albumName，最后 name
        if (item.seriesName?.isNotEmpty == true) return item.seriesName!;
        if (item.albumName?.isNotEmpty == true) return item.albumName!;
        return item.name;
    }
  }

  // ============================================================
  // 统一流 URL 构造
  // ============================================================
  String _buildStreamUrl({
    required String baseUrl,
    required String itemId,
    required String sourceId,
    required String token,
    required String container,
    required bool supportsDirectPlay,
    required bool isAudio,
  }) {
    if (isAudio) {
      if (supportsDirectPlay) {
        return EmbyApiService.audioDirectStreamUrl(
          baseUrl, itemId, sourceId, token, container,
        );
      } else {
        return EmbyApiService.audioUniversalStreamUrl(
          baseUrl, itemId, sourceId, token, container: container,
        );
      }
    }
    if (supportsDirectPlay) {
      return EmbyApiService.directStreamUrl(
        baseUrl, itemId, sourceId, token, container,
      );
    } else {
      return EmbyApiService.hlsStreamUrl(
        baseUrl, itemId, sourceId, token,
      );
    }
  }

  // ============================================================
  // 获取单个 item 的流 URL（带缓存）
  // ============================================================
  Future<String?> _resolveStreamUrl({
    required EmbyServer server,
    required String token,
    required String itemId,
    required bool isAudio,
  }) async {
    // 缓存命中
    if (_trackUrlCache.containsKey(itemId)) {
      return _trackUrlCache[itemId];
    }
    try {
      final info = await api.getPlaybackInfo(
        userId: server.userId!,
        token: token,
        baseUrl: server.baseUrl,
        itemId: itemId,
      );
      final sources = info['MediaSources'] as List?;
      if (sources == null || sources.isEmpty) return null;

      final firstSource = sources.first as Map<String, dynamic>;
      final sourceId = firstSource['Id'] as String;
      final container =
          firstSource['Container'] as String? ?? (isAudio ? 'mp3' : 'mp4');
      final supportsDirectPlay =
          firstSource['SupportsDirectPlay'] as bool? ?? false;

      final url = _buildStreamUrl(
        baseUrl: server.baseUrl,
        itemId: itemId,
        sourceId: sourceId,
        token: token,
        container: container,
        supportsDirectPlay: supportsDirectPlay,
        isAudio: isAudio,
      );
      _trackUrlCache[itemId] = url;
      return url;
    } catch (e) {
      debugPrint('获取 item $itemId 流 URL 失败: $e');
      return null;
    }
  }

  // ============================================================
  // 加载详情
  // ============================================================
  Future<void> _loadDetail() async {
    final server = serverController.currentServer;
    if (server == null || server.userId == null) {
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
    try {
      final detail =
          await api.getItemInfo(server.userId!, token, server.baseUrl, itemId);
      item.value = detail;

      // 同步收藏状态
      isFavorite.value = detail.userData?.isFavorite ?? false;

      // 剧集：加载季/集
      if (detail.isSeries) {
        await _loadSeasons(server, token);
      }

      // 专辑：加载曲目
      if (detail.isMusicAlbum) {
        await _loadAlbumTracks(server, token);
      }

      // 定位初始集（若从历史/继续观看进入）
      _resolveInitialEpisode();
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loadSeasons(EmbyServer server, String token) async {
    isLoadingSeasons.value = true;
    try {
      final seasonsList = await api.getSeasons(
        server.userId!, token, server.baseUrl, itemId,
      );
      seasons.value = seasonsList;
      if (seasonsList.isNotEmpty) {
        await _loadEpisodes(server, token, seasonsList.first.id);
      }
    } catch (e) {
      debugPrint('加载季列表失败: $e');
    } finally {
      isLoadingSeasons.value = false;
    }
  }

  Future<void> _loadEpisodes(
      EmbyServer server, String token, String seasonId) async {
    try {
      final episodesList = await api.getEpisodes(
        server.userId!, token, server.baseUrl, itemId, seasonId,
      );
      episodes.value = episodesList;
    } catch (e) {
      debugPrint('加载剧集列表失败: $e');
    }
  }

  /// 加载专辑曲目
  Future<void> _loadAlbumTracks(EmbyServer server, String token) async {
    try {
      final tracks = await api.getAlbumTracks(
        server.userId!, token, server.baseUrl, itemId,
      );
      albumTracks.value = tracks;
      debugPrint('专辑 ${item.value?.name} 加载了 ${tracks.length} 首曲目');
    } catch (e) {
      debugPrint('加载专辑曲目失败: $e');
    }
  }

  /// 根据 `_initialEpisodeId` 在已加载的集/曲列表中定位到目标条目
  ///
  /// 匹配源：
  /// - 剧集：从 `episodes` 里找（首次进入默认加载第一季，可能不包含目标集）
  /// - 专辑：从 `albumTracks` 里找
  ///
  /// 若目标集不在已加载列表中（例如目标集在第二季），会加载对应的季。
  Future<void> _resolveInitialEpisode() async {
    final eid = _initialEpisodeId;
    if (eid == null || eid.isEmpty) return;

    // ---- 专辑曲目直接查 ----
    for (final t in albumTracks) {
      if (t.id == eid) {
        initialEpisode.value = t;
        return;
      }
    }

    // ---- 剧集：先在当前加载的集里找 ----
    for (final ep in episodes) {
      if (ep.id == eid) {
        initialEpisode.value = ep;
        return;
      }
    }

    // ---- 未找到：遍历所有季查（懒加载）----
    final detail = item.value;
    if (detail == null || !detail.isSeries) return;
    final server = serverController.currentServer;
    if (server == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;

    for (int i = 0; i < seasons.length; i++) {
      final season = seasons[i];
      try {
        final eps = await api.getEpisodes(
          server.userId!, token, server.baseUrl, detail.id, season.id,
        );
        for (final ep in eps) {
          if (ep.id == eid) {
            // 切换当前显示的季到该集所属季
            selectedSeasonIndex.value = i;
            episodes.value = eps;
            initialEpisode.value = ep;
            return;
          }
        }
      } catch (_) {}
    }
  }

  // ============================================================
  // 播放（电影/剧集/专辑入口）
  // ============================================================
  Future<void> _play() async {
    final server = serverController.currentServer;
    if (server == null || server.userId == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;

    final detail = item.value!;

    // ===== 专辑：从第一首开始播放整张专辑 =====
    if (detail.isMusicAlbum) {
      if (albumTracks.isEmpty) {
        SmartDialog.showToast('专辑暂无曲目');
        return;
      }
      await _playAlbum(
        server: server,
        token: token,
        album: detail,
        tracks: albumTracks.toList(),
        startTrack: albumTracks.first,
      );
      return;
    }

    // ===== 电影 / 剧集：走原有逻辑 =====
    SmartDialog.showLoading(msg: '获取播放信息...');
    try {
      final baseUrl = server.baseUrl;
      final posterUrl =
          EmbyApiService.primaryImage(baseUrl, detail.id, maxWidth: 400);

      List<PlaySource> playSources = [];
      String defaultStreamUrl = '';

      // 剧集：加载完整剧集列表
      if (detail.isSeries) {
        try {
          final seasonsList = await api.getSeasons(
            server.userId!, token, baseUrl, detail.id,
          );
          if (seasonsList.isNotEmpty) {
            final sourcesList = <PlaySource>[];
            for (final season in seasonsList) {
              final episodesList = await api.getEpisodes(
                server.userId!, token, baseUrl, detail.id, season.id,
              );
              if (episodesList.isEmpty) continue;

              final episodeEntries = <Episode>[];
              for (final e in episodesList) {
                final url = await _resolveStreamUrl(
                  server: server,
                  token: token,
                  itemId: e.id,
                  isAudio: e.isAudio,
                );
                if (url == null) continue;
                episodeEntries.add(Episode(
                  name:
                      'E${e.indexNumber?.toString().padLeft(2, '0') ?? '?'} ${e.name}',
                  url: url,
                ));
              }

              if (episodeEntries.isNotEmpty) {
                sourcesList.add(PlaySource(
                  name: season.name,
                  episodes: episodeEntries,
                ));
              }
            }
            if (sourcesList.isNotEmpty) {
              playSources = sourcesList;
              final firstEpisode = await api.getEpisodes(
                server.userId!, token, baseUrl, detail.id,
                seasonsList.first.id,
              );
              if (firstEpisode.isNotEmpty) {
                defaultStreamUrl = await _resolveStreamUrl(
                  server: server,
                  token: token,
                  itemId: firstEpisode.first.id,
                  isAudio: firstEpisode.first.isAudio,
                ) ?? '';
              }
            }
          }
        } catch (e) {
          debugPrint('加载剧集列表失败: $e');
        }
      }

      // 电影或剧集加载失败：当前 item
      if (defaultStreamUrl.isEmpty) {
        defaultStreamUrl = await _resolveStreamUrl(
          server: server,
          token: token,
          itemId: detail.id,
          isAudio: detail.isAudio,
        ) ?? '';
      }

      if (defaultStreamUrl.isEmpty) {
        SmartDialog.dismiss();
        SmartDialog.showToast('无法获取播放地址');
        return;
      }

      SmartDialog.dismiss();

      final videoDetail = VideoDetail(
        vodId: detail.id,
        vodName: _effectiveVodName(detail),
        vodPic: posterUrl,
        vodContent: detail.overview ?? '',
        vodYear: detail.productionYear?.toString() ?? '',
        vodActor: detail.people
            .where((p) => p.type == 'Actor')
            .map((p) => p.name)
            .join(','),
        vodDirector: detail.people
            .where((p) => p.type == 'Director')
            .map((p) => p.name)
            .join(','),
        vodRemarks: detail.genres.join(' · '),
        typeName: detail.type,
        playSources: playSources.isNotEmpty
            ? playSources
            : [
                PlaySource(
                  name: 'Emby',
                  episodes: [
                    Episode(name: detail.name, url: defaultStreamUrl),
                  ],
                ),
              ],
      );

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'isPush': true,
          'directUrl': defaultStreamUrl,
          'directTitle': detail.name,
          'videoDetail': videoDetail,
          'sourceName': server.name,
          'vodPic': posterUrl,
          'vodContent': detail.overview ?? '',
          'vodYear': detail.productionYear?.toString() ?? '',
          'vodActor': detail.people
              .where((p) => p.type == 'Actor')
              .map((p) => p.name)
              .join(','),
          'vodRemarks': detail.genres.join(' · '),
          'isSeries': detail.isSeries,
          'isDirectPushMode': true,
        },
      );
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('播放失败: $e');
    }
  }

  // ============================================================
  // 专辑播放核心：完整拼接所有曲目
  // ============================================================
  /// [startTrack] 指定从哪首开始播放（用于点单曲时定位起始位置）
  Future<void> _playAlbum({
    required EmbyServer server,
    required String token,
    required EmbyMediaItem album,
    required List<EmbyMediaItem> tracks,
    required EmbyMediaItem startTrack,
  }) async {
    SmartDialog.showLoading(msg: '准备播放列表...');
    try {
      final baseUrl = server.baseUrl;
      final posterUrl =
          EmbyApiService.primaryImage(baseUrl, album.id, maxWidth: 400);

      // ===== 关键：完整拼接所有曲目的 Episode 列表 =====
      final episodes = <Episode>[];
      String? startStreamUrl;

      for (final track in tracks) {
        final url = await _resolveStreamUrl(
          server: server,
          token: token,
          itemId: track.id,
          isAudio: true,
        );
        if (url == null) continue;

        episodes.add(Episode(name: track.name, url: url));

        // 记录起始曲目的 URL
        if (track.id == startTrack.id) {
          startStreamUrl = url;
        }
      }

      SmartDialog.dismiss();

      if (episodes.isEmpty) {
        SmartDialog.showToast('无法获取任何曲目的播放地址');
        return;
      }

      // 起始曲目 URL 兜底：若未命中（ID 不一致），从第一首开始
      startStreamUrl ??= episodes.first.url;

      // ===== 构造 VideoDetail（参考剧集的构造方式）=====
      final videoDetail = VideoDetail(
        vodId: album.id,
        vodName: album.name,
        vodPic: posterUrl,
        vodContent: album.overview ?? '',
        vodYear: album.productionYear?.toString() ?? '',
        vodActor: album.artists.join(','),
        vodDirector: album.albumArtist ?? '',
        vodRemarks: '专辑 · ${episodes.length} 首',
        typeName: 'MusicAlbum',
        playSources: [
          PlaySource(name: album.name, episodes: episodes),
        ],
      );

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'isPush': true,
          'directUrl': startStreamUrl,
          'directTitle': startTrack.name,
          'videoDetail': videoDetail,
          'sourceName': server.name,
          'vodPic': posterUrl,
          'vodContent': album.overview ?? '',
          'vodYear': album.productionYear?.toString() ?? '',
          'vodActor': album.artists.join(','),
          'vodDirector': album.albumArtist ?? '',
          'vodRemarks': '专辑 · ${episodes.length} 首',
          'isSeries': false,
          'isDirectPushMode': true,
        },
      );
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('播放失败: $e');
    }
  }

  // ============================================================
  // 播放单集/单曲
  // ============================================================
  Future<void> _playEpisode(EmbyMediaItem episode) async {
    final server = serverController.currentServer;
    if (server == null || server.userId == null) return;
    final token = serverController.getToken(server.id);
    if (token == null) return;

    // ===== 关键分支：当前上下文是专辑 → 完整拼接所有曲目 =====
    final currentDetail = item.value;
    if (currentDetail != null &&
        currentDetail.isMusicAlbum &&
        albumTracks.isNotEmpty) {
      await _playAlbum(
        server: server,
        token: token,
        album: currentDetail,
        tracks: albumTracks.toList(),
        startTrack: episode,
      );
      return;
    }

    // ===== 剧集场景：单集播放 =====
    SmartDialog.showLoading(msg: '获取播放信息...');
    try {
      final url = await _resolveStreamUrl(
        server: server,
        token: token,
        itemId: episode.id,
        isAudio: episode.isAudio,
      );

      SmartDialog.dismiss();

      if (url == null) {
        SmartDialog.showToast('无法获取播放地址');
        return;
      }

      // ===== 单集播放：始终构造 videoDetail，让播放页标题显示"剧集/专辑"名 =====
      // 覆盖三种场景：
      //   1. currentDetail 是 Series（从剧集详情点某集）→ vodName = 剧集名
      //   2. currentDetail 是 Episode（从 Home 直接进某集）→ vodName = seriesName
      //   3. currentDetail 是 Movie（从 Home 进电影）→ vodName = 电影名
      VideoDetail? videoDetail;
      if (currentDetail != null) {
        // ---- 播放列表：优先用已加载的 episodes ----
        final allEpisodes = <Episode>[];
        if (episodes.isNotEmpty) {
          for (final ep in episodes) {
            final epUrl = await _resolveStreamUrl(
              server: server,
              token: token,
              itemId: ep.id,
              isAudio: ep.isAudio,
            );
            if (epUrl == null) continue;
            allEpisodes.add(Episode(
              name:
                  'E${ep.indexNumber?.toString().padLeft(2, '0') ?? '?'} ${ep.name}',
              url: epUrl,
            ));
          }
        }
        // ---- 兜底：episodes 为空时（如从 Home 直接进某集），至少放当前这一集 ----
        if (allEpisodes.isEmpty) {
          allEpisodes.add(Episode(name: episode.name, url: url));
        }

        // ---- 播放源名称：剧集用当前选中季名，其余用类型名 ----
        final sourceName = (currentDetail.isSeries && seasons.isNotEmpty &&
                selectedSeasonIndex.value < seasons.length)
            ? seasons[selectedSeasonIndex.value].name
            : (currentDetail.isSeries ? '剧集' : currentDetail.type);

        videoDetail = VideoDetail(
          vodId: currentDetail.id,
          vodName: _effectiveVodName(currentDetail), // ← 关键：永远是大标题
          vodPic: EmbyApiService.primaryImage(
              server.baseUrl, currentDetail.id, maxWidth: 400),
          vodContent: currentDetail.overview ?? '',
          vodYear: currentDetail.productionYear?.toString() ?? '',
          vodRemarks: currentDetail.genres.join(' · '),
          typeName: currentDetail.type,
          playSources: [
            PlaySource(name: sourceName, episodes: allEpisodes),
          ],
        );
      }

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'isPush': true,
          'directUrl': url,
          'directTitle': episode.name,
          if (videoDetail != null) 'videoDetail': videoDetail,
          if (videoDetail != null) 'sourceName': server.name,
          if (videoDetail != null)
            'vodPic': EmbyApiService.primaryImage(
                server.baseUrl, currentDetail!.id, maxWidth: 400),
          'isDirectPushMode': true,
        },
      );
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('播放失败: $e');
    }
  }

  // ============================================================
  // 下载入口：按详情类型分发
  //   - Movie / Episode / Audio → 直接下载
  //   - Series → 弹窗让用户选「全部」或「某一季」
  //   - MusicAlbum → 弹窗让用户选「全部」或「某一首」
  // ============================================================
  Future<void> _download() async {
    final server = serverController.currentServer;
    if (server == null) {
      SmartDialog.showToast('未连接服务器');
      return;
    }
    final token = serverController.getToken(server.id);
    if (token == null) {
      SmartDialog.showToast('请先登录');
      return;
    }
    final detail = item.value!;

    if (detail.isSeries) {
      await _downloadSeries(detail, server, token);
    } else if (detail.isMusicAlbum) {
      await _downloadAlbum(detail, server, token);
    } else {
      await _downloadSingle(detail, server, token);
    }
  }

  /// 单集/单曲/电影：直接下载（保持原逻辑）
  Future<void> _downloadSingle(
    EmbyMediaItem target,
    EmbyServer server,
    String token,
  ) async {
    if (!Get.isRegistered<EmbyDownloadController>()) {
      Get.put(EmbyDownloadController());
    }
    final downloadCtrl = Get.find<EmbyDownloadController>();
    await downloadCtrl.addDownload(
      itemId: target.id,
      name: target.name,
      imageTag: null,
      serverId: server.id,
      baseUrl: server.baseUrl,
      token: token,
    );
    SmartDialog.showToast('已加入下载队列');
  }

  /// 剧集：弹窗让用户逐集勾选下载
  Future<void> _downloadSeries(
    EmbyMediaItem series,
    EmbyServer server,
    String token,
  ) async {
    // ---- 1. 确保季列表已加载 ----
    List<EmbyMediaItem> seasonsList = seasons.toList();
    if (seasonsList.isEmpty) {
      SmartDialog.showLoading(msg: '正在加载季列表...');
      try {
        seasonsList = await api.getSeasons(
          server.userId!, token, server.baseUrl, series.id,
        );
      } catch (e) {
        SmartDialog.dismiss();
        SmartDialog.showToast('加载季列表失败: $e');
        return;
      }
      SmartDialog.dismiss();
    }
    if (seasonsList.isEmpty) {
      SmartDialog.showToast('此剧集无季信息');
      return;
    }

    if (!mounted) return;

    // ---- 2. 弹窗让用户勾选具体的集 ----
    final selected = await showModalBottomSheet<List<EmbyMediaItem>>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      isScrollControlled: true,
      builder: (_) => _SeriesDownloadSheet(
        seasons: seasonsList,
        loadEpisodes: (seasonId) => api.getEpisodes(
          server.userId!, token, server.baseUrl, series.id, seasonId,
        ),
      ),
    );

    if (selected == null || selected.isEmpty) return;
    if (!mounted) return;

    // ---- 3. 批量加入下载队列 ----
    await _enqueueBatch(selected, server, token, '集');
  }

  /// 专辑：弹窗让用户选择曲目
  Future<void> _downloadAlbum(
    EmbyMediaItem album,
    EmbyServer server,
    String token,
  ) async {
    // ---- 1. 确保曲目列表已加载 ----
    List<EmbyMediaItem> tracks = albumTracks.toList();
    if (tracks.isEmpty) {
      SmartDialog.showLoading(msg: '正在加载曲目列表...');
      try {
        tracks = await api.getAlbumTracks(
          server.userId!, token, server.baseUrl, album.id,
        );
      } catch (e) {
        SmartDialog.dismiss();
        SmartDialog.showToast('加载曲目列表失败: $e');
        return;
      }
      SmartDialog.dismiss();
    }
    if (tracks.isEmpty) {
      SmartDialog.showToast('此专辑无曲目');
      return;
    }

    if (!mounted) return;

    // ---- 2. 弹窗选择 ----
    // 返回类型：null=取消；_albumDownloadAllSentinel=全部；EmbyMediaItem=单曲
    final choice = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    '选择下载曲目',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.download, color: cs.primary),
                  title: const Text('下载全部'),
                  subtitle: Text('共 ${tracks.length} 首'),
                  onTap: () => Navigator.pop(ctx, _albumDownloadAllSentinel),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tracks.length,
                    itemBuilder: (ctx2, i) {
                      final t = tracks[i];
                      return ListTile(
                        leading: Icon(
                          Icons.music_note,
                          color: cs.secondary,
                        ),
                        title: Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: t.artists.isNotEmpty
                            ? Text(t.artists.join(' / '))
                            : null,
                        onTap: () => Navigator.pop(ctx, t),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == null || !mounted) return;

    // ---- 3. 确定要下载的曲目 ----
    final List<EmbyMediaItem> toDownload =
        identical(choice, _albumDownloadAllSentinel)
            ? tracks
            : (choice is EmbyMediaItem ? [choice] : <EmbyMediaItem>[]);

    if (toDownload.isEmpty) return;

    // ---- 4. 批量加入下载队列 ----
    await _enqueueBatch(toDownload, server, token, '首');
  }

  /// 批量加入下载队列的通用实现
  /// [unit] 用于提示文案（"集" / "首"）
  Future<void> _enqueueBatch(
    List<EmbyMediaItem> items,
    EmbyServer server,
    String token,
    String unit,
  ) async {
    if (!Get.isRegistered<EmbyDownloadController>()) {
      Get.put(EmbyDownloadController());
    }
    final downloadCtrl = Get.find<EmbyDownloadController>();

    int added = 0;
    for (final item in items) {
      // 已在队列中的跳过
      if (downloadCtrl.items
          .any((i) => i.id == item.id && i.serverId == server.id)) {
        continue;
      }
      // 并发启动下载（每个任务独立）
      unawaited(downloadCtrl.addDownload(
        itemId: item.id,
        name: item.name,
        imageTag: null,
        serverId: server.id,
        baseUrl: server.baseUrl,
        token: token,
      ));
      added++;
    }

    if (added > 0) {
      SmartDialog.showToast('已加入 $added $unit下载队列');
    } else {
      SmartDialog.showToast('所选内容已全部在下载列表中');
    }
  }

  /// 单集/单曲快捷下载（从列表行点下载图标）
  Future<void> _downloadEpisodeQuick(EmbyMediaItem episode) async {
    final server = serverController.currentServer;
    if (server == null) {
      SmartDialog.showToast('未连接服务器');
      return;
    }
    final token = serverController.getToken(server.id);
    if (token == null) {
      SmartDialog.showToast('请先登录');
      return;
    }
    await _downloadSingle(episode, server, token);
  }

  // ============================================================
  // 收藏 / 取消收藏
  // ============================================================
  Future<void> _toggleFavorite() async {
    final server = serverController.currentServer;
    if (server == null || server.userId == null) {
      SmartDialog.showToast('服务器未配置');
      return;
    }
    final token = serverController.getToken(server.id);
    if (token == null) {
      SmartDialog.showToast('请先登录');
      return;
    }
    final detail = item.value;
    if (detail == null) return;

    isFavoriteLoading.value = true;
    try {
      if (isFavorite.value) {
        await api.unmarkFavorite(
          userId: server.userId!,
          token: token,
          baseUrl: server.baseUrl,
          itemId: detail.id,
        );
        isFavorite.value = false;
        SmartDialog.showToast('已取消收藏');
      } else {
        await api.markFavorite(
          userId: server.userId!,
          token: token,
          baseUrl: server.baseUrl,
          itemId: detail.id,
        );
        isFavorite.value = true;
        SmartDialog.showToast('已收藏');
      }

      // ★ 通知收藏页刷新（如果已注册）
      if (Get.isRegistered<EmbyFavoriteController>()) {
        Get.find<EmbyFavoriteController>().refreshData();
      }
    } catch (e) {
      SmartDialog.showToast('操作失败: $e');
    } finally {
      isFavoriteLoading.value = false;
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Obx(() {
        if (isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (error.isNotEmpty) {
          return Center(
            child: Text(error.value,
                style: TextStyle(color: colorScheme.error)),
          );
        }
        final detail = item.value!;
        final server = serverController.currentServer!;
        final backdropUrl = EmbyApiService.backdropImage(
            server.baseUrl, detail.id,
            maxWidth: 1280);
        final posterUrl =
            EmbyApiService.primaryImage(server.baseUrl, detail.id,
                maxWidth: 400);

        return CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 250,
              pinned: true,
              backgroundColor: colorScheme.surface,
              leadingWidth: 56,
              leading: SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: _overlayCircleButton(
                    icon: Icons.arrow_back,
                    onPressed: () => Get.back(),
                    tooltip: '返回',
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child: Obx(() => _overlayCircleButton(
                          icon: isFavorite.value
                              ? Icons.favorite
                              : Icons.favorite_border,
                          iconColor: isFavorite.value
                              ? colorScheme.primary
                              : Colors.white,
                          onPressed: isFavoriteLoading.value
                              ? null
                              : _toggleFavorite,
                          tooltip:
                              isFavorite.value ? '取消收藏' : '收藏',
                        )),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      backdropUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: colorScheme.surfaceVariant,
                        child: Icon(Icons.movie,
                            size: 64, color: colorScheme.outline),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            colorScheme.surface.withOpacity(0.8),
                            colorScheme.surface,
                          ],
                          stops: const [0.0, 0.5, 0.8, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.name,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        if (detail.productionYear != null)
                          _buildMetaChip('${detail.productionYear}', colorScheme),
                        if (detail.communityRating != null)
                          _buildMetaChip(
                              '⭐ ${detail.communityRating!.toStringAsFixed(1)}',
                              colorScheme),
                        if (detail.runtimeTicks != null)
                          _buildMetaChip(
                              _formatDuration(detail.runtimeTicks!), colorScheme),
                        // 专辑显示艺术家
                        if (detail.isMusicAlbum && detail.artists.isNotEmpty)
                          _buildMetaChip(
                              detail.artists.join(' / '), colorScheme),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (detail.genres.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: detail.genres
                            .take(5)
                            .map((g) => _buildGenreChip(g, colorScheme))
                            .toList(),
                      ),
                    const SizedBox(height: 16),
                    Obx(() {
                      final initEp = initialEpisode.value;
                      // 主按钮文案：
                      // - 有定位集 → "继续播放 E05"
                      // - 专辑 → "播放专辑"
                      // - 其他 → "立即播放"
                      String primaryLabel;
                      if (initEp != null) {
                        final epLabel = initEp.indexNumber != null
                            ? 'E${initEp.indexNumber!.toString().padLeft(2, '0')}'
                            : (initEp.name.isNotEmpty
                                ? initEp.name
                                : '上一集');
                        primaryLabel = '继续播放 $epLabel';
                      } else if (detail.isMusicAlbum) {
                        primaryLabel = '播放专辑';
                      } else {
                        primaryLabel = '立即播放';
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              // ★ 有定位集 → 播该集；否则走原逻辑
                              onPressed: initEp != null
                                  ? () => _playEpisode(initEp)
                                  : _play,
                              icon: const Icon(Icons.play_arrow),
                              label: Text(primaryLabel),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _download(),
                              icon: const Icon(Icons.download),
                              label: const Text('下载'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                                side:
                                    BorderSide(color: colorScheme.primary),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 20),
                    if (detail.overview != null &&
                        detail.overview!.isNotEmpty) ...[
                      Text(
                        '简介',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detail.overview!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // 剧集：季/集列表
                    if (detail.isSeries) ...[
                      _buildSeasonsSection(
                        colorScheme: colorScheme,
                        server: server,
                        token: serverController.getToken(server.id)!,
                      ),
                      const SizedBox(height: 24),
                    ],

                    // 专辑：曲目列表
                    if (detail.isMusicAlbum) ...[
                      _buildAlbumTracksSection(
                        colorScheme: colorScheme,
                        server: server,
                      ),
                      const SizedBox(height: 24),
                    ],

                    if (detail.people.isNotEmpty) ...[
                      Text(
                        '演员阵容',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildCastSection(
                          detail.people, server.baseUrl, colorScheme),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  // ============================================================
  // 专辑曲目区块
  // ============================================================
  Widget _buildAlbumTracksSection({
    required ColorScheme colorScheme,
    required EmbyServer server,
  }) {
    return Obx(() {
      if (albumTracks.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '暂无曲目',
            style: TextStyle(color: colorScheme.outline),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '曲目列表',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${albumTracks.length} 首',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...albumTracks.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final track = entry.value;
            return _buildTrackItem(
              track: track,
              baseUrl: server.baseUrl,
              colorScheme: colorScheme,
              index: index,
            );
          }),
        ],
      );
    });
  }

  /// 曲目条目：点击时完整拼接所有曲目到播放列表，从当前曲目开始播
  /// 右侧有小下载按钮可快捷下载单曲
  Widget _buildTrackItem({
    required EmbyMediaItem track,
    required String baseUrl,
    required ColorScheme colorScheme,
    required int index,
  }) {
    return GestureDetector(
      onTap: () => _playEpisode(track), // 内部会检测专辑上下文
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.surfaceVariant,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '$index',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (track.artists.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        track.artists.join(' / '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (track.runtimeTicks != null)
              Text(
                _formatDuration(track.runtimeTicks!),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
            const SizedBox(width: 8),
            // ★ 单曲快捷下载
            IconButton(
              icon: Icon(Icons.download_outlined,
                  color: colorScheme.outline, size: 18),
              tooltip: '下载此曲',
              onPressed: () => _downloadEpisodeQuick(track),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            Icon(Icons.play_arrow, color: colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 剧集季/集区块
  // ============================================================
  Widget _buildSeasonsSection({
    required ColorScheme colorScheme,
    required EmbyServer server,
    required String token,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '剧集列表',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        if (seasons.isNotEmpty)
          SizedBox(
            height: 36,
            child: Obx(() => ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: seasons.length,
                  itemBuilder: (ctx, i) {
                    final season = seasons[i];
                    final isSelected = i == selectedSeasonIndex.value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(season.name),
                        selected: isSelected,
                        selectedColor: colorScheme.primary,
                        backgroundColor: colorScheme.surfaceVariant,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                        onSelected: (_) {
                          selectedSeasonIndex.value = i;
                          _loadEpisodes(server, token, season.id);
                        },
                      ),
                    );
                  },
                )),
          ),
        const SizedBox(height: 8),
        Obx(() {
          if (isLoadingSeasons.value) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (episodes.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '暂无剧集',
                style: TextStyle(color: colorScheme.outline),
              ),
            );
          }
          return Column(
            children: episodes
                .map((ep) =>
                    _buildEpisodeItem(ep, server.baseUrl, colorScheme))
                .toList(),
          );
        }),
      ],
    );
  }

  Widget _buildEpisodeItem(
      EmbyMediaItem episode, String baseUrl, ColorScheme colorScheme) {
    final thumbUrl =
        EmbyApiService.primaryImage(baseUrl, episode.id, maxWidth: 300);
    final progress = episode.userData?.playedPercentage != null
        ? episode.userData!.playedPercentage! / 100
        : null;
    // 是否是"从历史定位进来"的那一集
    final isInitial = initialEpisode.value?.id == episode.id;

    return GestureDetector(
      onTap: () => _playEpisode(episode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          // 高亮背景
          color: isInitial
              ? colorScheme.primary.withOpacity(0.08)
              : null,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.surfaceVariant,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 120,
                height: 68,
                child: Stack(
                  children: [
                    Image.network(
                      thumbUrl,
                      fit: BoxFit.cover,
                      width: 120,
                      height: 68,
                      errorBuilder: (_, __, ___) => Container(
                        color: colorScheme.surfaceVariant,
                        child: Icon(Icons.play_circle_outline,
                            color: colorScheme.outline),
                      ),
                    ),
                    if (progress != null)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 2,
                          color: colorScheme.primary,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'E${episode.indexNumber?.toString().padLeft(2, '0') ?? '?'}  ${episode.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (episode.overview != null)
                    Text(
                      episode.overview!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            // ★ 单集快捷下载
            IconButton(
              icon: Icon(Icons.download_outlined,
                  color: colorScheme.outline, size: 20),
              tooltip: '下载此集',
              onPressed: () => _downloadEpisodeQuick(episode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCastSection(
      List<EmbyPerson> people, String baseUrl, ColorScheme colorScheme) {
    final actors = people.where((p) => p.type == 'Actor').take(12).toList();
    if (actors.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: actors.length,
        itemBuilder: (ctx, i) {
          final person = actors[i];
          return SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: ClipOval(
                      // ★ 只在演员有头像时请求图片；
                      //   没有 PrimaryImageTag 就直接显示默认图标
                      child: person.hasImage
                          ? Image.network(
                              EmbyApiService.primaryImage(
                                baseUrl,
                                person.id,
                                maxWidth: 160,
                                tag: person.primaryImageTag,
                              ),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              // ★ errorBuilder 兜底（网络失败/超时）
                              errorBuilder: (_, __, ___) =>
                                  _buildAvatarFallback(colorScheme),
                              loadingBuilder: (_, child, progress) =>
                                  progress == null
                                      ? child
                                      : _buildAvatarFallback(colorScheme),
                            )
                          : _buildAvatarFallback(colorScheme),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    person.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 演员头像的默认占位（无头像 / 加载中 / 加载失败都显示）
  Widget _buildAvatarFallback(ColorScheme colorScheme) {
    return Container(
      width: 56,
      height: 56,
      color: colorScheme.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(Icons.person, color: colorScheme.outline, size: 28),
    );
  }

  Widget _buildMetaChip(String text, ColorScheme colorScheme) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildGenreChip(String genre, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        genre,
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _formatDuration(int ticks) {
    final seconds = (ticks / 10000000).round();
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// ============================================================
// 辅助类型
// ============================================================

/// 剧集下载选择的封装
class _SeriesDownloadChoice {
  final List<EmbyMediaItem>? allSeasonsList;
  final EmbyMediaItem? singleSeason;

  _SeriesDownloadChoice.allSeasons(this.allSeasonsList) : singleSeason = null;

  _SeriesDownloadChoice.singleSeason(this.singleSeason)
      : allSeasonsList = null;
}

/// 专辑"全部下载"的哨兵值
/// 用 `identical()` 判断，避免与 EmbyMediaItem 实例冲突
const _albumDownloadAllSentinel = _AlbumDownloadAllSentinel();

class _AlbumDownloadAllSentinel {
  const _AlbumDownloadAllSentinel();
}

// ============================================================
// 剧集下载弹窗（支持逐集勾选）
// ============================================================

class _SeriesDownloadSheet extends StatefulWidget {
  final List<EmbyMediaItem> seasons;
  final Future<List<EmbyMediaItem>> Function(String seasonId) loadEpisodes;

  const _SeriesDownloadSheet({
    required this.seasons,
    required this.loadEpisodes,
  });

  @override
  State<_SeriesDownloadSheet> createState() => _SeriesDownloadSheetState();
}

class _SeriesDownloadSheetState extends State<_SeriesDownloadSheet> {
  /// seasonId -> 该季的集列表（懒加载）
  final Map<String, List<EmbyMediaItem>> _episodesBySeason = {};

  /// seasonId -> 是否正在加载
  final Map<String, bool> _loadingSeasons = {};

  /// 选中的 episode id 集合
  final Set<String> _selectedIds = {};

  /// 展开的季 id 集合
  final Set<String> _expandedSeasons = {};

  @override
  void initState() {
    super.initState();
    // 默认展开第一季并加载
    if (widget.seasons.isNotEmpty) {
      _expandedSeasons.add(widget.seasons.first.id);
      _loadEpisodes(widget.seasons.first.id);
    }
  }

  Future<void> _loadEpisodes(String seasonId) async {
    if (_episodesBySeason.containsKey(seasonId) ||
        _loadingSeasons[seasonId] == true) {
      return;
    }
    setState(() => _loadingSeasons[seasonId] = true);
    try {
      final eps = await widget.loadEpisodes(seasonId);
      if (!mounted) return;
      setState(() {
        _episodesBySeason[seasonId] = eps;
        _loadingSeasons[seasonId] = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _episodesBySeason[seasonId] = [];
        _loadingSeasons[seasonId] = false;
      });
    }
  }

  void _toggleSeason(String seasonId) {
    final eps = _episodesBySeason[seasonId] ?? [];
    if (eps.isEmpty) return;
    final allSelected = eps.every((e) => _selectedIds.contains(e.id));
    setState(() {
      if (allSelected) {
        for (final e in eps) {
          _selectedIds.remove(e.id);
        }
      } else {
        for (final e in eps) {
          _selectedIds.add(e.id);
        }
      }
    });
  }

  Future<void> _selectAll() async {
    // 确保所有季都已加载
    for (final s in widget.seasons) {
      if (!_episodesBySeason.containsKey(s.id)) {
        await _loadEpisodes(s.id);
      }
    }
    if (!mounted) return;
    setState(() {
      for (final eps in _episodesBySeason.values) {
        for (final e in eps) {
          _selectedIds.add(e.id);
        }
      }
    });
  }

  void _clearAll() {
    setState(() => _selectedIds.clear());
  }

  List<EmbyMediaItem> _collectSelected() {
    final result = <EmbyMediaItem>[];
    for (final eps in _episodesBySeason.values) {
      for (final e in eps) {
        if (_selectedIds.contains(e.id)) result.add(e);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedCount = _selectedIds.length;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- 顶部标题 + 快捷操作 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Text(
                    '下载剧集',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _selectAll,
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: _clearAll,
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ---- 季 / 集列表 ----
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.seasons.length,
                itemBuilder: (_, i) {
                  final s = widget.seasons[i];
                  final eps = _episodesBySeason[s.id] ?? [];
                  final loading = _loadingSeasons[s.id] == true;
                  final selectedCountInSeason =
                      eps.where((e) => _selectedIds.contains(e.id)).length;
                  final allSelected =
                      eps.isNotEmpty && selectedCountInSeason == eps.length;
                  final noneSelected = selectedCountInSeason == 0;
                  final expanded = _expandedSeasons.contains(s.id);

                  return Column(
                    children: [
                      // 季标题行
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (expanded) {
                              _expandedSeasons.remove(s.id);
                            } else {
                              _expandedSeasons.add(s.id);
                              _loadEpisodes(s.id);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                expanded
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                                color: cs.outline,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (loading)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              else if (eps.isNotEmpty)
                                Text(
                                  '$selectedCountInSeason/${eps.length}',
                                  style: TextStyle(
                                    color: cs.outline,
                                    fontSize: 12,
                                  ),
                                ),
                              const SizedBox(width: 4),
                              Checkbox(
                                value: allSelected
                                    ? true
                                    : (noneSelected ? false : null),
                                tristate: true,
                                onChanged: (loading || eps.isEmpty)
                                    ? null
                                    : (_) => _toggleSeason(s.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 集列表
                      if (expanded && !loading)
                        ...eps.map(
                          (e) => CheckboxListTile(
                            value: _selectedIds.contains(e.id),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedIds.add(e.id);
                                } else {
                                  _selectedIds.remove(e.id);
                                }
                              });
                            },
                            title: Text(
                              'E${e.indexNumber?.toString().padLeft(2, '0') ?? '?'}  ${e.name}',
                              style: const TextStyle(fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            dense: true,
                            contentPadding: const EdgeInsets.only(
                              left: 56,
                              right: 16,
                            ),
                            controlAffinity: ListTileControlAffinity.trailing,
                          ),
                        ),
                      const Divider(height: 1),
                    ],
                  );
                },
              ),
            ),

            // ---- 底部按钮 ----
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: selectedCount == 0
                            ? null
                            : () => Navigator.pop(
                                  context,
                                  _collectSelected(),
                                ),
                        child: Text('下载选中 ($selectedCount)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}