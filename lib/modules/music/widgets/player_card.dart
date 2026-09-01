// lib/modules/music/widgets/player_card.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/modules/music/widgets/vinyl_record.dart';
import 'package:yuanying/modules/music/widgets/lyric_scroller.dart';
import 'package:yuanying/modules/music/widgets/current_list.dart';
import 'package:yuanying/modules/music/utils/clear_html_tags.dart';
import 'package:yuanying/utils/toast_utils.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/core/constants/app_constants.dart';
import 'package:yuanying/t4/services/source_manager.dart';

class PlayerCard extends StatefulWidget {
  const PlayerCard({super.key});

  @override
  State<PlayerCard> createState() => PlayerCardState();
}

class PlayerCardState extends State<PlayerCard> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  int _currentPage = 0;
  final RxBool _isLike = false.obs;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadFavoriteStatus();
  }

  void _loadFavoriteStatus() {
    final controller = Get.find<MusicPlayerController>();
    final vodId = controller.currentVodId;
    if (vodId != null && vodId.isNotEmpty) {
      final favorites = GStorage.getFavorites();
      _isLike.value = favorites.any((item) => item['vod_id'] == vodId);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleLike() async {
    final controller = Get.find<MusicPlayerController>();
    final vodId = controller.currentVodId;
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

    if (_isLike.value) {
      GStorage.removeFavorite(vodId);
      _isLike.value = false;
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
      _isLike.value = true;
      ToastUtils.show('已收藏');
    }
    // 通知其他界面刷新
    controller.notifyFavoriteChanged();
  }

  void _goToLyrics() {
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ===== 倍速弹窗 =====
  void _showSpeedDialog(BuildContext context) {
    final controller = Get.find<MusicPlayerController>();
    final colorScheme = Theme.of(context).colorScheme;
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('倍速'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: speeds.map((speed) {
            final isSelected = (controller.speed.value - speed).abs() < 0.01;
            return GestureDetector(
              onTap: () {
                controller.setSpeed(speed);
                Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${speed}x',
                  style: TextStyle(
                    color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ===== 定时弹窗 =====
  void _showTimerPicker(BuildContext context) {
    final controller = Get.find<MusicPlayerController>();
    final colorScheme = Theme.of(context).colorScheme;

    final presetOptions = [
      {'label': '禁用', 'value': 0, 'icon': Icons.cancel_outlined},
      {'label': '播放完当前曲目', 'value': -1, 'icon': Icons.music_note},
      {'label': '10 分钟', 'value': 10, 'icon': Icons.timer},
      {'label': '15 分钟', 'value': 15, 'icon': Icons.timer},
      {'label': '30 分钟', 'value': 30, 'icon': Icons.timer},
      {'label': '45 分钟', 'value': 45, 'icon': Icons.timer},
      {'label': '60 分钟', 'value': 60, 'icon': Icons.timer},
      {'label': '90 分钟', 'value': 90, 'icon': Icons.timer},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), // 只保留顶部圆角
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const Center(
                child: Text('定时关闭', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 4),
              ...presetOptions.map(
                (option) => ListTile(
                  dense: true,
                  leading: Icon(option['icon'] as IconData, size: 20, color: colorScheme.primary),
                  onTap: () {
                    Navigator.pop(context);
                    controller.setTimer(option['value'] as int);
                  },
                  title: Text(option['label'] as String, style: const TextStyle(fontSize: 14)),
                  trailing: Obx(() {
                    final current = controller.timerMinutes.value;
                    final selected = (current == option['value']);
                    return selected
                        ? Icon(Icons.done, size: 20, color: colorScheme.primary)
                        : const SizedBox.shrink();
                  }),
                ),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.edit, size: 20, color: colorScheme.primary),
                onTap: () {
                  Navigator.pop(context);
                  _showCustomTimerPicker(context);
                },
                title: const Text('自定义', style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  // ===== 自定义时间选择器 =====
  void _showCustomTimerPicker(BuildContext context) {
    final controller = Get.find<MusicPlayerController>();
    int currentMinutes = controller.timerMinutes.value;
    if (currentMinutes <= 0) currentMinutes = 30;

    final int hour = currentMinutes ~/ 60;
    final int minute = currentMinutes % 60;

    showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.inputOnly,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    ).then((time) {
      if (time != null) {
        final minutes = time.hour * 60 + time.minute;
        if (minutes > 0) {
          controller.setTimer(minutes);
        } else {
          ToastUtils.show('请选择有效时间');
        }
      }
    });
  }

  // ===== 跳过片头片尾  =====
  void _showSkipDialog(BuildContext context) {
    final controller = Get.find<MusicPlayerController>();
    final colorScheme = Theme.of(context).colorScheme;

    int localStart = controller.skipStartDuration.value;
    int localEnd = controller.skipEndDuration.value;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            void updateStart(int value) {
              setState(() => localStart = value);
            }
            void updateEnd(int value) {
              setState(() => localEnd = value);
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '跳过片头片尾',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '设置后将自动跳过片头片尾，仅当前会话有效',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // 片头行
                    Row(
                      children: [
                        const SizedBox(width: 44, child: Text('片头:', style: TextStyle(fontSize: 14))),
                        Expanded(
                          child: Slider(
                            min: 0,
                            max: 300,
                            divisions: 60,
                            value: localStart.toDouble(),
                            onChanged: (val) => updateStart(val.round()),
                            activeColor: colorScheme.primary,
                            inactiveColor: colorScheme.onSurface.withOpacity(0.1),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            localStart == 0 ? '关' : '${localStart}s',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 片尾行
                    Row(
                      children: [
                        const SizedBox(width: 44, child: Text('片尾:', style: TextStyle(fontSize: 14))),
                        Expanded(
                          child: Slider(
                            min: 0,
                            max: 300,
                            divisions: 60,
                            value: localEnd.toDouble(),
                            onChanged: (val) => updateEnd(val.round()),
                            activeColor: colorScheme.primary,
                            inactiveColor: colorScheme.onSurface.withOpacity(0.1),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            localEnd == 0 ? '关' : '${localEnd}s',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 预设按钮网格（使用 Wrap 替代 GridView，彻底避免布局异常）
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildPresetButton('片头30s', () => updateStart(30), colorScheme),
                        _buildPresetButton('片头60s', () => updateStart(60), colorScheme),
                        _buildPresetButton('片头90s', () => updateStart(90), colorScheme),
                        _buildPresetButton('片尾30s', () => updateEnd(30), colorScheme),
                        _buildPresetButton('片尾60s', () => updateEnd(60), colorScheme),
                        _buildPresetButton('片尾90s', () => updateEnd(90), colorScheme),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 底部操作栏
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              localStart = 0;
                              localEnd = 0;
                            });
                          },
                          child: Text('清除', style: TextStyle(color: colorScheme.primary)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: Text('取消', style: TextStyle(color: colorScheme.primary)),
                        ),
                        TextButton(
                          onPressed: () {
                            controller.skipStartDuration.value = localStart;
                            controller.skipEndDuration.value = localEnd;
                            final pos = controller.position;
                            if (localStart > 0 && pos.inSeconds < localStart) {
                              controller.seek(Duration(seconds: localStart));
                            }
                            Navigator.of(dialogContext).pop();
                          },
                          child: Text(
                            '确定',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPresetButton(String label, VoidCallback onTap, ColorScheme colorScheme) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
      ),
    );
  }

  // ===== 倍速按钮（图标） =====
  Widget _buildSpeedButton(BuildContext context) {
    final controller = Get.find<MusicPlayerController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Obx(() {
      final isHighlight = controller.speed.value != 1.0;
      return IconButton(
        iconSize: 24,
        onPressed: () => _showSpeedDialog(context),
        icon: Icon(
          Icons.speed,
          color: isHighlight ? colorScheme.primary : Colors.white,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GetBuilder<MusicPlayerController>(
            builder: (controller) {
              final cover = controller.coverUrl.value;
              if (cover.isNotEmpty) {
                return ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Image.network(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                );
              }
              return Container(color: colorScheme.surfaceContainerHighest);
            },
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(colorScheme),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) => setState(() => _currentPage = index),
                    children: const [
                      _VinylPage(),
                      LyricScroller(),
                    ],
                  ),
                ),
                _buildPageIndicator(colorScheme),
                _buildTopActions(context, colorScheme),
                _buildProgressBar(colorScheme),
                _buildControlButtons(colorScheme),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Get.back(),
          ),
          const Text(
            '正在播放',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          2,
          (index) => Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == _currentPage
                  ? colorScheme.primary
                  : Colors.white.withOpacity(0.3),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopActions(BuildContext context, ColorScheme colorScheme) {
    final controller = Get.find<MusicPlayerController>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 歌词按钮 - 无歌词时置灰
          Obx(() {
            final hasLyric = controller.lyric.value.isNotEmpty;
            return IconButton(
              iconSize: 24,
              onPressed: hasLyric ? _goToLyrics : null,
              icon: Icon(
                Icons.lyrics,
                color: hasLyric ? Colors.white : Colors.white.withOpacity(0.3),
              ),
            );
          }),
          const SizedBox(width: 20),

          // 倍速按钮（图标）
          _buildSpeedButton(context),
          const SizedBox(width: 20),

          // 跳过片头片尾
          IconButton(
            iconSize: 24,
            onPressed: () => _showSkipDialog(context),
            icon: const Icon(Icons.skip_next, color: Colors.white),
          ),
          const SizedBox(width: 20),

          // 定时
          Obx(() {
            final isActive = controller.timerMinutes.value != 0;
            return IconButton(
              iconSize: 24,
              onPressed: () => _showTimerPicker(context),
              icon: Icon(
                isActive ? Icons.timer : Icons.timer_outlined,
                color: isActive ? colorScheme.primary : Colors.white,
              ),
            );
          }),
          const SizedBox(width: 20),

          // 收藏
          Obx(() {
            final controller = Get.find<MusicPlayerController>();
            final _ = controller.favoriteVersion.value;
            final vodId = controller.currentVodId;
            bool isFav = false;
            if (vodId != null && vodId.isNotEmpty) {
              final favorites = GStorage.getFavorites();
              isFav = favorites.any((item) => item['vod_id'] == vodId);
            }
            // 同步 _isLike（用于其他逻辑）
            _isLike.value = isFav;
            return IconButton(
              iconSize: 24,
              onPressed: _toggleLike,
              icon: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? colorScheme.primary : Colors.white.withOpacity(0.6),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProgressBar(ColorScheme colorScheme) {
    final controller = Get.find<MusicPlayerController>();
    return StreamBuilder<Duration>(
      stream: controller.positionStream,
      initialData: Duration.zero,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = controller.duration;

        final progress = duration.inSeconds > 0
            ? position.inSeconds / duration.inSeconds
            : 0.0;

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackShape: const RoundedRectSliderTrackShape(),
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6,
                  disabledThumbRadius: 6,
                ),
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: Colors.white.withOpacity(0.3),
                thumbColor: colorScheme.primary,
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (value) {
                  final target = Duration(
                    seconds: (value * duration.inSeconds).toInt(),
                  );
                  controller.seek(target);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    seconds2duration(position.inSeconds),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  Text(
                    seconds2duration(duration.inSeconds),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControlButtons(ColorScheme colorScheme) {
    final controller = Get.find<MusicPlayerController>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _PlayModeButton(),
        const SizedBox(width: 20),
        IconButton(
          iconSize: 36,
          onPressed: () {
            if (controller.playlist.isEmpty) {
              ToastUtils.show('列表为空');
              return;
            }
            controller.playPrev();
          },
          icon: const Icon(Icons.skip_previous, color: Colors.white),
        ),
        const SizedBox(width: 20),
        Obx(() => IconButton(
          iconSize: 56,
          onPressed: controller.togglePlay,
          icon: Icon(
            controller.playing.value
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
            color: colorScheme.primary,
          ),
        )),
        const SizedBox(width: 20),
        IconButton(
          iconSize: 36,
          onPressed: () {
            if (controller.playlist.isEmpty) {
              ToastUtils.show('列表为空');
              return;
            }
            controller.playNext();
          },
          icon: const Icon(Icons.skip_next, color: Colors.white),
        ),
        const SizedBox(width: 20),
        IconButton(
          iconSize: 28,
          onPressed: () => _showCurrentList(context),
          icon: const Icon(Icons.menu, color: Colors.white),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  void _showCurrentList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const CurrentList(),
    );
  }
}

// ===== 黑胶唱片页面 =====
class _VinylPage extends StatelessWidget {
  const _VinylPage();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final availableWidth = constraints.maxWidth;
        final maxSize = (availableHeight < availableWidth
            ? availableHeight * 0.5
            : availableWidth * 0.5).clamp(100.0, 300.0);

        final controller = Get.find<MusicPlayerController>();

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() => SizedBox(
              height: maxSize,
              child: VinylRecordWidget(
                coverUrl: controller.coverUrl.value,
                isPlaying: controller.playing.value,
              ),
            )),
            const SizedBox(height: 12),
            Obx(() {
              final episodes = controller.playlist;
              final index = controller.currentIndex.value;
              final name = episodes.isNotEmpty && index < episodes.length
                  ? episodes[index].name
                  : '未选择歌曲';
              return Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              );
            }),
            const SizedBox(height: 4),
            Obx(() => Text(
              controller.author.value.isNotEmpty
                  ? controller.author.value
                  : controller.albumName.value,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )),
          ],
        );
      },
    );
  }
}

// ===== 播放模式按钮 =====
class _PlayModeButton extends StatelessWidget {
  const _PlayModeButton();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MusicPlayerController>();
    return Obx(() => IconButton(
      iconSize: 28,
      onPressed: controller.togglePlayMode,
      icon: Icon(
        controller.playMode.value.icon,
        color: Colors.white,
      ),
    ));
  }
}