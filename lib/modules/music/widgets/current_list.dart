// lib/modules/music/widgets/current_list.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/modules/music/widgets/music_list_tile.dart';

class CurrentList extends StatelessWidget {
  const CurrentList({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MusicPlayerController>();
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            child: Row(
              children: [
                Text(
                  '当前播放列表',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 10),
                Obx(() => Text(
                  '${controller.playlist.length} 首歌曲',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                  ),
                )),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Obx(() {
              if (controller.playlist.isEmpty) {
                return Center(
                  child: Text(
                    '没有歌曲',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: controller.playlist.length,
                itemBuilder: (context, index) {
                  final episode = controller.playlist[index];
                  final isCurrent = controller.currentIndex.value == index;
                  final isPlaying = isCurrent && controller.isPlaying;

                  return MusicListTile(
                    episode: episode,
                    index: index,
                    isPlaying: isPlaying,
                    backgroundColor: isCurrent ? colorScheme.primaryContainer : null,
                    onTap: () {
                      Navigator.pop(context);
                      controller.currentIndex.value = index;
                      if (controller.onPlayCompleted != null) {
                        controller.onPlayCompleted!();
                      }
                    },
                    onMore: () {},
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}