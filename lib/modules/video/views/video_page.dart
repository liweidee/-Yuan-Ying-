import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yuanying/common/widgets/custom_icon.dart';
import 'dart:io' show Platform;
import 'package:yuanying/modules/danmaku/controllers/danmaku_controller.dart';
import 'package:yuanying/modules/danmaku/widgets/danmaku_view.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/modules/video/widgets/header_control.dart';
import 'package:yuanying/modules/video/widgets/introduction/intro_view.dart';
import 'package:yuanying/plugin/pl_player/view.dart';
import 'package:yuanying/plugin/pl_player/models/data_status.dart';
import 'package:yuanying/modules/video/widgets/player_focus.dart';
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

class DetailPage extends CommonSlidePage {
  const DetailPage({super.key, super.enableSlide = true});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage>
    with RouteAware, RouteAwareMixin, TickerProviderStateMixin, CommonSlideMixin<DetailPage> {
  late final String _controllerTag;
  late final DetailController controller;

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

    final args = Get.arguments as Map?;
    _controllerTag = args?['_controllerTag'] as String? ??
        'detail_${DateTime.now().millisecondsSinceEpoch}';

    if (Get.isRegistered<DetailController>(tag: _controllerTag)) {
      controller = Get.find<DetailController>(tag: _controllerTag);
    } else {
      controller = Get.put(DetailController(tag: _controllerTag), tag: _controllerTag);
    }

    if (SettingPref.removeSafeArea) {
      hideSystemBar();
    }
  }

  @override
  void didPushNext() {
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
    final ctr = controller.playerController;
    ctr.dataStatus.value = DataStatus.none;
    ctr.isBuffering.value = false;
    controller.autoPlay.value = false;
    controller.isPlaying.value = false;
    // 如果播放器存在且正在播放，暂停
    if (ctr.playerStatus.value.isPlaying) {
      ctr.pause();
    }
  }

  @override
  void dispose() {
    super.dispose();
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
        // 居中播放按钮（纯白色，无主题颜色）
        Center(
          child: IconButton(
            iconSize: 80,
            // onPressed: () {
            //   if (controller.currentPlayUrl.value.isNotEmpty) {
            //     controller.autoPlay.value = true;
            //     controller.playerController.play();
            //   } else {
            //     controller.autoPlay.value = true;
            //     controller.reloadCurrentEpisode();
            //   }
            // },
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
        ),
      ],
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
        // 手动播放界面（autoPlay == false 时显示）
        Obx(() {
          if (!controller.autoPlay.value) {
            return _buildManualPlayerUI(width: width, height: height);
          }
          return const SizedBox.shrink();
        }),
      ],
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

    return ExtendedNestedScrollView(
      key: _scrollKey,
      physics: isFullScreen ? const NeverScrollableScrollPhysics() : null,
      onlyOneScrollInBody: true,
      pinnedHeaderSliverHeightBuilder: () => headerHeight,
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverPinnedDynamicHeader(
            key: const Key('sliver_header'),
            minExtent: kToolbarHeight,
            maxExtent: headerHeight,
            child: isFullScreen
                ? SizedBox(
                    width: size.width,
                    height: headerHeight,
                    child: videoPlayer(width: size.width, height: videoHeight),
                  )
                : Padding(
                    // 关键：顶部留出状态栏高度
                    padding: EdgeInsets.only(top: topPadding),
                    child: SizedBox(
                      width: size.width,
                      height: videoHeight,
                      child: videoPlayer(width: size.width, height: videoHeight),
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
                          color: enable ? colorScheme.secondary : colorScheme.outline,
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
        final bool isWide = MediaQuery.sizeOf(context).width > 800;
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