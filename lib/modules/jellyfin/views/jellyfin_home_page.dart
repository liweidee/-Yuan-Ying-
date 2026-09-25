import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/loading_widget/m3e_loading_indicator.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/utils/jellyfin_converter.dart';
import '../controllers/jellyfin_home_controller.dart';
import '../models/jellyfin_media_item.dart';
import '../services/jellyfin_api_service.dart';

const Widget _loadingWidget = Center(child: M3ELoadingIndicator());

class JellyfinHomePage extends StatelessWidget {
  const JellyfinHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<JellyfinHomeController>()) {
      Get.put(JellyfinHomeController());
    }
    final controller = Get.find<JellyfinHomeController>();
    final theme = Theme.of(context);

    return Obx(() {
      if (controller.isLoading.value) {
        return _loadingWidget;
      }
      if (controller.error.isNotEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(controller.error.value,
                  style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => controller.loadHomeData(),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }

      final libraries = controller.libraries;
      final resume = controller.resumeItems;

      if (libraries.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('没有媒体库',
                  style: TextStyle(color: theme.colorScheme.outline)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => controller.loadHomeData(),
                child: const Text('刷新'),
              ),
            ],
          ),
        );
      }

      final server = controller.serverController.currentServer!;

      return CustomScrollView(
        slivers: [
          // 我的媒体
          if (libraries.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Style.safeSpace, vertical: 8),
                    child: Text(
                      '我的媒体',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: Style.safeSpace),
                      itemCount: libraries.length,
                      itemBuilder: (ctx, i) {
                        final lib = libraries[i];
                        // 库封面：直接请求库的 Primary 图
                        // Jellyfin 对 CollectionFolder 会返回该库的默认图，
                        // 没有就用某个子项的图兜底
                        final libImageUrl = JellyfinApiService.primaryImage(
                          server.baseUrl,
                          lib.id,
                          maxWidth: 400,
                        );

                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: GestureDetector(
                            onTap: () => Get.toNamed(
                              AppPages.jellyfinLibrary,
                              arguments: {
                                'libraryId': lib.id,
                                'libraryName': lib.name,
                                'collectionType': lib.collectionType,
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
                                          Image.network(
                                            libImageUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                              color: theme
                                                  .colorScheme.surfaceVariant,
                                              child: Icon(
                                                lib.isMusicLibrary
                                                    ? Icons.music_note
                                                    : Icons.video_library,
                                                size: 40,
                                                color:
                                                    theme.colorScheme.outline,
                                              ),
                                            ),
                                          ),
                                          // 底部渐变 + 库名
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      10, 20, 10, 8),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black
                                                        .withOpacity(0.75),
                                                  ],
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  if (lib.isMusicLibrary) ...[
                                                    Icon(Icons.music_note,
                                                        size: 14,
                                                        color: Colors.white),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  Expanded(
                                                    child: Text(
                                                      lib.name,
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
          // ===== 继续观看（16:9 横版卡片） =====
          if (resume.isNotEmpty)
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
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: Style.safeSpace),
                      itemCount: resume.length,
                      itemBuilder: (ctx, i) {
                        final item = resume[i];
                        // 用 displayBackdrop：与详情页顶部背景图一致
                        final imageUrl = JellyfinApiService.displayBackdrop(
                          server.baseUrl,
                          item,
                          maxWidth: 640,
                          apiKey: controller.serverController.getToken(server.id),
                        );
                        final progress =
                            item.userData?.playedPercentage != null
                                ? item.userData!.playedPercentage! / 100
                                : null;

                        // 标题 + 副标题（Jellyfin 网页端风格）
                        final title =
                            item.seriesName?.isNotEmpty == true
                                ? item.seriesName!
                                : item.name;
                        final subtitle = _resumeSubtitle(item);

                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: GestureDetector(
                            onTap: () => _openResumeItem(context, item),
                            child: SizedBox(
                              width: 220,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ---- 16:9 横版封面 ----
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.network(
                                            imageUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                              color: theme
                                                  .colorScheme.surfaceVariant,
                                              child: Icon(
                                                Icons.movie,
                                                color: theme
                                                    .colorScheme.outline,
                                              ),
                                            ),
                                          ),
                                          // ---- 右下角进度条 ----
                                          if (progress != null)
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              child:
                                                  LinearProgressIndicator(
                                                value: progress,
                                                minHeight: 3,
                                                color:
                                                    theme.colorScheme.primary,
                                                backgroundColor:
                                                    Colors.black54,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  // ---- 主标题 ----
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  // ---- 副标题 ----
                                  if (subtitle.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
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
                  const SizedBox(height: 16),
                ],
              ),
            ),

          // ===== 最近添加 =====
          if (controller.recentlyAddedItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Style.safeSpace, vertical: 8),
                    child: Text(
                      '最近添加',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface),
                    ),
                  ),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: Style.safeSpace),
                      itemCount: controller.recentlyAddedItems.length,
                      itemBuilder: (ctx, i) {
                        final item = controller.recentlyAddedItems[i];
                        final imageUrl = JellyfinApiService.displayPoster(
                          server.baseUrl,
                          item,
                          maxWidth: 300,
                          apiKey: controller.serverController.getToken(server.id),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => Get.toNamed(
                                AppPages.jellyfinDetail,
                                arguments: {'itemId': item.id}),
                            child: SizedBox(
                              width: 120,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: theme
                                              .colorScheme.surfaceVariant,
                                          child: Icon(Icons.movie,
                                              color:
                                                  theme.colorScheme.outline),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            theme.colorScheme.onSurface),
                                  ),
                                  if (item.productionYear != null)
                                    Text(
                                      item.productionYear.toString(),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: theme.colorScheme.outline),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

          // ===== 各媒体库横向卡片 =====
          ...libraries.map((lib) {
            final latest = controller.latestItems[lib.id] ?? [];

            if (latest.isEmpty) {
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
                        Row(
                          children: [
                            // 音乐库图标标识（新增）
                            if (lib.isMusicLibrary) ...[
                              Icon(Icons.music_note,
                                  size: 20, color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              lib.name,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () => Get.toNamed(
                            AppPages.jellyfinLibrary,
                            arguments: {
                              'libraryId': lib.id,
                              'libraryName': lib.name,
                              // ===== 关键：传入 collectionType =====
                              'collectionType': lib.collectionType,
                            },
                          ),
                          child: Text('查看全部',
                              style:
                                  TextStyle(color: theme.colorScheme.primary)),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: Style.safeSpace),
                      itemCount: latest.length,
                      itemBuilder: (ctx, i) {
                        final item = latest[i];
                        final imageUrl = JellyfinApiService.displayPoster(
                          server.baseUrl,
                          item,
                          maxWidth: 300,
                          apiKey: controller.serverController.getToken(server.id),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => Get.toNamed(
                                AppPages.jellyfinDetail,
                                arguments: {'itemId': item.id}),
                            child: SizedBox(
                              width: 120,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: theme
                                              .colorScheme.surfaceVariant,
                                          child: Icon(Icons.movie,
                                              color:
                                                  theme.colorScheme.outline),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            theme.colorScheme.onSurface),
                                  ),
                                  if (item.productionYear != null)
                                    Text(
                                      item.productionYear.toString(),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: theme.colorScheme.outline),
                                    ),
                                ],
                              ),
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
          }).toList(),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      );
    });
  }

  /// 打开"继续观看"条目：
  /// - Episode → 打开 Series 详情 + 定位到该集
  /// - Audio   → 打开 Album 详情 + 定位到该曲
  /// - 其他    → 直接打开自身详情
  void _openResumeItem(BuildContext context, JellyfinMediaItem item) {
    // Episode → Series
    if (item.isEpisode &&
        item.seriesId != null &&
        item.seriesId!.isNotEmpty) {
      Get.toNamed(
        AppPages.jellyfinDetail,
        arguments: {
          'itemId': item.seriesId!,
          'initialEpisodeId': item.id,
        },
      );
      return;
    }

    // Audio → Album
    if (item.isAudio &&
        item.albumId != null &&
        item.albumId!.isNotEmpty) {
      Get.toNamed(
        AppPages.jellyfinDetail,
        arguments: {
          'itemId': item.albumId!,
          'initialEpisodeId': item.id,
        },
      );
      return;
    }

    // 其他
    Get.toNamed(
      AppPages.jellyfinDetail,
      arguments: {'itemId': item.id},
    );
  }

  /// 继续观看卡片的副标题
  /// - Episode → "S01E05 · 集名"
  /// - 电影 → "2024"
  /// - 其他 → 空
  String _resumeSubtitle(JellyfinMediaItem item) {
    if (item.isEpisode) {
      final s = item.parentIndexNumber;
      final e = item.indexNumber;
      final epLabel = (s != null && e != null)
          ? 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}'
          : '';
      final parts = <String>[
        if (epLabel.isNotEmpty) epLabel,
        if (item.name.isNotEmpty) item.name,
      ];
      return parts.join(' · ');
    }
    if (item.productionYear != null) {
      return '${item.productionYear}';
    }
    return '';
  }
}