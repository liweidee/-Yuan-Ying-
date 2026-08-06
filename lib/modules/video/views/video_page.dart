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

class DetailPage extends CommonSlidePage {
  const DetailPage({super.key, super.enableSlide = true});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage>
    with RouteAware, RouteAwareMixin, TickerProviderStateMixin, CommonSlideMixin<DetailPage> {
  // ===== 1. 在 State 中存储控制器 tag =====
  late final String _controllerTag;
  late final DetailController controller;

  @override
  void initState() {
    super.initState();

    // ===== 2. 从路由参数获取 tag，如果没有则生成唯一值 =====
    final args = Get.arguments as Map?;
    _controllerTag = args?['_controllerTag'] as String? ??
        'detail_${DateTime.now().millisecondsSinceEpoch}';

    // ===== 3. 使用 tag 注册主控制器 =====
    if (Get.isRegistered<DetailController>(tag: _controllerTag)) {
      controller = Get.find<DetailController>(tag: _controllerTag);
    } else {
      controller = Get.put(DetailController(tag: _controllerTag), tag: _controllerTag);
    }
  }

  @override
  void didPushNext() {
    // 只暂停播放器，不清空任何状态
    if (controller.playerController.playerStatus.value.isPlaying) {
      controller.playerController.pause();
    }
  }

  @override
  void didPopNext() {
    if (controller.currentPlayUrl.value.isNotEmpty) {
      // 原页面有播放内容，恢复播放
      controller.playerController.play();
    } else {
      // 原页面没有播放内容，停止播放器
      controller.playerController.pause();
      controller.playerController.dataStatus.value = DataStatus.none;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget buildPage(ThemeData theme) {
    final tabBarKey = GlobalKey();
    controller.setTabBarKey(tabBarKey);
    final bool removeSafeArea = SettingPref.removeSafeArea;

    return Obx(() {
      final colorScheme = ColorScheme.of(context);

      // 加载中
      if (controller.isLoadingDetail.value) {
        return Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: const Text('详情'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: colorScheme.onSurface,
          ),
          body: Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colorScheme.primary,
              ),
            ),
          ),
        );
      }

      // 错误状态
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

      final isFullScreen = controller.playerController.isFullScreen.value;
      final isPipMode = controller.playerController.isPipMode;

      // 强制 Obx 监听引擎切换事件，切内核后重新收集 isFullScreen 依赖
      controller.engineSwitchNotifier.value;

      Widget pageContent = Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        extendBody: true,
        body: DefaultTabController(
          length: 3,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (isPipMode) {
                return SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: PLVideoPlayer(
                    maxWidth: constraints.maxWidth,
                    maxHeight: constraints.maxHeight,
                    plPlayerController: controller.playerController,
                    headerControl: HeaderControl(controllerTag: _controllerTag),
                    controllerTag: _controllerTag,
                    fill: Colors.black,
                    danmuWidget: null,
                  ),
                );
              }
              final isWide = constraints.maxWidth > 800;
              return isWide
                  ? _buildLandscapeLayout(context, controller, tabBarKey, colorScheme, theme, isFullScreen)
                  : _buildPortraitLayout(context, controller, tabBarKey, colorScheme, theme, isFullScreen);
            },
          ),
        ),
      );

      if (removeSafeArea) {
        pageContent = MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: pageContent,
        );
      }

      return pageContent;
    });
  }

  // ---- 单列布局（移动端） ----
  Widget _buildPortraitLayout(
    BuildContext context,
    DetailController controller,
    GlobalKey tabBarKey,
    ColorScheme colorScheme,
    ThemeData theme,
    bool isFullScreen,
  ) {
    final size = MediaQuery.sizeOf(context);
    final videoHeight = isFullScreen ? size.height : size.width * 9 / 16;
    return Column(
      children: [
        _buildPlayer(
          context,
          controller,
          size.width,
          videoHeight,
          colorScheme,
          theme,
        ),
        if (!isFullScreen)
          Expanded(
            child: _buildTabBarAndContent(
              context,
              controller,
              tabBarKey,
              colorScheme,
              theme,
            ),
          ),
      ],
    );
  }

  // ---- 双列布局（桌面宽屏） ----
  Widget _buildLandscapeLayout(
    BuildContext context,
    DetailController controller,
    GlobalKey tabBarKey,
    ColorScheme colorScheme,
    ThemeData theme,
    bool isFullScreen,
  ) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final availableHeight = size.height - padding.top - padding.bottom;
    final playerWidth = isFullScreen
        ? size.width
        : (size.width * 0.6).clamp(400.0, 800.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: playerWidth,
          height: availableHeight,
          child: _buildPlayer(
            context,
            controller,
            playerWidth,
            availableHeight,
            colorScheme,
            theme,
          ),
        ),
        if (!isFullScreen)
          Expanded(
            child: Column(
              children: [
                _buildTabBar(
                  context,
                  controller,
                  tabBarKey,
                  colorScheme,
                  theme,
                  isLandscape: true,
                ),
                Expanded(
                  child: _buildTabBarView(context, controller, colorScheme, theme),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// PiP 模式专用头部（只有退出按钮 + 拖拽区域）
  // Widget _buildPipHeader(BuildContext context, DetailController controller) {
  //   return Container(
  //     height: 44,
  //     padding: const EdgeInsets.symmetric(horizontal: 8),
  //     decoration: const BoxDecoration(
  //       gradient: LinearGradient(
  //         begin: Alignment.topCenter,
  //         end: Alignment.bottomCenter,
  //         colors: [Colors.black87, Colors.transparent],
  //       ),
  //     ),
  //     child: Row(
  //       children: [
  //         // 返回按钮 - 退出 PiP
  //         SizedBox(
  //           width: 40,
  //           height: 34,
  //           child: IconButton(
  //             tooltip: '退出画中画',
  //             style: const ButtonStyle(
  //               padding: WidgetStatePropertyAll(EdgeInsets.zero),
  //             ),
  //             icon: const Icon(
  //               Icons.close,
  //               size: 20,
  //               color: Colors.white,
  //             ),
  //             onPressed: () async {
  //               if (controller.playerController.isDesktopPip) {
  //                 await controller.playerController.exitDesktopPip();
  //               }
  //             },
  //           ),
  //         ),
  //         // 中间空白区域用于拖拽窗口
  //         Expanded(
  //           child: GestureDetector(
  //             behavior: HitTestBehavior.translucent,
  //             onPanStart: (_) => windowManager.startDragging(),
  //             child: Container(),
  //           ),
  //         ),
  //         // PiP 状态指示
  //         const Padding(
  //           padding: EdgeInsets.only(right: 12),
  //           child: Icon(
  //             Icons.picture_in_picture_alt,
  //             size: 16,
  //             color: Colors.white54,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // ---- 播放器构建 ----
  Widget _buildPlayer(
    BuildContext context,
    DetailController controller,
    double width,
    double height,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    // ===== 读取设置 =====
    final bool removeSafeArea = SettingPref.removeSafeArea;
    final bool darkVideoPage = SettingPref.darkVideoPage;

    // ===== 构建播放器内容 =====
    Widget playerContent = SizedBox(
      width: width,
      height: height,
      child: Obx(() {
        final args = Get.arguments as Map?;
        final directUrl = args?['directUrl'] as String?;

        if (directUrl != null && directUrl.isNotEmpty) {
          return PLVideoPlayer(
            maxWidth: width,
            maxHeight: height,
            plPlayerController: controller.playerController,
            headerControl: HeaderControl(controllerTag: _controllerTag),
            controllerTag: _controllerTag,
            fill: Colors.black,
            danmuWidget: DanmakuView(
              playerController: controller.playerController,
              danmakuController: Get.find<DanmakuController>(),
              size: Size(width, height),
              isFullScreen: controller.playerController.isFullScreen.value,
            ),
          );
        }

        final status = controller.playerController.dataStatus.value;

        if (status == DataStatus.error) {
          return Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '视频加载失败，请重试',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (controller.playerController.isPipMode) {
          return PLVideoPlayer(
            maxWidth: width,
            maxHeight: height,
            plPlayerController: controller.playerController,
            headerControl: HeaderControl(controllerTag: _controllerTag),
            controllerTag: _controllerTag,
            fill: Colors.black,
            danmuWidget: null,
          );
        }

        if (status == DataStatus.none || status == DataStatus.loading) {
          final cover = controller.introController.videoDetail.value?.vodPic;
          return Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null && cover.isNotEmpty)
                  Image.network(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Get.back(),
                  ),
                ),
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 32,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return PlayerFocus(
          plPlayerController: controller.playerController,
          controllerTag: _controllerTag,
          child: PLVideoPlayer(
            maxWidth: width,
            maxHeight: height,
            plPlayerController: controller.playerController,
            headerControl: HeaderControl(controllerTag: _controllerTag),
            controllerTag: _controllerTag,
            fill: Colors.black,
            danmuWidget: DanmakuView(
              playerController: controller.playerController,
              danmakuController: Get.find<DanmakuController>(),
              size: Size(width, height),
              isFullScreen: controller.playerController.isFullScreen.value,
            ),
          ),
        );
      }),
    );

    // ===== 移除安全边距（让播放器延伸到边缘） =====
    // 只在非全屏模式下生效
    if (removeSafeArea && !controller.playerController.isFullScreen.value) {
      playerContent = MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        removeLeft: true,
        removeRight: true,
        child: playerContent,
      );
    }

    // ===== 深色主题包裹播放器 =====
    if (darkVideoPage) {
      playerContent = Theme(
        data: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorScheme: ColorScheme.dark(
            surface: Colors.black,
            primary: Colors.blue,
          ),
          scaffoldBackgroundColor: Colors.black,
        ),
        child: playerContent,
      );
    }

    // ===== iOS 非全屏竖屏时，添加顶部安全区域避开刘海 =====
    final bool needSafeArea = Platform.isIOS &&
        !controller.playerController.isFullScreen.value &&
        MediaQuery.of(context).orientation == Orientation.portrait &&
        !removeSafeArea;

    if (needSafeArea) {
      playerContent = SafeArea(
        top: true,
        bottom: false,
        left: false,
        right: false,
        child: playerContent,
      );
    }

    return playerContent;
  }

  // ---- TabBar + 内容（单列中的完整下半部分） ----
  Widget _buildTabBarAndContent(
    BuildContext context,
    DetailController controller,
    GlobalKey tabBarKey,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Column(
      children: [
        _buildTabBar(context, controller, tabBarKey, colorScheme, theme, isLandscape: false),
        Expanded(
          child: _buildTabBarView(context, controller, colorScheme, theme),
        ),
      ],
    );
  }

  // ---- TabBar 单独提取 ----
  Widget _buildTabBar(
    BuildContext context,
    DetailController controller,
    GlobalKey tabBarKey,
    ColorScheme colorScheme,
    ThemeData theme, {
    bool isLandscape = false,
  }) {
    return SizedBox(
      height: 45,
      child: DecoratedBox(
        key: tabBarKey,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            const Expanded(
              flex: 2,
              child: TabBar(
                padding: EdgeInsets.zero,
                labelStyle: TextStyle(fontSize: 13),
                labelPadding: EdgeInsets.symmetric(horizontal: 10.0),
                dividerColor: Colors.transparent,
                dividerHeight: 0,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: [
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

  // ---- TabBarView 单独提取 ----
  Widget _buildTabBarView(
    BuildContext context,
    DetailController controller,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return TabBarView(
      children: [
        // ===== 简介 Tab =====
        IntroView(controllerTag: _controllerTag),
        
        // ===== 推荐 Tab =====
        RecommendTab(controllerTag: _controllerTag),
        
        // ===== 搜索 Tab =====
        SearchTab(controllerTag: _controllerTag),
      ],
    );
  }
}