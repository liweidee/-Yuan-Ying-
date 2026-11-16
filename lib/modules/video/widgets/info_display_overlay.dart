import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

/// 全屏信息层：常驻显示电量 / 时间 / 帧率 / 分辨率 / 播放进度 / 网速
///
/// 由 `view.dart` 在全屏时挂载。内部 `IgnorePointer` 保证不拦截点击。
/// 每秒刷新时间，位置变更通过 `PlayerPref.*Position` 读取。
class InfoDisplayOverlay extends StatefulWidget {
  final PlPlayerController playerController;
  const InfoDisplayOverlay({super.key, required this.playerController});

  @override
  State<InfoDisplayOverlay> createState() => _InfoDisplayOverlayState();
}

class _InfoDisplayOverlayState extends State<InfoDisplayOverlay> {
  static const double _padding = 12;
  static const double _spacing = 4;

  late final RxString _clock;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clock = _fmtClock(DateTime.now()).obs;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _clock.value = _fmtClock(DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String _fmtClock(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Obx(() {
        // 依赖读取：任何一个 Rx 变化都会重建，保证实时刷新
        final now = _clock.value;
        final c = widget.playerController;
        final bat = c.batteryLevel.value;
        final fps = c.videoFps.value;
        final vw = c.videoWidth.value;
        final vh = c.videoHeight.value;
        final pos = c.positionSeconds.value;
        final dur = c.duration.value.inSeconds;
        final sp = c.downloadSpeed.value;

        final groups = <int, List<String>>{1: [], 2: [], 3: [], 4: []};

        // 固定堆叠顺序：时间 → 电量 → 帧率 → 分辨率 → 播放进度 → 网速
        void addIf(int pos, String text) {
          if (pos != 0) groups[pos]!.add(text);
        }

        addIf(PlayerPref.infoTimePosition, now);
        addIf(PlayerPref.batteryPosition, bat);

        if (PlayerPref.infoFpsPosition != 0) {
          addIf(PlayerPref.infoFpsPosition,
              fps > 0 ? '${fps.toStringAsFixed(2)} fps' : '-- fps');
        }

        if (PlayerPref.infoResolutionPosition != 0) {
          addIf(PlayerPref.infoResolutionPosition,
              (vw > 0 && vh > 0) ? '${vw}x$vh' : '--');
        }

        if (PlayerPref.infoProgressPosition != 0) {
          addIf(PlayerPref.infoProgressPosition,
              '${_fmtDuration(pos)} / ${_fmtDuration(dur)}');
        }

        if (PlayerPref.infoSpeedPosition != 0) {
          if (sp > 1024) {
            addIf(
              PlayerPref.infoSpeedPosition,
              sp >= 1024 * 1024
                  ? '${(sp / (1024 * 1024)).toStringAsFixed(1)} MB/s'
                  : '${(sp / 1024).toStringAsFixed(0)} KB/s',
            );
          } else {
            addIf(PlayerPref.infoSpeedPosition, '-- KB/s');
          }
        }

        final hasAny = groups.values.any((l) => l.isNotEmpty);
        if (!hasAny) return const SizedBox.shrink();

        Widget col(List<String> items, CrossAxisAlignment align) {
          if (items.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: align,
            mainAxisSize: MainAxisSize.min,
            children: items
                .map((t) => Padding(
                      padding: EdgeInsets.only(bottom: _spacing),
                      child: _InfoBadge(text: t),
                    ))
                .toList(),
          );
        }

        return Stack(
          children: [
            Positioned(
              left: _padding,
              top: _padding,
              child: col(groups[1]!, CrossAxisAlignment.start),
            ),
            Positioned(
              right: _padding,
              top: _padding,
              child: col(groups[2]!, CrossAxisAlignment.end),
            ),
            Positioned(
              left: _padding,
              bottom: _padding,
              child: col(groups[3]!, CrossAxisAlignment.start),
            ),
            Positioned(
              right: _padding,
              bottom: _padding,
              child: col(groups[4]!, CrossAxisAlignment.end),
            ),
          ],
        );
      }),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String text;
  const _InfoBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    // 样式：0=无底 / 1=黑底 / 2=黑底+阴影
    // 通过 PlayerPref.infoBadgeStyle 读取，外层 Obx 每秒因 _clock 变化
    // 会重建，样式变更后最多 1 秒内生效。
    final style = PlayerPref.infoBadgeStyle;
    final hasBg = style != 0;
    final hasShadow = style == 2;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: hasBg
          ? BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.2,
          shadows: hasShadow
              ? const [
                  Shadow(
                    color: Colors.black87,
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}