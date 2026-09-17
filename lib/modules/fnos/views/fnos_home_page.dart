import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:yuanying/common/widgets/loading_widget/m3e_loading_indicator.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import '../controllers/fnos_home_controller.dart';
import '../controllers/fnos_server_controller.dart';
import '../models/fnos_media_item.dart';
import '../services/fnos_api_service.dart';
import '../widgets/fnos_media_card.dart';

const Widget _loadingWidget = Center(child: M3ELoadingIndicator());

class FnosHomePage extends StatelessWidget {
  const FnosHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<FnosHomeController>()) {
      Get.put(FnosHomeController());
    }
    final ctrl = Get.find<FnosHomeController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Obx(() {
      if (ctrl.isLoading.value && ctrl.libraries.isEmpty) {
        return _loadingWidget;
      }
      if (ctrl.error.isNotEmpty && ctrl.libraries.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(ctrl.error.value,
                  style: TextStyle(color: colorScheme.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ctrl.loadHomeData(),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }

      final serverCtrl = Get.find<FnosServerController>();
      final server = serverCtrl.currentServer;
      if (server == null) {
        return const Center(child: Text('未选择服务器'));
      }
      final token = serverCtrl.getToken(server.id);
      final headers = FnosApiService().imageHeaders(token: token);

      return RefreshIndicator(
        onRefresh: ctrl.loadHomeData,
        child: CustomScrollView(
          slivers: [
            // ===== 我的媒体 =====
            if (ctrl.libraries.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Style.safeSpace,
                              vertical: 8,
                            ),
                            child: Text(
                              '我的媒体',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 160,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: Style.safeSpace,
                              ),
                              itemCount: ctrl.libraries.length,
                              itemBuilder: (_, i) {
                                final lib = ctrl.libraries[i];
                                final posterPath = lib.firstPoster ?? '';
                                final imageUrl = posterPath.isNotEmpty
                                    ? FnosApiService.imageUrl(
                                        server.baseUrl,
                                        posterPath,
                                        width: 400,
                                      )
                                    : '';
                                final isTvLib = lib.category == 'TV';
                                final isLiveLib = lib.category == 'IPTV';

                                return Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: GestureDetector(
                                    onTap: () => Get.toNamed(
                                      AppPages.fnosLibrary,
                                      arguments: {
                                        'libraryId': lib.guid,
                                        'libraryName': lib.title,
                                      },
                                    ),
                                    child: SizedBox(
                                      width: 200,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  if (imageUrl.isNotEmpty)
                                                    CachedNetworkImage(
                                                      imageUrl: imageUrl,
                                                      httpHeaders: headers,
                                                      fit: BoxFit.cover,
                                                      errorWidget: (_, __, ___) =>
                                                          Container(
                                                        color:
                                                            colorScheme.surfaceVariant,
                                                        child: Icon(
                                                          isLiveLib
                                                              ? Icons.live_tv_rounded
                                                              : (isTvLib
                                                                  ? Icons.tv_rounded
                                                                  : Icons
                                                                      .video_library_rounded),
                                                          size: 40,
                                                          color: colorScheme.outline,
                                                        ),
                                                      ),
                                                    )
                                                  else
                                                    Container(
                                                      color: colorScheme.surfaceVariant,
                                                      child: Icon(
                                                        isLiveLib
                                                            ? Icons.live_tv_rounded
                                                            : (isTvLib
                                                                ? Icons.tv_rounded
                                                                : Icons
                                                                    .video_library_rounded),
                                                        size: 40,
                                                        color: colorScheme.outline,
                                                      ),
                                                    ),

                                                  // 底部渐变 + 库名
                                                  Positioned(
                                                    left: 0,
                                                    right: 0,
                                                    bottom: 0,
                                                    child: Container(
                                                      padding: const EdgeInsets.fromLTRB(
                                                        10,
                                                        24,
                                                        10,
                                                        10,
                                                      ),
                                                      decoration: const BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: Alignment.topCenter,
                                                          end: Alignment.bottomCenter,
                                                          colors: [
                                                            Colors.transparent,
                                                            Color(0xE61C1C1C),
                                                          ],
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          if (isLiveLib) ...[
                                                            const Icon(
                                                              Icons.live_tv_rounded,
                                                              size: 14,
                                                              color: Colors.white,
                                                            ),
                                                            const SizedBox(width: 4),
                                                          ],
                                                          Expanded(
                                                            child: Text(
                                                              lib.title,
                                                              maxLines: 1,
                                                              overflow: TextOverflow
                                                                  .ellipsis,
                                                              style: const TextStyle(
                                                                color: Colors.white,
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight.w600,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
            // ===== 继续观看 =====
            if (ctrl.resumeItems.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Style.safeSpace, vertical: 8),
                      child: Text(
                        '继续观看',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: Style.safeSpace),
                        itemCount: ctrl.resumeItems.length,
                        itemBuilder: (_, i) {
                          final item = ctrl.resumeItems[i];
                          return _ResumeCard(
                            item: item,
                            baseUrl: server.baseUrl,
                            headers: headers,
                            onTap: () => _openResume(item),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

            // ===== 各媒体库预览 =====
            ...ctrl.libraries.map((lib) {
              final preview = ctrl.previews[lib.guid] ?? [];
              if (preview.isEmpty) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Style.safeSpace, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            lib.title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Get.toNamed(
                              AppPages.fnosLibrary,
                              arguments: {
                                'libraryId': lib.guid,
                                'libraryName': lib.title,
                              },
                            ),
                            child: Text(
                              '查看全部',
                              style: TextStyle(color: colorScheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 210,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: Style.safeSpace),
                        itemCount: preview.length,
                        itemBuilder: (_, i) {
                          final item = preview[i];
                          final imageUrl = FnosApiService.imageUrl(
                            server.baseUrl,
                            item.poster ?? '',
                            width: 300,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 120,
                              child: FnosMediaCard(
                                item: item,
                                imageUrl: imageUrl,
                                headers: headers,
                                onTap: () => _openItem(item),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            }),

            if (ctrl.libraries.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text('暂无媒体库')),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      );
    });
  }

  void _openItem(FnosPlayListItem item) {
    if (item.isFolder) {
      Get.toNamed(
        AppPages.fnosLibrary,
        arguments: {
          'libraryId': item.guid,
          'libraryName': item.title ?? '',
        },
      );
      return;
    }
    Get.toNamed(
      AppPages.fnosDetail,
      arguments: {
        'itemGuid': item.guid,
        'poster': item.poster,
        'title': item.title,
        'tvTitle': item.tvTitle,
        'type': item.type,
        'overview': item.overview,
      },
    );
  }

  void _openResume(FnosPlayListItem item) {
    final guid = (item.isEpisode &&
            item.parentGuid != null &&
            item.parentGuid!.isNotEmpty)
        ? item.parentGuid!
        : item.guid;
    Get.toNamed(
      AppPages.fnosDetail,
      arguments: {
        'itemGuid': guid,
        'initialEpisodeGuid': item.guid,
        'poster': item.poster,
        'title': item.title,
        'tvTitle': item.tvTitle,
        'type': item.type,
        'overview': item.overview,
      },
    );
  }
}

// ============================================================
// 继续观看卡片（16:9 横版）
// ============================================================
class _ResumeCard extends StatelessWidget {
  final FnosPlayListItem item;
  final String baseUrl;
  final Map<String, String> headers;
  final VoidCallback onTap;

  const _ResumeCard({
    required this.item,
    required this.baseUrl,
    required this.headers,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imageUrl = FnosApiService.imageUrl(
      baseUrl,
      item.poster ?? '',
      width: 640,
    );
    final progress = item.duration > 0
        ? (item.ts / item.duration).clamp(0.0, 1.0)
        : 0.0;
    final title = (item.tvTitle?.isNotEmpty == true)
        ? item.tvTitle!
        : (item.title ?? '');
    final subtitle = item.isEpisode && item.episodeNumber > 0
        ? '第${item.episodeNumber}集'
        : (item.airDate != null
            ? item.airDate!.split('-').first
            : '');

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          httpHeaders: headers,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: colorScheme.surfaceVariant,
                            child: Icon(Icons.movie,
                                color: colorScheme.outline),
                          ),
                        )
                      else
                        Container(
                          color: colorScheme.surfaceVariant,
                          child: Icon(Icons.movie,
                              color: colorScheme.outline),
                        ),
                      if (progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            color: colorScheme.primary,
                            backgroundColor: Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}