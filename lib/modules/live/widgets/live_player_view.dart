// lib/modules/live/widgets/live_player_view.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart' show NoVideoControls, Video;
import 'package:yuanying/modules/live/controllers/live_controller.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/plugin/pl_player/models/video_fit_type.dart';
import 'package:yuanying/plugin/pl_player/widgets/common_btn.dart';

/// 手势类型
enum _GestureType {
  none,
  left,   // 左侧：亮度
  right,  // 右侧：音量
}

class LivePlayerView extends StatefulWidget {
  final bool isFullScreen;

  const LivePlayerView({
    super.key,
    this.isFullScreen = false,
  });

  @override
  State<LivePlayerView> createState() => _LivePlayerViewState();
}

class _LivePlayerViewState extends State<LivePlayerView> {
  // ===== 手势状态 =====
  _GestureType _gestureType = _GestureType.none;
  Offset? _initialFocalPoint;

  // ===== 指示器隐藏定时器 =====
  Timer? _indicatorTimer;

  // ===== 指示器显隐状态 =====
  final RxBool _showVolumeIndicator = false.obs;
  final RxBool _showBrightnessIndicator = false.obs;

  LiveController get ctrl => Get.find<LiveController>(tag: 'live');

  @override
  void dispose() {
    _indicatorTimer?.cancel();
    super.dispose();
  }

  // ===== 显示指示器并重置定时器 =====
  void _showIndicator({required bool volume, required bool brightness}) {
    _indicatorTimer?.cancel();
    if (volume) {
      _showVolumeIndicator.value = true;
      _showBrightnessIndicator.value = false;
    } else if (brightness) {
      _showBrightnessIndicator.value = true;
      _showVolumeIndicator.value = false;
    } else {
      _showVolumeIndicator.value = false;
      _showBrightnessIndicator.value = false;
      return;
    }
    // 1.5 秒后自动隐藏
    _indicatorTimer = Timer(const Duration(milliseconds: 1500), () {
      _showVolumeIndicator.value = false;
      _showBrightnessIndicator.value = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ===== 读取刘海安全区 =====
    // 移动端全屏不做 EnterNativeFullscreen，viewPadding 始终正常上报，
    // 直接读即可。叠加到按钮位置做刘海避让。
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final double leftSafe = viewPadding.left;
    final double rightSafe = viewPadding.right;
    final double bottomSafe = viewPadding.bottom;

    Widget playerContent = Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ===== 视频渲染层 =====
          if (ctrl.videoController != null)
            Obx(() => Video(
              controller: ctrl.videoController!,
              controls: NoVideoControls,
              fit: ctrl.videoFit.value.boxFit,
            )),

          // ===== 加载/缓冲指示 =====
          Obx(() {
            if (ctrl.isLoading.value || ctrl.isBuffering.value) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            return const SizedBox.shrink();
          }),

          // ===== 空状态 =====
          Obx(() {
            if (ctrl.channels.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tv_off, size: 48, color: Colors.white54),
                    const SizedBox(height: 8),
                    Text(
                      '暂无频道',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          }),

          // ===== 底部自定义控制栏 =====
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.isFullScreen ? 0 : bottomSafe),
              child: _buildControls(),
            ),
          ),

          // ===== 音量指示器 =====
          Obx(() {
            return AnimatedOpacity(
              opacity: _showVolumeIndicator.value ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: const BoxDecoration(
                      color: Color(0x88000000),
                      borderRadius: BorderRadius.all(Radius.circular(64)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          ctrl.volume.value == 0.0
                              ? Icons.volume_off
                              : ctrl.volume.value < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                          color: Colors.white,
                          size: 20.0,
                        ),
                        const SizedBox(width: 2.0),
                        Text(
                          '${(ctrl.volume.value * 100.0).round()}%',
                          style: const TextStyle(fontSize: 13.0, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // ===== 亮度指示器 =====
          Obx(() {
            return AnimatedOpacity(
              opacity: _showBrightnessIndicator.value ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: const BoxDecoration(
                      color: Color(0x88000000),
                      borderRadius: BorderRadius.all(Radius.circular(64)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          ctrl.brightness.value < 1.0 / 3.0
                              ? Icons.brightness_low
                              : ctrl.brightness.value < 2.0 / 3.0
                              ? Icons.brightness_medium
                              : Icons.brightness_high,
                          color: Colors.white,
                          size: 18.0,
                        ),
                        const SizedBox(width: 2.0),
                        Text(
                          '${(ctrl.brightness.value * 100.0).round()}%',
                          style: const TextStyle(fontSize: 13.0, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // ===== 锁屏按钮（左侧垂直居中） =====
          //
          // 交互设计：
          //   - 非锁屏 + 控制栏可见：显示"锁定"图标
          //   - 锁屏：显示"解锁"图标且常显
          //   - 非全屏：不显示
          //
          // 安全区适配：叠加 viewPadding.left，
          // iOS 横屏刘海在左侧时 16 + leftSafe 能正确避让。
          Obx(() {
            if (!ctrl.isFullScreen.value) return const SizedBox.shrink();
            final isLocked = ctrl.controlsLock.value;
            final visible = isLocked || ctrl.controlsVisible.value;
            if (!visible) return const SizedBox.shrink();

            return Positioned(
              left: 16 + leftSafe,
              top: 0,
              bottom: 0,
              child: Center(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0x45000000),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  child: ComBtn(
                    tooltip: isLocked ? '解锁' : '锁定',
                    icon: Icon(
                      isLocked ? Icons.lock : Icons.lock_open,
                      size: 20,
                      color: Colors.white,
                    ),
                    onTap: ctrl.toggleControlsLock,
                  ),
                ),
              ),
            );
          }),

          // ===== 截图 / 旋转屏幕按钮（右侧垂直居中） =====
          //
          // 交互设计：
          //   - 非全屏：不显示
          //   - 锁屏：只显示"截图"
          //   - 非锁屏 + 控制栏可见：截图 + 旋转（移动端）
          //   - 非锁屏 + 控制栏隐藏：不显示
          //
          // 安全区适配：叠加 viewPadding.right，
          // iOS 横屏刘海在右侧时能正确避让，不被遮挡。
          Obx(() {
            if (!ctrl.isFullScreen.value) return const SizedBox.shrink();

            final bool isLocked = ctrl.controlsLock.value;
            final bool showScreenshot = isLocked || ctrl.controlsVisible.value;
            final bool showRotate = !isLocked &&
                ctrl.controlsVisible.value &&
                PlatformUtils.isMobile;

            if (!showScreenshot && !showRotate) {
              return const SizedBox.shrink();
            }

            return Positioned(
              right: 16 + rightSafe,
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 旋转屏幕（仅移动端，非锁屏时显示）
                    if (showRotate) ...[
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0x45000000),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: ComBtn(
                          tooltip: '旋转屏幕',
                          icon: const Icon(
                            Icons.screen_rotation,
                            size: 20,
                            color: Colors.white,
                          ),
                          onTap: () => ctrl.toggleOrientation(Get.context!),
                        ),
                      ),
                      // 两按钮之间的垂直间距
                      const SizedBox(height: 8),
                    ],
                    // 截图（锁屏时常显；非锁屏时跟随控制栏）
                    if (showScreenshot)
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0x45000000),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: ComBtn(
                          tooltip: '截图',
                          icon: const Icon(
                            Icons.photo_camera,
                            size: 20,
                            color: Colors.white,
                          ),
                          onTap: ctrl.takeScreenshot,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );

    // ===== 手势 + 鼠标交互 =====
    if (PlatformUtils.isDesktop) {
      playerContent = MouseRegion(
        cursor: SystemMouseCursors.basic,
        onEnter: (_) => ctrl.showControls(),
        onHover: (_) => ctrl.showControls(),
        onExit: (_) => ctrl.hideControls(),
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            onTap: _onTap,
            onDoubleTap: _onDoubleTapDesktop,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: playerContent,
          ),
        ),
      );
    } else {
      playerContent = GestureDetector(
        onTap: _onTap,
        onDoubleTap: _onDoubleTapMobile,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: playerContent,
      );
    }

    return playerContent;
  }

  // ============================================================
  // 底部控制栏构建
  // ============================================================

  Widget _buildControls() {
    return Obx(() {
      // 锁屏状态下隐藏整个底部控制栏
      if (ctrl.controlsLock.value) {
        return const SizedBox.shrink();
      }
      return AnimatedOpacity(
        opacity: ctrl.controlsVisible.value ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: IgnorePointer(
          ignoring: !ctrl.controlsVisible.value,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.7), Colors.transparent],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildProgressRow(),
                const SizedBox(height: 4),
                _buildButtonRow(),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildProgressRow() {
    final colorScheme = Theme.of(Get.context!).colorScheme;

    return Row(
      children: [
        Obx(() => Text(
          ctrl.formatDuration(ctrl.position.value),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        )),
        const SizedBox(width: 8),
        Expanded(
          child: Obx(() {
            final dur = ctrl.duration.value;
            final pos = ctrl.position.value;
            final double max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
            final double value = pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble();

            return Container(
              height: 3.5,
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(width: 8),
        Obx(() => Text(
          ctrl.formatDuration(ctrl.duration.value),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        )),
      ],
    );
  }

  Widget _buildButtonRow() {
    return Row(
      children: [
        Obx(() => IconButton(
          icon: Icon(
            ctrl.isPlaying.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 22,
          ),
          onPressed: ctrl.togglePlayPause,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        )),
        const SizedBox(width: 8),

        Obx(() => Expanded(
          child: Text(
            ctrl.currentChannel.value?.name ?? '未选择频道',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        )),

        // 画面比例下拉菜单
        //
        // 说明：
        //   全屏改为 PageRoute 后，此按钮弹出的菜单会进入
        //   当前 Navigator 的 Overlay，天然位于全屏页面之上。
        Obx(() => PopupMenuButton<VideoFitType>(
          tooltip: '画面比例',
          requestFocus: false,
          initialValue: ctrl.videoFit.value,
          color: Colors.black.withOpacity(0.8),
          onSelected: ctrl.setVideoFit,
          itemBuilder: (context) {
            final fits = [
              VideoFitType.contain,
              VideoFitType.fill,
              VideoFitType.cover,
              VideoFitType.fitWidth,
              VideoFitType.fitHeight,
            ];
            return fits.map((fit) => PopupMenuItem<VideoFitType>(
              height: 35,
              padding: const EdgeInsets.only(left: 30),
              value: fit,
              child: Text(
                fit.desc,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            )).toList();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              ctrl.videoFit.value.desc,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        )),

        Obx(() => IconButton(
          icon: Icon(
            ctrl.isFullScreen.value ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            color: Colors.white,
            size: 22,
          ),
          onPressed: () => ctrl.toggleFullScreen(Get.context!),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: ctrl.isFullScreen.value ? '退出全屏' : '全屏',
        )),
      ],
    );
  }

  // ============================================================
  // 手势事件处理
  // ============================================================

  /// 单击：控制栏隐藏时显示；控制栏显示时切换播放/暂停
  void _onTap() {
    // 锁屏状态：点击屏幕不做任何事（解锁按钮常显，用户直接点它）
    if (ctrl.controlsLock.value) return;

    if (ctrl.controlsVisible.value) {
      // 控制栏已显示：切换播放/暂停
      ctrl.togglePlayPause();
    } else {
      // 控制栏隐藏：显示控制栏
      ctrl.showControls();
    }
  }

  /// 移动端双击：播放/暂停
  void _onDoubleTapMobile() {
    if (ctrl.controlsLock.value) return;
    ctrl.togglePlayPause();
    ctrl.showControls();
  }

  /// 桌面端双击：全屏切换
  void _onDoubleTapDesktop() {
    if (ctrl.controlsLock.value) return;
    ctrl.toggleFullScreen(Get.context!);
  }

  void _onPanStart(DragStartDetails details) {
    // 锁屏状态下禁用手势
    if (ctrl.controlsLock.value) return;
    _gestureType = _GestureType.none;
    _initialFocalPoint = details.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // 锁屏状态下禁用手势
    if (ctrl.controlsLock.value) return;

    final size = MediaQuery.sizeOf(Get.context!);
    final maxHeight = size.height;

    if (_gestureType == _GestureType.none && _initialFocalPoint != null) {
      final delta = details.localPosition - _initialFocalPoint!;
      if (delta.distanceSquared < 1) return;

      final dx = delta.dx.abs();
      final dy = delta.dy.abs();
      if (dy > dx) {
        final tapPosition = _initialFocalPoint!.dx;
        final sectionWidth = size.width / 3;
        if (tapPosition < sectionWidth) {
          _gestureType = _GestureType.left;
        } else if (tapPosition > sectionWidth * 2) {
          _gestureType = _GestureType.right;
        } else {
          return;
        }
      } else {
        return;
      }
    }

    switch (_gestureType) {
      case _GestureType.left:
        final double level = maxHeight * 3;
        final double currentBrightness = ctrl.brightness.value < 0 ? 0.5 : ctrl.brightness.value;
        final double newBrightness = (currentBrightness - details.delta.dy / level).clamp(0.0, 1.0);
        ctrl.setBrightness(newBrightness);
        _showIndicator(brightness: true, volume: false);
        break;

      case _GestureType.right:
        final double level = maxHeight * 0.5;
        final double newVolume = (ctrl.volume.value - details.delta.dy / level).clamp(0.0, 2.0);
        ctrl.setVolume(newVolume);
        _showIndicator(brightness: false, volume: true);
        break;

      case _GestureType.none:
        break;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _gestureType = _GestureType.none;
    _initialFocalPoint = null;
    // 不立即隐藏指示器，让定时器管理
  }

  // 桌面端滚轮调节音量
  void _onPointerSignal(PointerSignalEvent event) {
    // 锁屏状态下禁用滚轮调音
    if (ctrl.controlsLock.value) return;

    if (event is PointerScrollEvent) {
      final offset = -event.scrollDelta.dy / 4000;
      final newVolume = (ctrl.volume.value + offset).clamp(0.0, 2.0);
      ctrl.setVolume(newVolume);
      // 滚轮调节音量时显示指示器
      _showIndicator(brightness: false, volume: true);
    }
  }
}