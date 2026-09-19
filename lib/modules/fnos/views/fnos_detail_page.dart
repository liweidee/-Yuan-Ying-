import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import '../controllers/fnos_detail_controller.dart';
import '../controllers/fnos_server_controller.dart';
import '../models/fnos_media_item.dart';
import '../services/fnos_api_service.dart';
import '../utils/fnos_converter.dart';
import '../services/fnos_auth_utils.dart';

class FnosDetailPage extends StatefulWidget {
  const FnosDetailPage({super.key});

  @override
  State<FnosDetailPage> createState() => _FnosDetailPageState();
}

class _FnosDetailPageState extends State<FnosDetailPage> {
  late final String itemGuid;
  late final String? _initialEpisodeGuid;
  late final FnosDetailController ctrl;
  final FnosApiService api = FnosApiService();

  final ScrollController _scrollController = ScrollController();
  double _appBarCollapse = 0;
  bool _overviewExpanded = false;
  static const double _appBarExpandedHeight = 260;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    itemGuid = args['itemGuid'] as String;
    _initialEpisodeGuid = args['initialEpisodeGuid'] as String?;

    if (!Get.isRegistered<FnosServerController>()) {
      Get.put(FnosServerController());
    }

    ctrl = Get.put(
      FnosDetailController(
        itemGuid: itemGuid,
        initialPoster: args['poster'] as String?,
        initialBackdrops: args['backdrops'] as String?,
        initialTitle: args['title'] as String?,
        initialTvTitle: args['tvTitle'] as String?,
        initialType: args['type'] as String?,
        initialOverview: args['overview'] as String?,
      ),
      tag: 'fnos_detail_$itemGuid',
    );
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    Get.delete<FnosDetailController>(tag: 'fnos_detail_$itemGuid');
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !mounted) return;
    final topPadding = MediaQuery.of(context).padding.top;
    final collapseDistance =
        _appBarExpandedHeight - kToolbarHeight - topPadding;
    if (collapseDistance <= 0) return;
    final t =
        (_scrollController.offset / collapseDistance).clamp(0.0, 1.0);
    if ((t - _appBarCollapse).abs() > 0.015) {
      setState(() => _appBarCollapse = t);
    }
  }

  double get _collapsedTitleOpacity {
    if (_appBarCollapse <= 0.72) return 0;
    return ((_appBarCollapse - 0.72) / 0.28).clamp(0.0, 1.0);
  }

  // ============================================================
  // 播放
  // ============================================================
  Future<void> _play([FnosPlayListItem? ep]) async {
    if (_isPlaying) return;
    _isPlaying = true;

    final serverCtrl = Get.find<FnosServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) {
      _isPlaying = false;
      return;
    }
    final token = serverCtrl.getToken(server.id);
    if (token == null) {
      _isPlaying = false;
      return;
    }

    final cont = ctrl.continueEpisode;
    final targetGuid = ep?.guid ??
        (_initialEpisodeGuid?.isNotEmpty == true
            ? _initialEpisodeGuid!
            : (ctrl.showEpisodes && cont != null ? cont.guid : itemGuid));

    SmartDialog.showLoading(msg: '获取播放信息...');
    try {
      // ① play/info
      final info = await api.getPlayInfo(
        baseUrl: server.baseUrl,
        token: token,
        itemGuid: targetGuid,
      );

      // ============================================================
      // ⚠️ 直播频道分支：不走 stream，直接用 live_channels
      // ============================================================
      if (info.type == 'LiveChannel') {
        SmartDialog.dismiss();

        if (info.liveChannels.isEmpty) {
          SmartDialog.showToast('无法获取直播源');
          return;
        }
        // 优先选 canPlay 的
        final channel = info.liveChannels.firstWhere(
          (c) => c.canPlay == 1 && c.path.isNotEmpty,
          orElse: () => info.liveChannels.first,
        );
        if (channel.path.isEmpty) {
          SmartDialog.showToast(
            channel.playError?.isNotEmpty == true
                ? channel.playError!
                : '直播源地址为空',
          );
          return;
        }

        final detailInfo = ctrl.item.value;
        final liveName = detailInfo?.title ?? channel.fileName;
        final posterUrl = detailInfo?.poster?.isNotEmpty == true
            ? FnosApiService.imageUrl(
                server.baseUrl, detailInfo!.poster!, width: 600)
            : '';

        debugPrint('=== 直播频道 ===');
        debugPrint('  path: ${channel.path}');
        debugPrint('  fileName: ${channel.fileName}');

        final videoDetail = FnosConverter.buildVideoDetail(
          vodId: detailInfo?.guid ?? targetGuid,
          vodName: liveName,
          posterUrl: posterUrl,
          overview: detailInfo?.overview ?? '',
          year: '',
          remarks: '直播',
          typeName: 'LiveChannel',
          playSources: [
            PlaySource(
              name: server.name,
              episodes: [Episode(name: liveName, url: channel.path)],
            ),
          ],
          defaultStreamUrl: channel.path,
          defaultEpisodeName: liveName,
        );

        // 直播一般不传 header（多数 m3u8 是公开的）
        // 如需认证，可以加 'headers': {'Authorization': token}
        Get.toNamed(
          AppPages.detail,
          arguments: {
            'isPush': true,
            'isDirectPushMode': true,
            'directUrl': channel.path,
            'directTitle': liveName,
            'videoDetail': videoDetail,
            'sourceName': server.name,
            'vodPic': posterUrl,
            'vodContent': detailInfo?.overview ?? '',
            'vodYear': '',
            'headers': <String, String>{},
          },
        );
        return;
      }

      // ============================================================
      // 普通资源：继续走 stream + play/play 或直连
      // ============================================================
      final mediaGuid = info.mediaGuid;
      if (mediaGuid == null || mediaGuid.isEmpty) {
        SmartDialog.dismiss();
        SmartDialog.showToast('无法获取媒体信息');
        return;
      }

      final stream = await api.getStreamInfo(
        baseUrl: server.baseUrl,
        token: token,
        mediaGuid: mediaGuid,
        accountMd5: FnosAuthUtils.md5Account(server.username ?? 'video'),
      );

      final bool isCloudMedia = stream.directLinkQualities.isNotEmpty;
      final String playLink;
      final Map<String, String> httpHeaders;

      if (isCloudMedia) {
        // 云盘：直连 CDN
        int pickIdx = -1;
        for (var i = 0; i < stream.directLinkQualities.length; i++) {
          if (stream.directLinkQualities[i]
              .url
              .toLowerCase()
              .contains('.m3u8')) {
            pickIdx = i;
            break;
          }
        }
        if (pickIdx < 0) pickIdx = 0;

        final quality = stream.directLinkQualities[pickIdx];
        playLink = quality.url;

        final cdnHeaders = <String, String>{};
        final streamHeader = stream.header ?? const <String, dynamic>{};
        for (final entry in streamHeader.entries) {
          final k = entry.key.toString();
          final v = entry.value;
          if (v is List && v.isNotEmpty) {
            cdnHeaders[k] = v.first.toString();
          } else if (v != null) {
            cdnHeaders[k] = v.toString();
          }
        }
        if (!cdnHeaders.containsKey('Referer')) {
          cdnHeaders['Referer'] = 'https://pan.quark.cn/';
        }
        if (!cdnHeaders.containsKey('User-Agent')) {
          cdnHeaders['User-Agent'] =
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/143.0.0.0 Safari/537.36';
        }
        httpHeaders = cdnHeaders;

        debugPrint('=== 云盘直连 ===');
        debugPrint('  URL: $playLink');
      } else {
        // 本地：play/play
        final vs = stream.videoStream;
        final videoEncoder = vs?.codecName ?? 'h264';
        final resolution = (vs?.resolutionType ?? '').isNotEmpty
            ? vs!.resolutionType!.toUpperCase()
            : _fallbackResolution(vs?.width ?? 0, vs?.height ?? 0);
        final bitrate = vs?.bps ?? 0;

        playLink = await api.resolvePlayLink(
          baseUrl: server.baseUrl,
          token: token,
          mediaGuid: mediaGuid,
          videoGuid: info.videoGuid ?? '',
          audioGuid: info.audioGuid ?? '',
          videoEncoder: videoEncoder,
          resolution: resolution,
          bitrate: bitrate,
          startTimestamp: info.ts > 0 ? info.ts : 0,
          subtitleGuid: info.subtitleGuid ?? '',
        );
        httpHeaders = <String, String>{'Authorization': token};

        debugPrint('=== 本地资源 ===');
        debugPrint('  playLink: $playLink');
      }

      final detailInfo = ctrl.item.value!;
      final episodeName =
          ep?.title ?? info.item?.title ?? detailInfo.title ?? '';
      final displayName = (detailInfo.tvTitle?.isNotEmpty == true)
          ? detailInfo.tvTitle!
          : (detailInfo.title ?? '');
      final posterUrl = FnosApiService.imageUrl(
        server.baseUrl,
        detailInfo.poster ?? '',
        width: 600,
      );

      final videoDetail = FnosConverter.buildVideoDetail(
        vodId: detailInfo.guid ?? itemGuid,
        vodName: displayName,
        posterUrl: posterUrl,
        overview: detailInfo.overview ?? '',
        year: (detailInfo.airDate ?? detailInfo.releaseDate ?? '')
            .split('-')
            .first,
        remarks: detailInfo.status ?? '',
        typeName: info.type ?? '',
        playSources: [
          PlaySource(
            name: server.name,
            episodes: [Episode(name: episodeName, url: playLink)],
          ),
        ],
        defaultStreamUrl: playLink,
        defaultEpisodeName: episodeName,
      );

      SmartDialog.dismiss();

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'isPush': true,
          'isDirectPushMode': true,
          'directUrl': playLink,
          'directTitle': episodeName,
          'videoDetail': videoDetail,
          'sourceName': server.name,
          'vodPic': posterUrl,
          'vodContent': detailInfo.overview ?? '',
          'vodYear': (detailInfo.airDate ?? '').split('-').first,
          'headers': httpHeaders,
        },
      );
    } catch (e, st) {
      debugPrint('=== play 异常 ===');
      debugPrint('$e');
      debugPrint('$st');
      SmartDialog.dismiss();
      SmartDialog.showToast('播放失败: $e');
    } finally {
      _isPlaying = false;
    }
  }

  String _fallbackResolution(int w, int h) {
    if (h <= 0) return '1080P';
    if (h >= 2160) return '2160P';
    if (h >= 1440) return '1440P';
    if (h >= 1080) return '1080P';
    if (h >= 720) return '720P';
    if (h >= 480) return '480P';
    return '360P';
  }

  /// 把视频宽高归一为服务端要求的画质字符串
  String _normalizeResolution(int w, int h) {
    if (h <= 0) return '1080p';
    if (h >= 2160) return '2160p';
    if (h >= 1440) return '1440p';
    if (h >= 1080) return '1080p';
    if (h >= 720) return '720p';
    if (h >= 480) return '480p';
    return '360p';
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
        if (ctrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (ctrl.error.isNotEmpty) {
          return _buildError(colorScheme);
        }
        final detail = ctrl.item.value;
        if (detail == null) {
          return const Center(child: Text('无详情数据'));
        }

        final server =
            Get.find<FnosServerController>().currentServer!;
        final token =
            Get.find<FnosServerController>().getToken(server.id);
        final headers = api.imageHeaders(token: token);
        
        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            _buildSliverAppBar(detail, server.baseUrl, headers, colorScheme),
            SliverToBoxAdapter(
              child: _buildNarrowBody(detail, server.baseUrl, headers, colorScheme),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        );
      }),
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              color: colorScheme.error, size: 48),
          const SizedBox(height: 16),
          Text(ctrl.error.value,
              style: TextStyle(color: colorScheme.error)),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              ctrl.error.value = '';
              ctrl.isLoading.value = true;
              ctrl.loadDetail();
            },
            child: Text('重试',
                style: TextStyle(color: colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SliverAppBar
  // ============================================================
  Widget _buildSliverAppBar(
    FnosItemInfo detail,
    String baseUrl,
    Map<String, String> headers,
    ColorScheme colorScheme,
  ) {
    final bgPath = ctrl.bestBackdrops;
    final bgUrl = bgPath.isNotEmpty
        ? FnosApiService.imageUrl(baseUrl, bgPath, width: 1280)
        : '';
    final logoUrl = detail.logo?.isNotEmpty == true
      ? FnosApiService.imageUrl(baseUrl, detail.logo!, width: 500)
      : '';

    return SliverAppBar(
      expandedHeight: _appBarExpandedHeight,
      pinned: true,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
        onPressed: () => Get.back(),
      ),
      title: Opacity(
        opacity: _collapsedTitleOpacity,
        child: Text(
          ctrl.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (bgUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: bgUrl,
                httpHeaders: headers,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Container(color: colorScheme.surfaceVariant),
              )
            else
              Container(color: colorScheme.surfaceVariant),

            // 渐变遮罩
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.55),
                    colorScheme.surface,
                  ],
                  stops: const [0.0, 0.65, 1.0],
                ),
              ),
            ),

            // Logo 或大标题
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Opacity(
                opacity: (1 - _appBarCollapse * 1.15).clamp(0.0, 1.0),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildLogoOrTitle(
                    logoUrl: logoUrl,
                    title: ctrl.displayTitle,
                    headers: headers,
                    colorScheme: colorScheme,
                    maxHeight: 72,
                    maxWidth: 300,
                    titleSize: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoOrTitle({
    required String logoUrl,
    required String title,
    required Map<String, String> headers,
    required ColorScheme colorScheme,
    double maxHeight = 72,
    double maxWidth = 300,
    double titleSize = 22,
    int titleMaxLines = 2,
  }) {
    if (logoUrl.isNotEmpty) {
      return ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: maxHeight, maxWidth: maxWidth),
        child: CachedNetworkImage(
          imageUrl: logoUrl,
          httpHeaders: headers,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => _buildTitleText(
            title,
            size: titleSize,
            maxLines: titleMaxLines,
            colorScheme: colorScheme,
          ),
        ),
      );
    }
    return _buildTitleText(
      title,
      size: titleSize,
      maxLines: titleMaxLines,
      colorScheme: colorScheme,
    );
  }

  Widget _buildTitleText(
    String title, {
    double size = 22,
    int maxLines = 2,
    required ColorScheme colorScheme,
  }) {
    return Text(
      title,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        shadows: const [
          Shadow(blurRadius: 8, color: Colors.black87),
        ],
      ),
    );
  }

  // ============================================================
  // 窄屏布局
  // ============================================================
  Widget _buildNarrowBody(
    FnosItemInfo detail,
    String baseUrl,
    Map<String, String> headers,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPoster(detail, baseUrl, headers, colorScheme),
              const SizedBox(width: 14),
              Expanded(
                child: _buildHeroInfoCard(detail, colorScheme,
                    compact: true),
              ),
            ],
          ),
        ),
        _buildHeroActions(colorScheme),
        Obx(() {
          if (!ctrl.showEpisodes || ctrl.episodes.isEmpty) {
            return const SizedBox.shrink();
          }
          return _buildWatchProgress(colorScheme);
        }),
        Obx(() {
          if (!ctrl.showEpisodes) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 简介（剧集在信息卡里已经隐藏，这里展开）
              if (detail.overview != null &&
                  detail.overview!.isNotEmpty)
                _buildOverview(detail.overview!, colorScheme),
              _buildSeasonSelector(colorScheme),
              _buildEpisodeHeader(colorScheme),
              _buildEpisodeList(baseUrl, headers, colorScheme),
            ],
          );
        }),
        Obx(() {
          if (!ctrl.showEpisodes) {
            // 非剧集：简介 & 演员
            return Column(
              children: [
                if (detail.overview != null &&
                    detail.overview!.isNotEmpty)
                  _buildOverview(detail.overview!, colorScheme),
                _buildActorsSection(baseUrl, headers, colorScheme),
              ],
            );
          }
          return _buildActorsSection(baseUrl, headers, colorScheme);
        }),
      ],
    );
  }

  // ============================================================
  // 宽屏布局
  // ============================================================
  Widget _buildWideBody(
    FnosItemInfo detail,
    String baseUrl,
    Map<String, String> headers,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPoster(detail, baseUrl, headers, colorScheme,
                    width: 200, height: 286),
                const SizedBox(height: 16),
                _buildHeroActions(colorScheme),
                Obx(() {
                  if (!ctrl.showEpisodes || ctrl.episodes.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _buildWatchProgress(colorScheme);
                }),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroInfoCard(detail, colorScheme, compact: false),
                Obx(() {
                  if (!ctrl.showEpisodes) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSeasonSelector(colorScheme),
                      _buildEpisodeHeader(colorScheme),
                      _buildEpisodeList(baseUrl, headers, colorScheme),
                    ],
                  );
                }),
                _buildActorsSection(baseUrl, headers, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 海报
  // ============================================================
  Widget _buildPoster(
    FnosItemInfo detail,
    String baseUrl,
    Map<String, String> headers,
    ColorScheme colorScheme, {
    double width = 108,
    double height = 154,
  }) {
    final posterPath = ctrl.bestPoster;
    final url = posterPath.isNotEmpty
        ? FnosApiService.imageUrl(baseUrl, posterPath, width: 400)
        : '';

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              httpHeaders: headers,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: colorScheme.surfaceVariant),
              errorWidget: (_, __, ___) => Container(
                color: colorScheme.surfaceVariant,
                child: Icon(Icons.movie,
                    color: colorScheme.outline, size: 32),
              ),
            )
          : Container(
              color: colorScheme.surfaceVariant,
              child: Icon(Icons.movie,
                  color: colorScheme.outline, size: 32),
            ),
    );
  }

  // ============================================================
  // 信息卡
  // ============================================================
  Widget _buildHeroInfoCard(
    FnosItemInfo detail,
    ColorScheme colorScheme, {
    bool compact = false,
  }) {
    final subtitle = ctrl.displaySubtitle;

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 0 : 4, compact ? 8 : 12, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ctrl.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 22 : 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _buildMetaWrap(detail, colorScheme),
          if (detail.overview != null &&
              detail.overview!.isNotEmpty &&
              !compact) ...[
            const SizedBox(height: 10),
            Text(
              detail.overview!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaWrap(FnosItemInfo detail, ColorScheme colorScheme) {
    final parts = <String>[];
    final year =
        (detail.airDate ?? detail.releaseDate ?? '').split('-').first;
    if (year.isNotEmpty) parts.add(year);
    if (detail.voteAverage != null && detail.voteAverage!.isNotEmpty) {
      parts.add('⭐ ${detail.voteAverage}');
    }
    if (detail.numberOfEpisodes > 0) {
      parts.add('${detail.numberOfEpisodes} 集');
    } else if (detail.runtime > 0) {
      parts.add('${detail.runtime} 分钟');
    }
    if (detail.numberOfSeasons > 0) {
      parts.add('${detail.numberOfSeasons} 季');
    }
    if (detail.status != null && detail.status!.isNotEmpty) {
      parts.add(detail.status!);
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: parts
          .map((p) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  p,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ))
          .toList(),
    );
  }

  // ============================================================
  // 播放 / 收藏
  // ============================================================
  Widget _buildHeroActions(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Obx(() {
        final label = ctrl.playButtonLabel;
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 240,
                minWidth: 180,
              ),
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _play(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    minimumSize: const Size(0, 52),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow_rounded, size: 20),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // ===== 收藏按钮 =====
            Obx(() {
              final fav = ctrl.isFavorite.value;
              final loading = ctrl.isFavoriteLoading.value;
              return Material(
                color: colorScheme.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: loading ? null : _toggleFavorite,
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: loading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            fav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: fav
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                  ),
                ),
              );
            }),
            const SizedBox(width: 8),

            // ===== 已看按钮 =====
            Obx(() {
              final watched = ctrl.isWatched.value;
              final loading = ctrl.isWatchedLoading.value;
              return Material(
                color: colorScheme.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: loading ? null : _toggleWatched,
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: loading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            watched
                                ? Icons.check_circle_rounded
                                : Icons.check_circle_outline_rounded,
                            color: watched
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                  ),
                ),
              );
            }),
          ],
        );
      }),
    );
  }

  // ============================================================
  // 观看进度
  // ============================================================
  Widget _buildWatchProgress(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Obx(() {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '观看进度',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${ctrl.watchedCount} / ${ctrl.episodes.length} 集',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ctrl.watchProgress,
                minHeight: 5,
                backgroundColor: colorScheme.surfaceVariant,
                valueColor:
                    AlwaysStoppedAnimation(colorScheme.primary),
              ),
            ),
          ],
        );
      }),
    );
  }

  // ============================================================
  // 简介
  // ============================================================
  Widget _buildOverview(String overview, ColorScheme colorScheme) {
    final needsExpand = overview.length > 100;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '简介',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            overview,
            maxLines: _overviewExpanded ? null : 4,
            overflow: _overviewExpanded
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.65,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (needsExpand)
            GestureDetector(
              onTap: () => setState(
                  () => _overviewExpanded = !_overviewExpanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _overviewExpanded ? '收起' : '展开全部',
                  style: TextStyle(
                      fontSize: 13, color: colorScheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // 季选择器
  // ============================================================
  Widget _buildSeasonSelector(ColorScheme colorScheme) {
    return Obx(() {
      if (ctrl.seasons.length <= 1) return const SizedBox.shrink();
      return SizedBox(
        height: 44,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          itemCount: ctrl.seasons.length,
          itemBuilder: (_, i) {
            final season = ctrl.seasons[i];
            final active = i == ctrl.selectedSeasonIndex.value;
            final label = season.title?.isNotEmpty == true
                ? season.title!
                : '第${season.seasonNumber}季';
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: active
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                selected: active,
                selectedColor: colorScheme.primary,
                backgroundColor:
                    colorScheme.surfaceVariant.withOpacity(0.5),
                side: BorderSide(
                  color: active
                      ? colorScheme.primary
                      : colorScheme.surfaceVariant,
                ),
                showCheckmark: false,
                onSelected: (_) => ctrl.selectSeason(i),
              ),
            );
          },
        ),
      );
    });
  }

  // ============================================================
  // 选集头部（数量 + 视图切换 + 正序倒序）
  // ============================================================
  Widget _buildEpisodeHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Icon(Icons.list_rounded, color: colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            '选集',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Obx(() {
            if (ctrl.episodes.isEmpty) return const SizedBox.shrink();
            return Text(
              '${ctrl.episodes.length} 集',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.outline,
              ),
            );
          }),
          const Spacer(),
          Obx(() {
            if (ctrl.episodes.isEmpty) return const SizedBox.shrink();
            return Row(
              children: [
                _sortOrderBtn(colorScheme),
                const SizedBox(width: 4),
                _viewModeBtn(0, Icons.view_list_rounded, colorScheme),
                _viewModeBtn(1, Icons.grid_view_rounded, colorScheme),
                _viewModeBtn(2, Icons.apps_rounded, colorScheme),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _sortOrderBtn(ColorScheme colorScheme) {
    return Obx(() {
      final asc = ctrl.episodeSortAscending.value;
      return Tooltip(
        message: asc ? '正序（点击切换倒序）' : '倒序（点击切换正序）',
        child: InkWell(
          onTap: ctrl.toggleSortOrder,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  asc
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  asc ? '正序' : '倒序',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _viewModeBtn(
      int mode, IconData icon, ColorScheme colorScheme) {
    return Obx(() {
      final active = ctrl.episodeViewMode.value == mode;
      return Tooltip(
        message: mode == 0 ? '详细' : (mode == 1 ? '封面' : '按钮'),
        child: InkWell(
          onTap: () => ctrl.toggleEpisodeViewMode(mode),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(6),
            margin: const EdgeInsets.only(left: 4),
            decoration: active
                ? BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Icon(
              icon,
              size: 18,
              color: active
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    });
  }

  // ============================================================
  // 选集主体
  // ============================================================
  Widget _buildEpisodeList(
    String baseUrl,
    Map<String, String> headers,
    ColorScheme colorScheme,
  ) {
    return Obx(() {
      if (ctrl.isLoadingEpisodes.value) {
        return const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (ctrl.episodes.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              '暂无剧集',
              style: TextStyle(color: colorScheme.outline),
            ),
          ),
        );
      }
      switch (ctrl.episodeViewMode.value) {
        case 1:
          return _buildEpisodeGrid(baseUrl, headers, colorScheme);
        case 2:
          return _buildEpisodeButtons(colorScheme);
        default:
          return _buildEpisodeDetailList(baseUrl, headers, colorScheme);
      }
    });
  }

  // ============================================================
  // 详细列表
  // ============================================================
  Widget _buildEpisodeDetailList(
    String baseUrl,
    Map<String, String> headers,
    ColorScheme colorScheme,
  ) {
    return Obx(() {
      final episodes = ctrl.sortedEpisodes;
      final cont = ctrl.continueEpisode;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(episodes.length, (i) {
          final ep = episodes[i];
          final thumbPath = ep.poster ?? '';
          final thumbUrl = thumbPath.isNotEmpty
              ? FnosApiService.imageUrl(baseUrl, thumbPath, width: 200)
              : '';
          final progress = ep.duration > 0
              ? (ep.ts / ep.duration).clamp(0.0, 1.0)
              : 0.0;
          final isInitial = ep.guid == _initialEpisodeGuid;
          final isContinue = cont?.guid == ep.guid;
          final isWatched = ep.watched > 0;
          final epNum = ep.episodeNumber > 0 ? ep.episodeNumber : i + 1;

          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Material(
              color: isContinue
                  ? colorScheme.primary.withOpacity(0.1)
                  : colorScheme.surfaceVariant.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _play(ep),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      // 缩略图
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 112,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: colorScheme.surfaceVariant,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: thumbUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: thumbUrl,
                                    httpHeaders: headers,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                        Center(
                                      child: Text(
                                        '$epNum',
                                        style: TextStyle(
                                          color: colorScheme
                                              .onSurfaceVariant,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      '$epNum',
                                      style: TextStyle(
                                        color: colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                          Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white
                                .withOpacity(isContinue ? 0.9 : 0.65),
                            size: 30,
                          ),
                          if (progress > 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                backgroundColor: Colors.black54,
                                valueColor: AlwaysStoppedAnimation(
                                    colorScheme.primary),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isContinue
                                        ? colorScheme.primary
                                        : colorScheme.surfaceVariant,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isContinue ? '继续' : 'E$epNum',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isContinue
                                          ? colorScheme.onPrimary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ep.title?.isNotEmpty == true
                                        ? ep.title!
                                        : '第$epNum集',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isContinue
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      color: isContinue
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                if (isWatched)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: colorScheme.primary,
                                    size: 16,
                                  ),
                              ],
                            ),
                            if (ep.overview != null &&
                                ep.overview!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                ep.overview!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            if (ep.duration > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                _formatDuration(ep.duration),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      );
    });
  }

  // ============================================================
  // 封面九宫格
  // ============================================================
  Widget _buildEpisodeGrid(
    String baseUrl,
    Map<String, String> headers,
    ColorScheme colorScheme,
  ) {
    return Obx(() {
      final episodes = ctrl.sortedEpisodes;

      return LayoutBuilder(
        builder: (context, constraints) {
          final crossCount = constraints.maxWidth > 900
              ? 6
              : constraints.maxWidth > 600
                  ? 4
                  : 3;
          final itemW = (constraints.maxWidth - 32 - (crossCount - 1) * 8) /
              crossCount;
          final itemH = itemW * 9 / 16;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(episodes.length, (i) {
                final ep = episodes[i];
                final epNum =
                    ep.episodeNumber > 0 ? ep.episodeNumber : i + 1;
                final posterPath = ep.poster ?? '';
                final posterUrl = posterPath.isNotEmpty
                    ? FnosApiService.imageUrl(baseUrl, posterPath,
                        width: 300)
                    : '';
                final hasProgress = ep.ts > 0 && ep.duration > 0;
                final progress = hasProgress ? ep.ts / ep.duration : 0.0;

                return GestureDetector(
                  onTap: () => _play(ep),
                  child: SizedBox(
                    width: itemW,
                    height: itemH + 28,
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: colorScheme.surfaceVariant,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (posterUrl.isNotEmpty)
                                  CachedNetworkImage(
                                    imageUrl: posterUrl,
                                    httpHeaders: headers,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Center(
                                      child: Text(
                                        '$epNum',
                                        style: TextStyle(
                                          color: colorScheme
                                              .onSurfaceVariant,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Center(
                                    child: Text(
                                      '$epNum',
                                      style: TextStyle(
                                        color: colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color:
                                        Colors.white.withOpacity(0.7),
                                    size: 32,
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withOpacity(0.7),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$epNum',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                if (hasProgress)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: LinearProgressIndicator(
                                      value: progress.clamp(0.0, 1.0),
                                      backgroundColor: Colors.black54,
                                      valueColor:
                                          AlwaysStoppedAnimation(
                                              colorScheme.primary),
                                      minHeight: 3,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '第$epNum集',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          );
        },
      );
    });
  }

  // ============================================================
  // 数字按钮
  // ============================================================
  Widget _buildEpisodeButtons(ColorScheme colorScheme) {
    return Obx(() {
      final episodes = ctrl.sortedEpisodes;

      return LayoutBuilder(
        builder: (context, constraints) {
          final crossCount = constraints.maxWidth > 900
              ? 12
              : constraints.maxWidth > 600
                  ? 8
                  : 6;
          final btnSize =
              (constraints.maxWidth - 32 - (crossCount - 1) * 8) /
                  crossCount;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(episodes.length, (i) {
                final ep = episodes[i];
                final epNum =
                    ep.episodeNumber > 0 ? ep.episodeNumber : i + 1;
                final hasProgress = ep.ts > 0 && ep.duration > 0;
                final isWatched = ep.watched > 0;

                return GestureDetector(
                  onTap: () => _play(ep),
                  child: Container(
                    width: btnSize.clamp(40, 64),
                    height: btnSize.clamp(40, 64),
                    decoration: BoxDecoration(
                      color: hasProgress
                          ? colorScheme.primary.withOpacity(0.15)
                          : colorScheme.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasProgress
                            ? colorScheme.primary.withOpacity(0.4)
                            : colorScheme.surfaceVariant,
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '$epNum',
                          style: TextStyle(
                            fontSize: btnSize > 50 ? 16 : 14,
                            fontWeight: FontWeight.bold,
                            color: hasProgress
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                        if (isWatched)
                          Positioned(
                            top: 3,
                            right: 3,
                            child: Icon(
                              Icons.check_circle,
                              size: 12,
                              color: colorScheme.primary,
                            ),
                          ),
                        if (hasProgress)
                          Positioned(
                            bottom: 3,
                            left: 6,
                            right: 6,
                            child: LinearProgressIndicator(
                              value:
                                  (ep.ts / ep.duration).clamp(0.0, 1.0),
                              backgroundColor: Colors.white12,
                              valueColor: AlwaysStoppedAnimation(
                                  colorScheme.primary),
                              minHeight: 2,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          );
        },
      );
    });
  }

  // ============================================================
  // 演员
  // ============================================================
  Widget _buildActorsSection(
    String baseUrl,
    Map<String, String> headers,
    ColorScheme colorScheme,
  ) {
    return Obx(() {
      final actors = ctrl.persons
          .where((p) => p['job']?.toString() == 'Actor')
          .take(20)
          .toList();
      if (actors.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
            child: Text(
              '演职人员',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: actors.length,
              itemBuilder: (_, i) {
                final p = actors[i];
                final name = p['name']?.toString() ?? '';
                final role = p['role']?.toString() ?? '';
                final profile = p['profile_path']?.toString() ?? '';
                final imgUrl = profile.isNotEmpty
                    ? FnosApiService.imageUrl(baseUrl, profile,
                        width: 200)
                    : '';
                return Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: imgUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: imgUrl,
                                  httpHeaders: headers,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      _avatarFallback(colorScheme),
                                )
                              : _avatarFallback(colorScheme),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (role.isNotEmpty)
                        Text(
                          role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _avatarFallback(ColorScheme colorScheme) {
    return Container(
      width: 60,
      height: 60,
      color: colorScheme.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(Icons.person, color: colorScheme.outline, size: 30),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // 收藏 / 已看
  // ============================================================
  Future<void> _toggleFavorite() async {
    final serverCtrl = Get.find<FnosServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return;
    final token = serverCtrl.getToken(server.id);
    if (token == null) return;

    final detail = ctrl.item.value;
    if (detail == null || detail.guid == null || detail.guid!.isEmpty) {
      SmartDialog.showToast('当前条目无有效 GUID');
      return;
    }

    ctrl.isFavoriteLoading.value = true;
    try {
      final wasFav = ctrl.isFavorite.value;
      final ok = wasFav
          ? await api.removeFavorite(
              baseUrl: server.baseUrl,
              token: token,
              itemGuid: detail.guid!,
            )
          : await api.addFavorite(
              baseUrl: server.baseUrl,
              token: token,
              itemGuid: detail.guid!,
            );

      if (ok) {
        ctrl.isFavorite.value = !wasFav;
        SmartDialog.showToast(wasFav ? '已取消收藏' : '已收藏');
      } else {
        SmartDialog.showToast('操作失败');
      }
    } catch (e) {
      SmartDialog.showToast('操作失败: $e');
    } finally {
      ctrl.isFavoriteLoading.value = false;
    }
  }

  Future<void> _toggleWatched() async {
    final serverCtrl = Get.find<FnosServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return;
    final token = serverCtrl.getToken(server.id);
    if (token == null) return;

    final detail = ctrl.item.value;
    if (detail == null || detail.guid == null || detail.guid!.isEmpty) {
      SmartDialog.showToast('当前条目无有效 GUID');
      return;
    }

    ctrl.isWatchedLoading.value = true;
    try {
      final wasWatched = ctrl.isWatched.value;
      final ok = wasWatched
          ? await api.markUnwatched(
              baseUrl: server.baseUrl,
              token: token,
              itemGuid: detail.guid!,
            )
          : await api.markWatched(
              baseUrl: server.baseUrl,
              token: token,
              itemGuid: detail.guid!,
            );

      if (ok) {
        ctrl.isWatched.value = !wasWatched;
        SmartDialog.showToast(wasWatched ? '已标记未看' : '已标记已看');
      } else {
        SmartDialog.showToast('操作失败');
      }
    } catch (e) {
      SmartDialog.showToast('操作失败: $e');
    } finally {
      ctrl.isWatchedLoading.value = false;
    }
  }
}