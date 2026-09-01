// lib/modules/music/views/music_player_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/modules/music/widgets/player_list.dart';
import 'package:yuanying/utils/toast_utils.dart';
import 'package:yuanying/common/widgets/marquee.dart'; // 跑马灯组件
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

    return Obx(() {
      final hasSong = controller.currentEpisode != null;
      if (!hasSong) {
        return const SizedBox.shrink();
      }

      final isFirst = controller.currentIndex.value == 0;
      final isLast = controller.currentIndex.value == controller.playlist.length - 1;

      return GestureDetector(
        onTap: () => _showPlayerCard(context),
        child: Container(
          height: 50,
          width: double.infinity,
          margin: EdgeInsets.only(bottom: cancelMargin ? 0 : 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
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
              // ===== 封面图（圆角 + 阴影） =====
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
              const SizedBox(width: 10),
              // ===== 歌曲名（跑马灯） =====
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
              const SizedBox(width: 10),
              // ===== 控制按钮 =====
              Row(
                children: [
                  // 收藏按钮
                  Obx(() {
                    final controller = Get.find<MusicPlayerController>();
                    final _ = controller.favoriteVersion.value; // 依赖刷新
                    final vodId = controller.currentVodId;
                    bool isFav = false;
                    if (vodId != null && vodId.isNotEmpty) {
                      final favorites = GStorage.getFavorites();
                      isFav = favorites.any((item) => item['vod_id'] == vodId);
                    }
                    return IconButton(
                      iconSize: 24,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: isFav ? colorScheme.primary : colorScheme.outline.withOpacity(0.6),
                      icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
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
                        controller.notifyFavoriteChanged(); // 刷新所有界面
                      },
                    );
                  }),
                  const SizedBox(width: 4),
                  // 上一曲（第一首时置灰）
                  IconButton(
                    iconSize: 28,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: isFirst ? colorScheme.outline.withOpacity(0.3) : colorScheme.primary,
                    icon: const Icon(Icons.skip_previous),
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
                  const SizedBox(width: 4),
                  // 播放/暂停
                  IconButton(
                    iconSize: 32,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: colorScheme.primary,
                    icon: controller.playing.value
                        ? const Icon(Icons.pause_circle_filled)
                        : const Icon(Icons.play_circle_filled),
                    onPressed: controller.togglePlay,
                  ),
                  const SizedBox(width: 4),
                  // 下一曲（最后一首时置灰）
                  IconButton(
                    iconSize: 28,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: isLast ? colorScheme.outline.withOpacity(0.3) : colorScheme.primary,
                    icon: const Icon(Icons.skip_next),
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
                  const SizedBox(width: 4),
                  // 播放列表
                  IconButton(
                    iconSize: 28,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: colorScheme.primary,
                    icon: const Icon(Icons.queue_music),
                    onPressed: () => _showPlayerList(context),
                  ),
                ],
              ),
            ],
          ),
        ),
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