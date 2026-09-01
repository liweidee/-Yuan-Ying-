// lib/modules/music/views/music_player_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/modules/music/widgets/player_list.dart';
import 'package:yuanying/utils/toast_utils.dart';
import 'package:yuanying/common/widgets/marquee.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/core/constants/app_constants.dart';
import 'package:yuanying/t4/services/source_manager.dart';

/// 底部音乐播放状态条（不是页面）
class MusicPlayerView extends StatelessWidget {
  final bool cancelMargin;

  const MusicPlayerView({super.key, this.cancelMargin = false});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MusicPlayerController>();
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // 是否有底部安全区域（刘海屏）
    final hasBottomSafeArea = bottomPadding > 0;
    // 额外间距：cancelMargin=false 时保留 34px，否则为 0
    final extraMargin = cancelMargin ? 0.0 : 34.0;
    // 播放条主体高度（不含安全区域）
    const barHeight = 50.0;
    // 总高度 = 主体 + 额外间距 + (有安全区域时增加安全区域高度)
    final totalHeight = barHeight + extraMargin + (hasBottomSafeArea ? bottomPadding : 0);

    return Obx(() {
      final hasSong = controller.currentEpisode != null;
      if (!hasSong) {
        return const SizedBox.shrink();
      }

      final isFirst = controller.currentIndex.value == 0;
      final isLast = controller.currentIndex.value == controller.playlist.length - 1;

      // ===== 构建播放条主体 Widget =====
      Widget buildBarContent() {
        return Container(
          height: barHeight + extraMargin,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              // ===== 封面图 =====
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: controller.coverUrl.value.isNotEmpty
                      ? Image.network(
                          controller.coverUrl.value,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.music_note,
                              color: colorScheme.outline,
                              size: 18,
                            ),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.music_note,
                            color: colorScheme.outline,
                            size: 18,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              // ===== 歌曲名（跑马灯），使用 Expanded 撑满剩余空间 =====
              Expanded(
                child: MarqueeText(
                  controller.currentSongName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                  velocity: 25,
                  spacing: 30,
                ),
              ),
              const SizedBox(width: 8),
              // ===== 控制按钮区 =====
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 收藏按钮
                  Obx(() {
                    final controller = Get.find<MusicPlayerController>();
                    final _ = controller.favoriteVersion.value;
                    final vodId = controller.currentVodId;
                    bool isFav = false;
                    if (vodId != null && vodId.isNotEmpty) {
                      final favorites = GStorage.getFavorites();
                      isFav = favorites.any((item) => item['vod_id'] == vodId);
                    }
                    return IconButton(
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      color: isFav ? colorScheme.primary : colorScheme.outline.withOpacity(0.6),
                      icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, size: 20),
                      onPressed: () async {
                        if (vodId == null || vodId.isEmpty) {
                          ToastUtils.show('无法获取歌曲ID');
                          return;
                        }
                        final sourceManager = Get.find<SourceManager>();
                        final site = sourceManager.currentSite.value;
                        final sourceName = site?['name']?.toString() ?? '音乐';
                        final apiUrl = site?['api']?.toString() ?? '';
                        final siteKey = site?['key']?.toString() ?? '';
                        final configKey = sourceManager.currentConfigKey.value;
                        const detailType = DetailType.audio;
                        final songName = controller.currentSongName;
                        final cover = controller.coverUrl.value;

                        if (isFav) {
                          GStorage.removeFavorite(vodId);
                          ToastUtils.show('已取消收藏');
                        } else {
                          final item = {
                            'vod_id': vodId,
                            'vod_name': songName,
                            'vod_pic': cover,
                            'vod_remarks': '',
                            'vod_tag': '',
                            'type_name': sourceName,
                            'api_url': apiUrl,
                            'site_key': siteKey,
                            'config_key': configKey,
                            'detail_type': detailType,
                          };
                          GStorage.addFavorite(item);
                          ToastUtils.show('已收藏');
                        }
                        controller.notifyFavoriteChanged();
                      },
                    );
                  }),
                  const SizedBox(width: 2),
                  // 上一曲
                  IconButton(
                    iconSize: 24,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: isFirst ? colorScheme.outline.withOpacity(0.3) : colorScheme.primary,
                    icon: const Icon(Icons.skip_previous, size: 22),
                    onPressed: isFirst
                        ? null
                        : () {
                            if (controller.playlist.isEmpty) {
                              ToastUtils.show('列表为空');
                              return;
                            }
                            controller.playPrev();
                          },
                  ),
                  const SizedBox(width: 2),
                  // 播放/暂停
                  IconButton(
                    iconSize: 28,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: colorScheme.primary,
                    icon: controller.playing.value
                        ? const Icon(Icons.pause_circle_filled, size: 28)
                        : const Icon(Icons.play_circle_filled, size: 28),
                    onPressed: controller.togglePlay,
                  ),
                  const SizedBox(width: 2),
                  // 下一曲
                  IconButton(
                    iconSize: 24,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: isLast ? colorScheme.outline.withOpacity(0.3) : colorScheme.primary,
                    icon: const Icon(Icons.skip_next, size: 22),
                    onPressed: isLast
                        ? null
                        : () {
                            if (controller.playlist.isEmpty) {
                              ToastUtils.show('列表为空');
                              return;
                            }
                            controller.playNext();
                          },
                  ),
                  const SizedBox(width: 2),
                  // 播放列表
                  IconButton(
                    iconSize: 24,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: colorScheme.primary,
                    icon: const Icon(Icons.queue_music, size: 22),
                    onPressed: () => _showPlayerList(context),
                  ),
                ],
              ),
            ],
          ),
        );
      }

      // ===== 根据是否有安全区域选择布局方式 =====
      // 有底部安全区域（刘海屏）：使用 Stack 分层，背景延伸到底部
      if (hasBottomSafeArea) {
        return SizedBox(
          height: totalHeight,
          width: double.infinity,
          child: Stack(
            children: [
              // 底层：纯色背景延伸到底部（不镂空）
              Positioned.fill(
                child: Container(
                  color: colorScheme.surface,
                ),
              ),
              // 上层：播放条主体（底部对齐到安全区域上边缘）
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomPadding,
                child: buildBarContent(),
              ),
            ],
          ),
        );
      }

      // 无底部安全区域（非刘海屏）：直接返回播放条主体，无背景延伸
      return SizedBox(
        height: totalHeight,
        width: double.infinity,
        child: buildBarContent(),
      );
    });
  }

  void _showPlayerCard(BuildContext context) {
    final controller = Get.find<MusicPlayerController>();
    if (controller.currentEpisode == null) return;
    Get.toNamed(AppPages.musicPlayer);
  }

  void _showPlayerList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const PlayerList(),
    );
  }
}