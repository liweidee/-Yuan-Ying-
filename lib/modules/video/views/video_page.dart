import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yuanying/common/widgets/custom_icon.dart';
import 'dart:io' show Platform;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/modules/danmaku/controllers/danmaku_controller.dart';
import 'package:yuanying/modules/danmaku/widgets/danmaku_view.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/modules/video/controllers/intro_controller.dart';
import 'package:yuanying/modules/video/widgets/header_control.dart';
import 'package:yuanying/modules/video/widgets/introduction/intro_view.dart';
import 'package:yuanying/plugin/pl_player/view.dart';
import 'package:yuanying/plugin/pl_player/models/data_status.dart';
import 'package:yuanying/modules/push/views/push_dialog.dart';
import 'package:yuanying/common/widgets/route_aware_mixin.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/modules/common/mixins/common_slide_mixin.dart';
import 'package:yuanying/modules/video/widgets/recommend_tab.dart';
import 'package:yuanying/modules/video/widgets/search_tab.dart';
import 'package:yuanying/plugin/pl_player/utils/fullscreen.dart';
import 'package:yuanying/common/widgets/sliver/sliver_pinned_dynamic_header.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:yuanying/common/widgets/flutter/pop_scope.dart';
import 'package:yuanying/common/assets.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/services/silence_keeper.dart';
import 'package:yuanying/utils/ios_pip_helper.dart';

class DetailPage extends CommonSlidePage {
  const DetailPage({super.key, super.enableSlide = true});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage>
    with RouteAware, RouteAwareMixin, TickerProviderStateMixin, CommonSlideMixin<DetailPage> {
  late final String _controllerTag;
  late final DetailController controller;

  /// 记录进入子路由前视频是否在播放，用于返回时决定是否自动恢复
  bool _wasPlayingBeforePush = false;

  final GlobalKey _videoPlayerKey = GlobalKey();
  final GlobalKey<ExtendedNestedScrollViewState> _scrollKey = GlobalKey();

  late bool isPortrait;
  late double maxWidth;
  late double maxHeight;
  late EdgeInsets padding;
  late ThemeData themeData;

  bool get isFullScreen => controller.playerController.isFullScreen.value;

  @override
  void initState() {
      super.initState();

      // ===== 主动停止音乐播放，让视频独占音频会话 =====
      _stopMusicForVideo();

      final args = Get.arguments as Map?;
      _controllerTag = args?['_controllerTag'] as String? ??
          'detail_${DateTime.now().millisecondsSinceEpoch}';

      if (Get.isRegistered<DetailController>(tag: _controllerTag)) {
        controller = Get.find<DetailController>(tag: _controllerTag);
      } else {
        controller = Get.put(DetailController(tag: _controllerTag), tag: _controllerTag);
      }
      controller.setIosPipSourceRectProvider(_iosPipSourceRect);

      if (SettingPref.removeSafeArea) {
        hideSystemBar();
      }
  }

  /// 视频播放前停止音乐，让视频抢占音频会话
  Future<void> _stopMusicForVideo() async {
      // 1. 停止音乐播放器
      if (Get.isRegistered<MusicPlayerController>()) {
          try {
              final musicController = Get.find<MusicPlayerController>();
              if (musicController.isPlaying) {
                  await musicController.pause();
              }
          } catch (_) {}
      }
      // 2. 停止静音保活引擎
      try {
          await SilenceKeeper.stop();
      } catch (_) {}
  }

  @override
  void didPushNext() {
    // 记录进入子路由前的播放状态（无论哪个子路由）
    _wasPlayingBeforePush = controller.playerController.playerStatus.value.isPlaying;

    // 如果是图片查看器，只保存进度，不重置状态
    if (controller.isImageViewerOpen) {
      final ctr = controller.playerController;
      controller.savedPosition = ctr.position;
      // 不暂停播放（可选），或者暂停？通常图片查看器不影响播放，可暂停也可继续。
      // 建议暂停，避免后台继续播放。
      if (ctr.playerStatus.value.isPlaying) {
        ctr.pause();
      }
      return;
    }

    final ctr = controller.playerController;
    // 保存当前播放位置
    controller.savedPosition = ctr.position;
    if (ctr.dataStatus.value == DataStatus.loading) {
      ctr.dataStatus.value = DataStatus.none;
      ctr.isBuffering.value = false;
      controller.autoPlay.value = false;
    }
    if (ctr.playerStatus.value.isPlaying) {
      ctr.pause();
    }
  }

  @override
  void didPopNext() {
    // 图片查看器返回：只清标志，然后尝试恢复
    if (controller.isImageViewerOpen) {
      controller.isImageViewerOpen = false;
      _tryAutoResume();
      return;
    }

    final ctr = controller.playerController;

    // 兜底：返回时仍在 loading 的场景清掉，防止卡死
    if (ctr.dataStatus.value == DataStatus.loading) {
      ctr.dataStatus.value = DataStatus.none;
      ctr.isBuffering.value = false;
      controller.autoPlay.value = false;
      _wasPlayingBeforePush = false;   // 清掉，不恢复
      return;
    }

    _tryAutoResume();
  }

  /// 若进入子路由前视频在播放，则自动恢复播放
  void _tryAutoResume() {
    if (!_wasPlayingBeforePush) {
      _wasPlayingBeforePush = false;
      return;
    }
    _wasPlayingBeforePush = false;

    // 延后一帧，等路由过渡和播放器状态稳定
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        // 前置条件检查：播放地址必须存在
        if (controller.currentPlayUrl.value.isEmpty) {
          debugPrint('[_tryAutoResume] currentPlayUrl empty, skip');
          return;
        }

        // 标记为"自动播放"状态
        controller.autoPlay.value = true;
        controller.isPlaying.value = true;

        // 用已存在的安全入口：playerInit 内部会 setDataSource + play
        // showLoading = false：避免恢复时弹出"正在获取播放信息"的遮罩
        await controller.playerInit(showLoading: false);

        debugPrint('[_tryAutoResume] resumed');
      } catch (e, s) {
        debugPrint('[_tryAutoResume] failed: $e\n$s');
      }
    });
  }

  @override
  void dispose() {
      // ===== 兜底：退出详情页时如果仍处于全屏，强制退出 =====
      // 对应"全屏时 ESC 不退出详情页"的原始诉求。
      // 即使 Focus 和 popScope 都失效（极端场景），退出时也保证状态干净，
      // 防止后续路由沿用全屏状态。
      try {
        final pc = controller.playerController;
        if (pc.isFullScreen.value) {
          pc.triggerFullScreen(status: false);
        }
      } catch (_) {}
      
      // 手动清理详情页控制器
      //
      // DetailController 与 IntroController 是通过 Get.put 手动注册的
      // （不是 GetPage 的 bindings），GetX 不会随路由销毁自动清理。
      // 若不在 State.dispose 中手动 Get.delete，会导致：
      //
      //   1. DetailController.onClose 永远不执行 →
      //      - 退出时的最终进度兜底（_updateHistoryProgress）不写入，
      //        拖拽进度条 / 快速退出 等场景丢失播放进度
      //      - playerController 的监听器、Timer、播放资源泄漏
      //      - 多次进入详情页时状态互相污染
      //
      //   2. IntroController.onClose 永远不执行 → videoDetail 引用不释放
      //
      // 删除顺序很重要：
      //   先删 DetailController，其 onClose 中要读取
      //   introController.videoDetail.value 做最后一次进度兜底；
      //   再删 IntroController，其 onClose 会清空 videoDetail。
      //   顺序反了会导致兜底时 videoDetail 已为 null。
      if (Get.isRegistered<DetailController>(tag: _controllerTag)) {
        controller.setIosPipSourceRectProvider(null);
        Get.delete<DetailController>(tag: _controllerTag);
      }
      if (Get.isRegistered<IntroController>(tag: _controllerTag)) {
        Get.delete<IntroController>(tag: _controllerTag);
      }

      super.dispose();
  }

  Map<String, int>? _iosPipSourceRect() {
    final context = _videoPlayerKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (context == null || renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) return null;

    final width = controller.playerController.videoWidth.value;
    final height = controller.playerController.videoHeight.value;
    final rawRatio = width > 0 && height > 0
        ? width / height
        : size.width / size.height;
    final ratio = rawRatio.clamp(1 / 2.39, 2.39).toDouble();
    final containerRatio = size.width / size.height;
    late final double dx;
    late final double dy;
    late final double videoWidth;
    late final double videoHeight;
    if (containerRatio > ratio) {
      videoHeight = size.height;
      videoWidth = size.height * ratio;
      dx = (size.width - videoWidth) / 2;
      dy = 0;
    } else {
      videoWidth = size.width;
      videoHeight = size.width / ratio;
      dx = 0;
      dy = (size.height - videoHeight) / 2;
    }
    final pixelRatio =
        MediaQuery.maybeOf(context)?.devicePixelRatio ??
        View.of(context).devicePixelRatio;
    final left = ((topLeft.dx + dx) * pixelRatio).round();
    final top = ((topLeft.dy + dy) * pixelRatio).round();
    final right = ((topLeft.dx + dx + videoWidth) * pixelRatio).round();
    final bottom = ((topLeft.dy + dy + videoHeight) * pixelRatio).round();
    if (right <= left || bottom <= top) return null;
    return <String, int>{
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    };
  }

  // ===== 手动播放 UI（封面 + 导航栏 + 播放按钮） =====
  Widget _buildManualPlayerUI({
    required double width,
    required double height,
  }) {
    final cover = controller.introController.videoDetail.value?.vodPic;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 封面图
        if (cover != null && cover.isNotEmpty)
          Image.network(
            cover,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        // 半透明遮罩
        Container(color: Colors.black.withOpacity(0.3)),
        // 顶部导航栏（保持不变）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AppBar(
            primary: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: Colors.white,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 34,
                  child: IconButton(
                    tooltip: '返回',
                    icon: const Icon(Icons.arrow_back, size: 20, color: Colors.white),
                    onPressed: Get.back,
                  ),
                ),
                SizedBox(
                  width: 42,
                  height: 34,
                  child: IconButton(
                    tooltip: '返回主页',
                    icon: const Icon(Icons.home_rounded, size: 20, color: Colors.white),
                    onPressed: controller.playerController.onCloseAll,
                  ),
                ),
              ],
            ),
            actions: [
              // ===== 内核切换按钮（弹菜单让用户选）=====
              // 失败视图会覆盖 HeaderControl（因为 autoPlay == false 时显示此视图），
              // 用户无法通过顶部栏切内核，所以这里提供入口。
              //
              // 交互与顶部栏 HeaderControl 保持一致：
              //   点击 → 弹出菜单列出所有内核 → 用户主动选择 → 才真正切换
              // 而不是直接切到"另一个"内核（否则用户会误以为是重新加载/点击穿透）。
              //
              // - initialValue 高亮当前内核
              // - onSelected 里对"选了当前内核"做短路，避免无意义的重载
              // - autoPlayOverride: true：失败视图里用户点切换即期望能播放，
              //   不像顶部栏那样沿用"切换前是否在播放"的状态
              PopupMenuButton<PlayerEngineType>(
                tooltip: '切换播放内核',
                offset: const Offset(0, 40),
                color: Colors.black.withValues(alpha: 0.85),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                initialValue: PlayerPref.playerEngine,
                itemBuilder: (context) => [
                  PopupMenuItem<PlayerEngineType>(
                    value: PlayerEngineType.mediaKit,
                    height: 40,
                    child: Row(
                      children: [
                        const Text(
                          'MPV',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        const Spacer(),
                        if (PlayerPref.playerEngine ==
                            PlayerEngineType.mediaKit)
                          const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                      ],
                    ),
                  ),
                  PopupMenuItem<PlayerEngineType>(
                    value: PlayerEngineType.fvp,
                    height: 40,
                    child: Row(
                      children: [
                        const Text(
                          'MDK',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        const Spacer(),
                        if (PlayerPref.playerEngine == PlayerEngineType.fvp)
                          const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                      ],
                    ),
                  ),
                ],
                onSelected: (newType) {
                  // 选了当前内核 → 不重复切换，避免一次无意义的重载
                  if (newType == PlayerPref.playerEngine) {
                    SmartDialog.showToast('已是当前内核');
                    return;
                  }
                  controller.switchPlayerEngine(
                    newType,
                    autoPlayOverride: true,
                  );
                },
                child: SizedBox(
                  height: 34,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.play_arrow,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          PlayerPref.playerEngine == PlayerEngineType.fvp
                              ? 'MDK'
                              : 'MPV',
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
              ),
              PopupMenuButton(
                tooltip: '更多功能',
                icon: const Icon(Icons.more_vert, size: 22, color: Colors.white),
                onSelected: (value) {},
                itemBuilder: (context) => <PopupMenuEntry>[
                  PopupMenuItem(
                    onTap: () => controller.saveCover(),
                    child: const Text('保存封面'),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 居中播放按钮 + 失败错误提示
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 80,
                onPressed: () {
                  controller.autoPlay.value = true;
                  controller.reloadCurrentEpisode(seekTo: controller.savedPosition);
                },
                icon: Icon(
                  Icons.play_circle_filled,
                  size: 80,
                  color: Colors.white.withOpacity(0.9),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              // ===== 播放失败时显示错误信息 =====
              Obx(() {
                if (!controller.playFailed.value) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 12, left: 40, right: 40),
                  child: Text(
                    controller.playErrorMessage.value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  /// FVP 引擎首帧加载中提示（完全仿 MPV 风格）
  ///
  /// 样式对齐 plugin/pl_player/view.dart 里 PLVideoPlayer 的 loading overlay：
  /// 黑底 + 径向渐变圆形 + 缓冲图标 + "加载中..."文字
  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Colors.black26, Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              Assets.buffering,
              height: 25,
              semanticLabel: '加载中',
              color: Colors.white,
            ),
            const Text(
              '加载中...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget plPlayer({
    required double width,
    required double height,
    bool isPipMode = false,
  }) {
    return popScope(
      key: _videoPlayerKey,
      canPop: !isFullScreen &&
          !controller.playerController.isDesktopPip &&
          (controller.playerController.horizontalScreen || isPortrait),
      onPopInvokedWithResult: controller.playerController.onPopInvokedWithResult,
      child: Obx(
        () {
          // 显式依赖 isFullScreen 和 engineSwitchNotifier
          // 原因一：PLVideoPlayer 内部的 build 方法使用局部变量 isFullScreen
          //   （取自 plPlayerController.isFullScreen.value），只在 PLVideoPlayer
          //   重建时才会重新读取。若不依赖 isFullScreen，全屏切换时 PLVideoPlayer
          //   不重建，AppBarAni 的 isFullScreen 参数永远是旧值，导致
          //   ViewSafeArea(bottom: isFullScreen) 在全屏时也不会加底部 padding，
          //   控件被 iOS Home Indicator 遮挡。
          // 原因二：引擎切换后 isFullScreen 的 RxBool 会换成新引擎的，
          //   依赖 engineSwitchNotifier 可以在引擎切换完成时强制 PLVideoPlayer
          //   重建，从而订阅新引擎的 isFullScreen 和 dataStatus。
          final _isFullScreen = controller.playerController.isFullScreen.value;
          final _engineSwitch = controller.engineSwitchNotifier.value;

          final bool hasVideo = controller.currentPlayUrl.value.isNotEmpty &&
              controller.playerController.dataStatus.value == DataStatus.loaded;
          if (!hasVideo) {
            // 返回黑色背景（供手动 UI 覆盖）
            return Container(color: Colors.black);
          }
          return PLVideoPlayer(
            // 不添加 key，让 Flutter 自然更新
            maxWidth: width,
            maxHeight: height,
            plPlayerController: controller.playerController,
            headerControl: HeaderControl(controllerTag: _controllerTag),
            controllerTag: _controllerTag,
            fill: Colors.black,
            danmuWidget: isPipMode
                ? null
                : DanmakuView(
                    playerController: controller.playerController,
                    danmakuController: Get.find<DanmakuController>(),
                    size: Size(width, height),
                    isFullScreen: controller.playerController.isFullScreen.value,
                  ),
          );
        },
      ),
    );
  }

  Widget videoPlayer({required double width, required double height}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 黑色背景（始终存在，避免闪烁）
        const Positioned.fill(child: ColoredBox(color: Colors.black)),
        // 播放器（已加载时显示）
        plPlayer(width: width, height: height),
        // 手动播放界面：仅在「确实没有可显示的视频内容」时展示封面
        // 有播放地址且数据已加载时，即使 autoPlay == false（暂停状态）也应显示视频画面
        Obx(() {
          final hasVideo = controller.currentPlayUrl.value.isNotEmpty &&
              controller.playerController.dataStatus.value == DataStatus.loaded;
          final showCover = !controller.autoPlay.value && !hasVideo;
          if (showCover) {
            return _buildManualPlayerUI(width: width, height: height);
          }
          return const SizedBox.shrink();
        }),
        // ===== FVP 引擎专用：首帧加载中提示（仿 MPV 风格） =====
        Obx(() {
          // 永远订阅 dataStatus —— 无论当前是什么内核，
          //    这样切到 FVP 后 dataStatus 一变就会重建
          final status = controller.playerController.dataStatus.value;

          // 订阅 autoPlay，与内部判断一致
          final autoPlay = controller.autoPlay.value;

          // 引擎判断放最后（只影响输出，不影响订阅）
          if (PlayerPref.playerEngine != PlayerEngineType.fvp) {
            return const SizedBox.shrink();
          }
          if (!autoPlay) {
            return const SizedBox.shrink();
          }
          if (status != DataStatus.loading) {
            return const SizedBox.shrink();
          }
          return _buildLoadingOverlay();
        }),
        if (Platform.isIOS)
          ListenableBuilder(
            listenable: Listenable.merge([
              IosPipHelper.instance.isActive,
              IosPipHelper.instance.isRequested,
              IosPipHelper.instance.activeEpisodeIndex,
            ]),
            builder: (context, _) {
              if (IosPipHelper.instance.isActive.value) {
                return _buildIosPipOverlay();
              }
              if (IosPipHelper.instance.isRequested.value) {
                return _buildIosPipStartingOverlay();
              }
              return const SizedBox.shrink();
            },
          ),
      ],
    );
  }

  Widget _buildIosPipOverlay() {
    final title = controller.introController.videoDetail.value?.vodName ?? '';
    final episode = controller.introController.currentPlayEpisode?.name ?? '';
    return Positioned.fill(
      child: ClipRect(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.94),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isFullScreen =
                  controller.playerController.isFullScreen.value;
              // 竖屏非全屏视频区只有约 16:9 高，不能沿用整屏安全区
              // 和全屏尺寸的卡片、按钮。
              final compact = constraints.maxHeight < 320;
              final cardPadding = compact ? 10.0 : 24.0;
              final buttonStyle = compact
                  ? ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 10),
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    )
                  : null;

              return SafeArea(
                top: isFullScreen,
                bottom: isFullScreen,
                child: Stack(
                  children: [
                    Positioned(
                      left: compact ? 2 : 8,
                      top: compact ? 2 : 8,
                      child: IconButton(
                        tooltip: '返回',
                        visualDensity: compact
                            ? VisualDensity.compact
                            : VisualDensity.standard,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: compact ? 16 : 20,
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: compact ? 10 : 24,
                        ),
                        padding: EdgeInsets.fromLTRB(
                          cardPadding,
                          cardPadding,
                          cardPadding,
                          compact ? 8 : 20,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xDD111111),
                          borderRadius: BorderRadius.circular(compact ? 12 : 18),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.picture_in_picture_alt_rounded,
                              color: Colors.white,
                              size: compact ? 20 : 34,
                            ),
                            SizedBox(height: compact ? 2 : 14),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 12 : 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (episode.isNotEmpty) ...[
                              SizedBox(height: compact ? 1 : 4),
                              Text(
                                episode,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: compact ? 10 : 12,
                                ),
                              ),
                            ],
                            SizedBox(height: compact ? 1 : 6),
                            Text(
                              '正在画中画窗口中播放',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: compact ? 10 : 13,
                              ),
                            ),
                            SizedBox(height: compact ? 5 : 18),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: compact ? 6 : 10,
                              runSpacing: compact ? 4 : 8,
                              children: [
                                FilledButton.icon(
                                  style: buttonStyle,
                                  onPressed: () => controller
                                      .stopIosPictureInPictureAndRestore(),
                                  icon: Icon(
                                    Icons.fullscreen_rounded,
                                    size: compact ? 14 : 18,
                                  ),
                                  label: Text('恢复应用内播放'),
                                ),
                                OutlinedButton.icon(
                                  style: buttonStyle,
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: compact ? 14 : 18,
                                  ),
                                  label: const Text('退出播放'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildIosPipStartingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.88),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 14),
              Text(
                '正在启动画中画...',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 竖屏布局 ----
  Widget _buildPortraitLayout() {
    final bool isFullScreen = controller.playerController.isFullScreen.value;
    final Size size = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.viewPaddingOf(context);
    final bool removeSafeArea = SettingPref.removeSafeArea;

    // 视频实际高度（16:9）
    final double videoHeight = size.width * 9 / 16;
    // 非全屏时顶部需要留出状态栏高度
    final double topPadding = isFullScreen ? 0 : (removeSafeArea ? 0 : padding.top);
    // Sliver 头部总高度 = 视频高度 + 顶部安全区域（非全屏时）
    final double headerHeight = isFullScreen ? size.height : videoHeight + topPadding;

    // ===== 全屏：完全绕过 ExtendedNestedScrollView =====
    //
    // 关键修复：
    //   竖屏全屏时 ExtendedNestedScrollView 的 header 会被垂直拖动手势
    //   驱动收缩（即使 physics = NeverScrollableScrollPhysics）。
    //   现象："按住底部上滑 → 视频区缩小 → body 从下方露出"，
    //   且锁屏与否都能触发（锁屏时 _scaleGestureRecognizer 未注册，
    //   pan 事件直接冒泡到 outer Scrollable）。
    //
    //   横屏走 _buildLandscapeLayout，用的是简单 Row + SizedBox，
    //   不涉及 NestedScrollView，所以没这个问题。
    //
    //   全屏时 body 本来就不可见，没必要用 NestedScrollView；
    //   直接返回全屏尺寸的 videoPlayer 即可彻底规避。
    if (isFullScreen) {
      return SizedBox(
        width: size.width,
        height: size.height,
        child: videoPlayer(width: size.width, height: size.height),
      );
    }

    // ===== 非全屏：保持原逻辑不变 =====
    final Widget layout = ExtendedNestedScrollView(
      key: _scrollKey,
      onlyOneScrollInBody: true,
      pinnedHeaderSliverHeightBuilder: () => headerHeight,
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverPinnedDynamicHeader(
            key: const Key('sliver_header'),
            minExtent: kToolbarHeight,
            maxExtent: headerHeight,
            child: SizedBox(
              width: size.width,
              height: headerHeight,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Colors.black),
                  ),
                  Positioned(
                    top: topPadding,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      width: size.width,
                      height: videoHeight,
                      child: videoPlayer(
                        width: size.width,
                        height: videoHeight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];
      },
      body: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            _buildTabBar(controller),
            Expanded(
              child: _buildTabBarView(controller),
            ),
          ],
        ),
      ),
    );

    // 非全屏下状态栏背景为黑色，需要浅色图标
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: layout,
    );
  }

  // ---- 宽屏布局 ----
  Widget _buildLandscapeLayout() {
    final bool isFullScreen = controller.playerController.isFullScreen.value;
    final Size size = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.viewPaddingOf(context);
    // 全屏时可用高度为屏幕高度，非全屏时去除顶部和底部安全区域
    final double availableHeight = isFullScreen
        ? size.height
        : size.height - padding.top - padding.bottom;
    const double rightWidth = 400.0;

    // 全屏时视频宽度为屏幕宽度，非全屏时减去右侧面板宽度
    final double videoWidth = isFullScreen ? size.width : size.width - rightWidth;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: videoWidth,
          height: availableHeight,
          child: videoPlayer(width: videoWidth, height: availableHeight),
        ),
        Offstage(
          offstage: isFullScreen,
          child: SizedBox(
            width: rightWidth,
            height: availableHeight,
            child: Column(
              children: [
                _buildTabBar(controller, isLandscape: true),
                Expanded(
                  child: _buildTabBarView(controller),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- TabBar ----
  Widget _buildTabBar(DetailController controller, {bool isLandscape = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: TabBar(
                controller: controller.tabCtr,
                padding: EdgeInsets.zero,
                labelStyle: const TextStyle(fontSize: 13),
                labelPadding: const EdgeInsets.symmetric(horizontal: 10.0),
                dividerColor: Colors.transparent,
                dividerHeight: 0,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [
                  Tab(text: '简介'),
                  Tab(text: '推荐'),
                  Tab(text: '搜索'),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // ===== 下载按钮 =====
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: IconButton(
                      tooltip: '缓存当前视频',
                      onPressed: () => controller.cacheCurrentVideo(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        // Icons.download_outlined,
                        Icons.download_outlined,
                        size: 22,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // ===== 弹幕开关 =====
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: Obx(() {
                      final ctr = controller.playerController;
                      final enable = ctr.enableShowDanmaku.value;
                      return IconButton(
                        onPressed: controller.toggleDanmaku,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          enable ? CustomIcons.dm_on : CustomIcons.dm_off,
                          size: 22,
                          color: enable
                              ? colorScheme.secondary
                              : colorScheme.outline,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- TabBarView ----
  Widget _buildTabBarView(DetailController controller) {
    return TabBarView(
      controller: controller.tabCtr,
      children: [
        IntroView(controllerTag: _controllerTag),
        RecommendTab(controllerTag: _controllerTag),
        SearchTab(controllerTag: _controllerTag),
      ],
    );
  }

  // ---- 主 build ----
  @override
  Widget buildPage(ThemeData theme) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.viewPaddingOf(context);
    if (controller.playerController.removeSafeArea) {
      this.padding = EdgeInsets.zero;
    } else {
      this.padding = padding;
    }
    maxWidth = size.width;
    maxHeight = size.height;
    isPortrait = size.height >= size.width;
    themeData = theme;

    return Obx(() {
      // 显式依赖 engineSwitchNotifier
      // 根本原因：PlPlayerController.isFullScreen 的 getter 每次调用都返回
      // _ensureEngine().isFullScreen，即「当前引擎」的 RxBool。引擎切换后，
      // 旧引擎的 RxBool 被废弃，新引擎的 RxBool 是新对象。
      // 但 Obx 在首次 build 时已订阅旧引擎的 RxBool，引擎切换后不会自动
      // 重新订阅新引擎的 RxBool，导致之后 isFullScreen 的变化无法感知，
      // 全屏按钮「点了没反应」。
      // 加入对 engineSwitchNotifier 的依赖后，引擎切换完成时会强制重建
      // 当前 Obx，重建时重新调用 playerController.isFullScreen 并订阅
      // 新引擎的 RxBool，之后全屏状态变化就能正常感知。
      final _engineSwitch = controller.engineSwitchNotifier.value;

      final ColorScheme colorScheme = theme.colorScheme;

      if (controller.isLoadingDetail.value) {
        return Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: const Text('详情'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: colorScheme.onSurface,
          ),
          body: const Center(child: CircularProgressIndicator()),
        );
      }

      if (controller.detailError.value.isNotEmpty) {
        return Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: const Text('详情'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: colorScheme.onSurface,
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: colorScheme.outline),
                const SizedBox(height: 12),
                Text(
                  controller.detailError.value,
                  style: TextStyle(color: colorScheme.outline, fontSize: 14),
                ),
              ],
            ),
          ),
        );
      }

      final bool isFullScreen = controller.playerController.isFullScreen.value;
      final bool isPipMode = controller.playerController.isPipMode;

      Widget content;
      if (isPipMode) {
        content = SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: PLVideoPlayer(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            plPlayerController: controller.playerController,
            headerControl: HeaderControl(controllerTag: _controllerTag),
            controllerTag: _controllerTag,
            fill: Colors.black,
            danmuWidget: null,
          ),
        );
      } else {
        final bool isWide;
        if (isFullScreen) {
          // 全屏时优先按系统方向判断：横屏用左右分栏，竖屏用上下分栏
          final orientation = MediaQuery.orientationOf(context);
          isWide = orientation == Orientation.landscape
              && size.width > 600;   // 手机横屏通常 > 600，平板更宽
        } else {
          isWide = size.width > 800;
        }
        content = isWide ? _buildLandscapeLayout() : _buildPortraitLayout();
      }

      Widget pageContent = Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        extendBody: true,
        resizeToAvoidBottomInset: false,
        body: content,
      );

      final bool removeSafeArea = SettingPref.removeSafeArea;
      if (removeSafeArea) {
        pageContent = MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: pageContent,
        );
      } else if (isFullScreen) {
        pageContent = MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: pageContent,
        );
      }

      return pageContent;
    });
  }
}
