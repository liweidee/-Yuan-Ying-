import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/modules/video/controllers/intro_controller.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/common/widgets/scroll_behavior.dart';
import 'package:yuanying/common/widgets/image_viewer/gallery_viewer.dart';
import 'package:yuanying/common/widgets/image_viewer/hero.dart';

/// 简介区域
class IntroView extends StatelessWidget {
  // ===== 通过构造函数接收 controllerTag =====
  final String controllerTag;
  const IntroView({super.key, required this.controllerTag});

  @override
  Widget build(BuildContext context) {
    // ===== 带 tag 查找 DetailController =====
    final detailController = Get.find<DetailController>(tag: controllerTag);
    final introController = detailController.introController;

    return Obx(() {
      final detail = introController.videoDetail.value;
      final _ = introController.displaySourceIndex.value;
      final __ = introController.currentEpisodeIndex.value;

      if (detail == null) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                '数据加载失败，请返回重试',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        );
      }

      return ScrollConfiguration(
        behavior: const NoScrollbarBehavior(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _buildContent(context, detail, detailController, introController),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildPlaySourceSection(context, detailController, introController),
            ),
            SliverToBoxAdapter(
              child: _buildQualitySection(context, detailController),
            ),
            SliverToBoxAdapter(
              child: _buildCollectionSection(context, detailController, introController),
            ),
            SliverToBoxAdapter(
              child: _buildEpisodeList(context, detailController, introController),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 100),
            ),
          ],
        ),
      );
    });
  }

  // ========== 封面 + 内容区 ==========
  Widget _buildContent(
    BuildContext context,
    VideoDetail detail,
    DetailController detailController,
    IntroController introController,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sourceName = introController.sourceName.value;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ============================================================
        // 封面图 - 修改点：添加 GestureDetector + fromHero
        // ============================================================
        GestureDetector(
          onTap: () => showImageViewer(context, detail.vodPic, tag: detail.vodPic),
          child: fromHero(
            tag: detail.vodPic,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                detail.vodPic,
                width: 100,
                height: 133,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 100,
                    height: 133,
                    color: colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 100,
                    height: 133,
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image,
                      size: 40,
                      color: colorScheme.outline,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      detail.vodName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Obx(() {
                    final isFav = introController.isFavorite.value;
                    return GestureDetector(
                      onTap: () => introController.toggleFavorite(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isFav
                              ? colorScheme.primary.withOpacity(0.15)
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          border: isFav
                              ? Border.all(color: colorScheme.primary, width: 1.2)
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isFav ? Icons.star : Icons.star_border,
                              size: 14,
                              color: isFav ? colorScheme.primary : colorScheme.outline,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              isFav ? '已收藏' : '收藏',
                              style: TextStyle(
                                fontSize: 11,
                                color: isFav ? colorScheme.primary : colorScheme.outline,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  sourceName,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                  ),
                ),
              ),
              if (detail.vodRemarks?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  detail.vodRemarks!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              // ============================================================
              // 简介文本 - 修改点：添加 GestureDetector 点击弹窗
              // ============================================================
              GestureDetector(
                onTap: () => detailController.showIntroDetailPanel(context),
                child: Text(
                  detail.vodContent ?? '暂无简介',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ========== 播放源区域 ==========
  Widget _buildPlaySourceSection(
    BuildContext context,
    DetailController detailController,
    IntroController introController,
  ) {
    final sourceNames = introController.sourceNames;
    if (sourceNames.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentIndex = introController.displaySourceIndex.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '播放源',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sourceNames.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final name = sourceNames[index];
                final isSelected = index == currentIndex;
                return GestureDetector(
                  onTap: () => detailController.switchSource(index),
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.15)
                          : colorScheme.onInverseSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: isSelected
                          ? Border.all(
                              color: colorScheme.primary,
                              width: 1.2,
                            )
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ========== 画质区域 ==========
  Widget _buildQualitySection(
    BuildContext context,
    DetailController detailController,
  ) {
    final qualities = detailController.currentQualities;
    if (qualities.length <= 1) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUrl = detailController.currentPlayUrl.value;

    final currentQuality = qualities.firstWhere(
      (q) => q.url == currentUrl,
      orElse: () => qualities.first,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '画质',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: qualities.map((quality) {
              final isSelected = quality.url == currentUrl;
              return GestureDetector(
                onTap: () => detailController.switchQuality(quality),  // ← 修复
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.onInverseSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: isSelected
                        ? Border.all(
                            color: colorScheme.primary,
                            width: 1.2,
                          )
                        : null,
                  ),
                  child: Text(
                    quality.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ========== 合集卡片（推送按钮在这里） ==========
  Widget _buildCollectionSection(
    BuildContext context,
    DetailController detailController,
    IntroController introController,
  ) {
    final episodes = introController.displayEpisodes;
    if (episodes.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final episodeIndex = introController.currentEpisodeIndex.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Text(
            '合集',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '正在播放：${episodeIndex + 1}',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.outline,
            ),
          ),
          const Spacer(),

          // ===== 推送按钮（纸飞机图标） =====
          Obx(() {
            if (!detailController.showPushButton.value) {
              return const SizedBox.shrink();
            }
            return GestureDetector(
              onTap: () {
                detailController.pushToDetail();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerHighest
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.send,
                      size: 14,
                      color: isDark
                          ? colorScheme.outline
                          : colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '推送',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? colorScheme.outline
                            : colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(width: 8),

          GestureDetector(
            onTap: () => detailController.showEpisodePanel(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '查看全部',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_forward_ios_outlined,
                  size: 12,
                  color: colorScheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== 剧集列表（桌面换行 / 移动端水平滚动） ==========
  Widget _buildEpisodeList(
    BuildContext context,
    DetailController detailController,
    IntroController introController,
  ) {
    final episodes = introController.displayEpisodes;
    if (episodes.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final episodeIndex = introController.currentEpisodeIndex.value;
    final displayIndex = introController.displaySourceIndex.value;
    final playIndex = introController.currentSourceIndex.value;
    final isPlayingLine = displayIndex == playIndex;
    final isWide = MediaQuery.sizeOf(context).width > 800;

    // ---- 按钮构建函数 ----
    Widget buildEpisodeButton(int index) {
      final episode = episodes[index];
      final isActive = isPlayingLine && index == episodeIndex;
      final padding = isWide
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 10);

      return GestureDetector(
        onTap: () => detailController.switchEpisode(index),
        child: Container(
          padding: padding,
          constraints: const BoxConstraints(
            minWidth: 70,
            maxWidth: 88,
          ),
          height: 48, // 固定两行高度
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            border: isActive
                ? null
                : Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start, // 从左上开始
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (isActive) ...[
                        WidgetSpan(
                          child: Icon(
                            Icons.play_circle_outline,
                            size: 14,
                            color: Colors.white,
                          ),
                          alignment: PlaceholderAlignment.middle, // 与文字基线对齐
                        ),
                        const TextSpan(text: ' '), // 图标和文字之间加空格
                      ],
                      TextSpan(text: episode.name),
                    ],
                  ),
                  maxLines: 2,              // 固定两行
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left, // 左对齐
                  style: TextStyle(
                    fontSize: 11,
                    color: isActive ? Colors.white : colorScheme.onSurface,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ---- 桌面端：左对齐，换行，行间距生效 ----
    if (isWide) {
      return Container(
        width: double.infinity,
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                child: Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 6,
                  runSpacing: 8,
                  children: episodes.asMap().entries.map((entry) {
                    return buildEpisodeButton(entry.key);
                  }).toList(),
                ),
              );
            },
          ),
        ),
      );
    }

    // ---- 移动端：水平滚动 ----
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: episodes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            return buildEpisodeButton(index);
          },
        ),
      ),
    );
  }
}