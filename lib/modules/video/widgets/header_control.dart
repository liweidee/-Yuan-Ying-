import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/common/widgets/custom_icon.dart';
import 'package:yuanying/common/widgets/marquee.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/modules/video/widgets/setting_sheet.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/plugin/pl_player/models/data_status.dart';

class HeaderControl extends StatefulWidget {
  final String controllerTag;
  const HeaderControl({super.key, required this.controllerTag});

  @override
  State<HeaderControl> createState() => _HeaderControlState();
}

class _HeaderControlState extends State<HeaderControl> {
  late final DetailController controller;
  late final PlPlayerController playerController;

  final _titleKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    controller = Get.find<DetailController>(tag: widget.controllerTag);
    playerController = controller.playerController;
  }

  // @override
  // Widget build(BuildContext context) {
  //   final title = controller.introController.videoDetail.value?.vodName ?? '';

  //   return Container(
  //     height: 56,
  //     padding: const EdgeInsets.symmetric(horizontal: 8),
  //     decoration: const BoxDecoration(
  //       gradient: LinearGradient(
  //         begin: Alignment.topCenter,
  //         end: Alignment.bottomCenter,
  //         colors: [Colors.black54, Colors.transparent],
  //       ),
  //     ),
  //     child: Row(
  //       children: [
  //         // 返回按钮
  //         SizedBox(
  //           width: 40,
  //           height: 34,
  //           child: IconButton(
  //             tooltip: '返回',
  //             style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
  //             icon: const Icon(
  //               FontAwesomeIcons.arrowLeft,
  //               size: 15,
  //               color: Colors.white,
  //             ),
  //             onPressed: () => playerController.onPopInvokedWithResult(false, null),
  //           ),
  //         ),
  //         // 返回主页按钮
  //         SizedBox(
  //           width: 40,
  //           height: 34,
  //           child: IconButton(
  //             tooltip: '返回主页',
  //             style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
  //             icon: const Icon(
  //               FontAwesomeIcons.house,
  //               size: 15,
  //               color: Colors.white,
  //             ),
  //             onPressed: playerController.onCloseAll,
  //           ),
  //         ),
  //         // 标题（Marquee滚动）
  //         Expanded(
  //           child: Padding(
  //             key: _titleKey,
  //             padding: const EdgeInsets.only(right: 10),
  //             child: MarqueeText(
  //               title,
  //               spacing: 30,
  //               velocity: 30,
  //               style: const TextStyle(
  //                 color: Colors.white,
  //                 fontSize: 16,
  //                 fontWeight: FontWeight.w500,
  //               ),
  //               provider: ContextSingleTicker(context, autoStart: () => true),
  //             ),
  //           ),
  //         ),
  //         // 内核切换按钮（桌面端显示）
  //         PopupMenuButton<PlayerEngineType>(
  //           tooltip: '切换播放内核',
  //           offset: const Offset(0, 40),
  //           color: Colors.black.withOpacity(0.8),
  //           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  //           initialValue: PlayerPref.playerEngine,
  //           itemBuilder: (context) => [
  //             PopupMenuItem<PlayerEngineType>(
  //               value: PlayerEngineType.mediaKit,
  //               child: Row(
  //                 children: [
  //                   Text('MPV', style: const TextStyle(color: Colors.white, fontSize: 13)),
  //                   if (PlayerPref.playerEngine == PlayerEngineType.mediaKit)
  //                     const Spacer(),
  //                   if (PlayerPref.playerEngine == PlayerEngineType.mediaKit)
  //                     Icon(Icons.check, color: Colors.white, size: 16),
  //                 ],
  //               ),
  //             ),
  //             PopupMenuItem<PlayerEngineType>(
  //               value: PlayerEngineType.fvp,
  //               child: Row(
  //                 children: [
  //                   Text('MDK', style: const TextStyle(color: Colors.white, fontSize: 13)),
  //                   if (PlayerPref.playerEngine == PlayerEngineType.fvp)
  //                     const Spacer(),
  //                   if (PlayerPref.playerEngine == PlayerEngineType.fvp)
  //                     Icon(Icons.check, color: Colors.white, size: 16),
  //                 ],
  //               ),
  //             ),
  //           ],
  //           onSelected: (newType) => _switchEngine(newType),
  //           child: SizedBox(
  //             width: 60,
  //             child: Row(
  //               mainAxisSize: MainAxisSize.min,
  //               mainAxisAlignment: MainAxisAlignment.center,
  //               children: [
  //                 Icon(
  //                   Icons.play_arrow,
  //                   size: 14,
  //                   color: Colors.white,
  //                 ),
  //                 const SizedBox(width: 4),
  //                 Text(
  //                   PlayerPref.playerEngine == PlayerEngineType.fvp ? 'MDK' : 'MPV',
  //                   style: const TextStyle(
  //                     color: Colors.white,
  //                     fontSize: 11,
  //                     fontWeight: FontWeight.w500,
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ),
  //         ),
          
  //         // 画中画按钮（仅在桌面端且非 FVP 引擎时显示）
  //         if (PlatformUtils.isDesktop && PlayerPref.playerEngine != PlayerEngineType.fvp)
  //           SizedBox(
  //             width: 40,
  //             height: 34,
  //             child: Obx(() {
  //               return IconButton(
  //                 tooltip: playerController.isDesktopPip ? '退出画中画' : '画中画',
  //                 style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
  //                 onPressed: () {
  //                   if (playerController.isDesktopPip) {
  //                     playerController.exitDesktopPip();
  //                   } else {
  //                     playerController.enterDesktopPip();
  //                   }
  //                 },
  //                 icon: Icon(
  //                   playerController.isDesktopPip
  //                       ? Icons.picture_in_picture_alt
  //                       : Icons.picture_in_picture_outlined,
  //                   size: 19,
  //                   color: Colors.white,
  //                 ),
  //               );
  //             }),
  //           ),
  //         // 投屏按钮
  //         SizedBox(
  //           width: 40,
  //           height: 34,
  //           child: IconButton(
  //             tooltip: '投屏',
  //             style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
  //             onPressed: controller.onCast,
  //             icon: const Icon(
  //               Icons.cast,
  //               size: 19,
  //               color: Colors.white,
  //             ),
  //           ),
  //         ),
  //         // 弹幕开关
  //         SizedBox(
  //           width: 40,
  //           height: 34,
  //           child: Obx(() {
  //             final enable = playerController.enableShowDanmaku.value;
  //             return IconButton(
  //               tooltip: enable ? '关闭弹幕' : '开启弹幕',
  //               style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
  //               onPressed: controller.toggleDanmaku,
  //               icon: Icon(
  //                 enable ? CustomIcons.dm_on : CustomIcons.dm_off,
  //                 size: 20,
  //                 color: Colors.white,
  //               ),
  //             );
  //           }),
  //         ),
  //         // 更多设置按钮
  //         SizedBox(
  //           width: 40,
  //           height: 34,
  //           child: IconButton(
  //             tooltip: '更多设置',
  //             style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
  //             onPressed: () => _showSettingSheet(context),
  //             icon: const Icon(
  //               Icons.more_vert_outlined,
  //               size: 19,
  //               color: Colors.white,
  //             ),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<DetailController>(tag: widget.controllerTag);
    final playerController = controller.playerController;

    return Obx(() {
      final w = playerController.videoWidth.value;
      final h = playerController.videoHeight.value;
      final speed = playerController.downloadSpeed.value;
      final isFvpEngine = PlayerPref.playerEngine == PlayerEngineType.fvp;

      // ---- 构建显示内容 ----
      String resolution = '';
      String speedText = '';

      // 分辨率：只有 > 0 时才显示
      if (w > 0 && h > 0) {
        resolution = '${w}x$h';
      }

      // 网速：只有非 FVP 且速度 > 1KB/s 时才显示
      if (!isFvpEngine && speed > 1024) {
        speedText = speed >= 1024 * 1024
            ? '${(speed / (1024 * 1024)).toStringAsFixed(1)}MB/s'
            : '${(speed / 1024).toStringAsFixed(1)}KB/s';
      }

      // 拼接显示文本
      String info = '';
      if (resolution.isNotEmpty) {
        info = resolution;
        if (speedText.isNotEmpty) {
          info += '  $speedText';
        }
      }

      return Container(
        height: 68, // 固定高度，永不变化
        padding: const EdgeInsets.only(top: 10, left: 8, right: 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // ---- 第一行：所有原有按钮（完全不变） ----
            Row(
              children: [
                // 返回按钮
                SizedBox(
                  width: 40,
                  height: 34,
                  child: IconButton(
                    tooltip: '返回',
                    style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
                    icon: const Icon(FontAwesomeIcons.arrowLeft, size: 15, color: Colors.white),
                    onPressed: () {
                      if (playerController.isDesktopPip) {
                        playerController.exitDesktopPip();
                      } else {
                        playerController.onPopInvokedWithResult(false, null);
                      }
                    },
                  ),
                ),
                // 返回首页按钮（非画中画模式下显示）
                if (!playerController.isDesktopPip)
                  SizedBox(
                    width: 40,
                    height: 34,
                    child: IconButton(
                      tooltip: '返回主页',
                      style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
                      icon: const Icon(
                        FontAwesomeIcons.house,
                        size: 15,
                        color: Colors.white,
                      ),
                      onPressed: playerController.onCloseAll,
                    ),
                  ),
                // 标题（Marquee）
                Expanded(
                  child: Padding(
                    key: _titleKey,
                    padding: const EdgeInsets.only(right: 10),
                    child: MarqueeText(
                      controller.introController.videoDetail.value?.vodName ?? '',
                      spacing: 30,
                      velocity: 30,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      provider: ContextSingleTicker(context, autoStart: () => true),
                    ),
                  ),
                ),
                // 内核切换
                PopupMenuButton<PlayerEngineType>(
                  tooltip: '切换播放内核',
                  offset: const Offset(0, 40),
                  color: Colors.black.withOpacity(0.8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  initialValue: PlayerPref.playerEngine,
                  itemBuilder: (context) => [
                    PopupMenuItem<PlayerEngineType>(
                      value: PlayerEngineType.mediaKit,
                      child: Row(
                        children: [
                          Text('MPV', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          if (PlayerPref.playerEngine == PlayerEngineType.mediaKit) const Spacer(),
                          if (PlayerPref.playerEngine == PlayerEngineType.mediaKit)
                            const Icon(Icons.check, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                    PopupMenuItem<PlayerEngineType>(
                      value: PlayerEngineType.fvp,
                      child: Row(
                        children: [
                          Text('MDK', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          if (PlayerPref.playerEngine == PlayerEngineType.fvp) const Spacer(),
                          if (PlayerPref.playerEngine == PlayerEngineType.fvp)
                            const Icon(Icons.check, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (newType) => _switchEngine(newType),
                  child: SizedBox(
                    width: 60,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_arrow, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          PlayerPref.playerEngine == PlayerEngineType.fvp ? 'MDK' : 'MPV',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 画中画（桌面且非FVP）
                if (PlatformUtils.isDesktop && PlayerPref.playerEngine != PlayerEngineType.fvp)
                  SizedBox(
                    width: 40,
                    height: 34,
                    child: Obx(() {
                      return IconButton(
                        tooltip: playerController.isDesktopPip ? '退出画中画' : '画中画',
                        style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
                        onPressed: () {
                          if (playerController.isDesktopPip) {
                            playerController.exitDesktopPip();
                          } else {
                            playerController.enterDesktopPip();
                          }
                        },
                        icon: Icon(
                          playerController.isDesktopPip
                              ? Icons.picture_in_picture_alt
                              : Icons.picture_in_picture_outlined,
                          size: 19,
                          color: Colors.white,
                        ),
                      );
                    }),
                  ),
                // 投屏
                SizedBox(
                  width: 40,
                  height: 34,
                  child: IconButton(
                    tooltip: '投屏',
                    style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
                    onPressed: controller.onCast,
                    icon: const Icon(Icons.cast, size: 19, color: Colors.white),
                  ),
                ),
                // 弹幕开关
                SizedBox(
                  width: 40,
                  height: 34,
                  child: Obx(() {
                    final enable = playerController.enableShowDanmaku.value;
                    return IconButton(
                      tooltip: enable ? '关闭弹幕' : '开启弹幕',
                      style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
                      onPressed: controller.toggleDanmaku,
                      icon: Icon(
                        enable ? CustomIcons.dm_on : CustomIcons.dm_off,
                        size: 20,
                        color: Colors.white,
                      ),
                    );
                  }),
                ),
                // 更多设置
                SizedBox(
                  width: 40,
                  height: 34,
                  child: IconButton(
                    tooltip: '更多设置',
                    style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
                    onPressed: () => _showSettingSheet(context),
                    icon: const Icon(Icons.more_vert_outlined, size: 19, color: Colors.white),
                  ),
                ),
              ],
            ),
            // ---- 第二行：固定高度占位，有内容时显示 ----
            SizedBox(
              height: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: info.isNotEmpty
                      ? Text(
                          info,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showSettingSheet(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 800;

    if (isWide) {
      // 固定右侧宽度 400px（与内容区一致）
      const double rightWidth = 400.0;

      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: '更多设置',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          final padding = MediaQuery.viewPaddingOf(context);
          final availableHeight = size.height - padding.top - padding.bottom;

          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: rightWidth,
                height: availableHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: SettingSheet(controller: controller, isWide: true),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
      );
    } else {
      // 移动端保持不变
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => SettingSheet(controller: controller, isWide: false),
      );
    }
  }

  void _switchEngine(PlayerEngineType newType) async {
    final current = PlayerPref.playerEngine;
    if (newType == current) {
      SmartDialog.showToast('已是当前内核');
      return;
    }

    SmartDialog.showLoading(msg: '切换内核中...');

    try {
      if (playerController.playerStatus.value.isPlaying) {
        await playerController.pause();
      }
      // 重置状态
      playerController.dataStatus.value = DataStatus.none;
      
      await playerController.switchEngine(newType);
      
      // 重新加载当前剧集（重新请求播放地址）
      await controller.reloadCurrentEpisode();

      // 通知详情页 Obx 重新收集 isFullScreen 依赖
      controller.engineSwitchNotifier.value++;
      
      if (mounted) setState(() {});
      SmartDialog.dismiss();
      SmartDialog.showToast('已切换到 ${newType == PlayerEngineType.fvp ? 'MDK' : 'MPV'} 内核');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('切换失败: $e');
    }
  }
}