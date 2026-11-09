import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/danmaku/controllers/danmaku_controller.dart';
import 'package:yuanying/modules/danmaku/widgets/danmaku_view.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/modules/video/widgets/danmaku_settings.dart';
import 'package:yuanying/modules/video/widgets/setting_sheet.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/plugin/pl_player/view.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/utils/duration_utils.dart';

/// 短剧模式播放页
///
/// 设计原则：**不新增业务逻辑，仅新增 UI 皮肤**
/// - 播放：复用 PlPlayerController
/// - 切集：复用 DetailController.switchEpisode
/// - 收藏 / 选集 / 倍速 / 弹幕 / 缓存 / 清晰度 / 设置：全部复用现有方法
class ShortDramaPlayerPage extends StatefulWidget {
  final DetailController detailController;
  final String controllerTag;

  const ShortDramaPlayerPage({
    super.key,
    required this.detailController,
    required this.controllerTag,
  });

  @override
  State<ShortDramaPlayerPage> createState() => _ShortDramaPlayerPageState();
}

class _ShortDramaPlayerPageState extends State<ShortDramaPlayerPage> {
  late final PageController _pages;
  late int _current;

  @override
  void initState() {
    super.initState();
    final ic = widget.detailController.introController;
    final episodes = ic.displayEpisodes;
    final len = episodes.length;
    _current = len == 0
        ? 0
        : ic.currentEpisodeIndex.value.clamp(0, len - 1);
    _pages = PageController(initialPage: _current);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _pages.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (index == _current) return;
    setState(() => _current = index);
    widget.detailController.switchEpisode(index);
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.detailController.introController.displayEpisodes;
    if (episodes.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('暂无剧集', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return PopScope(
      canPop: true,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,   // Android 白图标
          statusBarBrightness: Brightness.dark,        // iOS 白文字
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: PageView.builder(
            controller: _pages,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              if (index != _current) {
                return _PagePlaceholder(episode: episodes[index]);
              }
              return _ShortDramaContent(
                detailController: widget.detailController,
                controllerTag: widget.controllerTag,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 非当前页占位（不渲染播放器，避免多实例冲突）
class _PagePlaceholder extends StatelessWidget {
  final Episode episode;
  const _PagePlaceholder({required this.episode});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Text(
        episode.name,
        style: const TextStyle(color: Colors.white54, fontSize: 24),
      ),
    );
  }
}

/// 当前页：视频 + 弹幕 + 手势层 + UI 覆盖层
class _ShortDramaContent extends StatefulWidget {
  final DetailController detailController;
  final String controllerTag;

  const _ShortDramaContent({
    required this.detailController,
    required this.controllerTag,
  });

  @override
  State<_ShortDramaContent> createState() => _ShortDramaContentState();
}

class _ShortDramaContentState extends State<_ShortDramaContent> {
  double? _seekValue;
  Timer? _seekTimer;
  bool _longPressBoost = false;

  DetailController get _dc => widget.detailController;
  PlPlayerController get _pc => _dc.playerController;

  @override
  void initState() {
    super.initState();
    // 详情页 didPushNext 会暂停播放器，这里恢复播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_pc.playerStatus.value.isPlaying) {
        _pc.play(hideControls: false);
      }
    });
  }

  @override
  void dispose() {
    _seekTimer?.cancel();
    if (_longPressBoost) _pc.setLongPressStatus(false);
    super.dispose();
  }

  // ===== 手势 =====

  void _onTap() {
    _pc.controls = !_pc.showControls.value;
  }

  void _onDoubleTapDown(TapDownDetails details) {
    final w = MediaQuery.sizeOf(context).width;
    final x = details.localPosition.dx;
    if (x < w / 3) {
      _pc.onBackward(_pc.fastForBackwardDuration);
    } else if (x > w * 2 / 3) {
      _pc.onForward(_pc.fastForBackwardDuration);
    } else {
      _pc.onDoubleTapCenter();
    }
  }

  void _onLongPressStart(LongPressStartDetails _) {
    if (!_pc.playerStatus.value.isPlaying) return;
    _longPressBoost = true;
    _pc.setLongPressStatus(true);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!_longPressBoost) return;
    _longPressBoost = false;
    _pc.setLongPressStatus(false);
  }

  void _onHorizontalDragStart(DragStartDetails _) {
    if (!_pc.playerStatus.value.isPlaying) return;
    _pc.onChangedSliderStart();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final size = MediaQuery.sizeOf(context);
    final duration = _pc.duration.value;
    if (duration <= Duration.zero) return;
    final base = _seekValue ?? _pc.sliderPosition.inMilliseconds.toDouble();
    final delta = _pc.sliderScale * details.delta.dx / size.width;
    final next = (base + delta).clamp(0.0, duration.inMilliseconds.toDouble());
    setState(() => _seekValue = next);
    _pc.onUpdatedSliderProgress(Duration(milliseconds: next.round()));
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    final target = _seekValue;
    if (target == null) return;
    _pc.seekTo(Duration(milliseconds: target.round()), isSeek: false);
    _pc.onChangedSliderEnd();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _seekValue = null);
    });
  }

  // ===== 面板 =====

  void _showDanmakuSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DanmakuSettings(controller: _dc),
    );
  }

  void _showSettingSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SettingSheet(controller: _dc, isWide: false),
    );
  }

  void _showSpeed() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SpeedSheet(
        speeds: _pc.speedList,
        current: _pc.currentSpeed.value,
        onSelected: (s) {
          _pc.setPlaybackSpeed(s);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showQuality() {
    final qualities = _dc.currentQualities;
    if (qualities.isEmpty) {
      SmartDialog.showToast('暂无可用画质');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QualitySheet(
        qualities: qualities,
        currentUrl: _dc.currentPlayUrl.value,
        onSelected: (q) {
          _dc.switchQuality(q);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  String _qualityLabel() {
    final qualities = _dc.currentQualities;
    if (qualities.isEmpty) return '默认';
    final current = _dc.currentPlayUrl.value;
    return qualities
        .firstWhere(
          (q) => q.url == current,
          orElse: () => qualities.first,
        )
        .label;
  }

  void _showMoreMenu() {
    final colors = Theme.of(context).colorScheme;
    final qualityLabel = _qualityLabel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('缓存当前视频'),
                onTap: () {
                  Navigator.pop(ctx);
                  _dc.cacheCurrentVideo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.high_quality),
                title: const Text('清晰度'),
                subtitle: Text(qualityLabel),
                onTap: () {
                  Navigator.pop(ctx);
                  _showQuality();
                },
              ),
              ListTile(
                leading: const Icon(Icons.subtitles),
                title: const Text('弹幕设置'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDanmakuSettings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('播放设置'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSettingSheet();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== build =====

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        PLVideoPlayer(
          maxWidth: size.width,
          maxHeight: size.height,
          plPlayerController: _pc,
          controllerTag: widget.controllerTag,
          headerControl: const SizedBox.shrink(),
          bottomControl: const SizedBox.shrink(),
          interactive: false,
          danmuWidget: DanmakuView(
            playerController: _pc,
            danmakuController: Get.find<DanmakuController>(),
            size: size,
            isFullScreen: true,
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            onDoubleTapDown: _onDoubleTapDown,
            onDoubleTap: () {},
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: _onLongPressEnd,
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
          ),
        ),
        if (_seekValue != null) _SeekBubble(valueMs: _seekValue!),
        Obx(() {
          final visible = _pc.showControls.value ||
              !_pc.playerStatus.value.isPlaying;
          if (!visible) return const SizedBox.shrink();
          return _ShortDramaOverlay(
            detailController: _dc,
            onShowDanmakuSettings: _showDanmakuSettings,
            onShowSettingSheet: _showSettingSheet,
            onShowSpeed: _showSpeed,
            onShowQuality: _showQuality,
            onShowMore: _showMoreMenu,
          );
        }),
      ],
    );
  }
}

/// 短剧 UI 覆盖层
class _ShortDramaOverlay extends StatelessWidget {
  final DetailController detailController;
  final VoidCallback onShowDanmakuSettings;
  final VoidCallback onShowSettingSheet;
  final VoidCallback onShowSpeed;
  final VoidCallback onShowQuality;
  final VoidCallback onShowMore;

  const _ShortDramaOverlay({
    required this.detailController,
    required this.onShowDanmakuSettings,
    required this.onShowSettingSheet,
    required this.onShowSpeed,
    required this.onShowQuality,
    required this.onShowMore,
  });

  @override
  Widget build(BuildContext context) {
    final dc = detailController;
    final pc = dc.playerController;
    final padding = MediaQuery.paddingOf(context);

    return Stack(
      children: [
        // 顶部栏
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopBar(detailController: dc, topPadding: padding.top),
        ),
        // 右侧按钮（合并成一列）
        Positioned(
          right: 12,
          bottom: padding.bottom + 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Obx(() => _CircleAction(
                    icon: dc.introController.isFavorite.value
                        ? Icons.favorite
                        : Icons.favorite_border,
                    active: dc.introController.isFavorite.value,
                    onTap: () => dc.introController.toggleFavorite(),
                  )),
              _CircleAction(
                icon: Icons.playlist_play,
                onTap: () => dc.showEpisodePanel(),
              ),
              const SizedBox(height: 12),
              Obx(() => _TextAction(
                    text: '${pc.currentSpeed.value}x',
                    onTap: onShowSpeed,
                  )),
              Obx(() => _CircleAction(
                    icon: pc.enableShowDanmaku.value
                        ? Icons.subtitles
                        : Icons.subtitles_off,
                    onTap: () => dc.toggleDanmaku(),
                    onLongPress: onShowDanmakuSettings,
                  )),
              _CircleAction(
                icon: Icons.more_horiz,
                onTap: onShowMore,
              ),
            ],
          ),
        ),
        // 底部：进度 + 上一集 / 播放暂停 / 下一集 / 时间
        Positioned(
          left: 16,
          right: 16,
          bottom: padding.bottom + 16,
          child: _BottomBar(detailController: dc),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final DetailController detailController;
  final double topPadding;

  const _TopBar({required this.detailController, required this.topPadding});

  @override
  Widget build(BuildContext context) {
    final ic = detailController.introController;
    return Container(
      padding: EdgeInsets.fromLTRB(4, topPadding + 4, 12, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Get.back(),
          ),
          Expanded(
            child: Obx(() {
              final name = ic.videoDetail.value?.vodName ?? '';
              final idx = ic.currentEpisodeIndex.value + 1;
              final total = ic.displayEpisodes.length;
              return Text(
                '$name · 第 $idx 集 / 共 $total 集',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final DetailController detailController;

  const _BottomBar({required this.detailController});

  @override
  Widget build(BuildContext context) {
    final dc = detailController;
    final pc = dc.playerController;
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 进度条（复用 PlPlayerController 的滑块回调）
        Obx(() {
          final dur = pc.duration.value;
          if (dur <= Duration.zero) return const SizedBox(height: 32);
          final max = dur.inMilliseconds.toDouble();
          final pos = pc.sliderPosition.inMilliseconds.toDouble();
          return SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: colors.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: colors.primary,
            ),
            child: Slider(
              value: pos.clamp(0.0, max),
              max: max,
              onChangeStart: (_) => pc.onChangedSliderStart(),
              onChanged: (v) =>
                  pc.onUpdatedSliderProgress(Duration(milliseconds: v.round())),
              onChangeEnd: (v) {
                pc.seekTo(Duration(milliseconds: v.round()), isSeek: false);
                pc.onChangedSliderEnd();
              },
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          children: [
            _IconBtn(
              icon: Icons.skip_previous,
              onTap: () => dc.playPrev(),
            ),
            const SizedBox(width: 8),
            Obx(() => _IconBtn(
                  icon: pc.playerStatus.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                  size: 48,
                  onTap: pc.onDoubleTapCenter,
                )),
            const SizedBox(width: 8),
            _IconBtn(
              icon: Icons.skip_next,
              onTap: () => dc.playNext(),
            ),
            const Spacer(),
            Obx(() {
              final pos =
                  DurationUtils.formatDuration(pc.positionSeconds.value);
              final dur =
                  DurationUtils.formatDuration(pc.duration.value.inSeconds);
              return Text(
                '$pos / $dur',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              );
            }),
          ],
        ),
      ],
    );
  }
}

// ===== 通用小组件 =====

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _CircleAction({
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 24,
            color: active ? colors.primary : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _TextAction({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        iconSize: size * 0.65,
        padding: EdgeInsets.zero,
        onPressed: onTap,
      ),
    );
  }
}

class _SeekBubble extends StatelessWidget {
  final double valueMs;
  const _SeekBubble({required this.valueMs});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          DurationUtils.formatDuration((valueMs / 1000).round()),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _SpeedSheet extends StatelessWidget {
  final List<double> speeds;
  final double current;
  final ValueChanged<double> onSelected;

  const _SpeedSheet({
    required this.speeds,
    required this.current,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '倍速',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in speeds)
                _Pill(
                  label: '${s}x',
                  selected: (s - current).abs() < 0.01,
                  onTap: () => onSelected(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualitySheet extends StatelessWidget {
  final List<PlayQuality> qualities;
  final String currentUrl;
  final ValueChanged<PlayQuality> onSelected;

  const _QualitySheet({
    required this.qualities,
    required this.currentUrl,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '清晰度',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in qualities)
                _Pill(
                  label: q.label,
                  selected: q.url == currentUrl,
                  onTap: () => onSelected(q),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? colors.onPrimary : colors.onSurface,
          ),
        ),
      ),
    );
  }
}