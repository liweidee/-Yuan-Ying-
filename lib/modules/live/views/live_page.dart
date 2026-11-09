// lib/modules/live/views/live_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/live/controllers/live_controller.dart';
import 'package:yuanying/modules/live/widgets/live_player_view.dart';
import 'package:yuanying/modules/live/widgets/live_group_list.dart';
import 'package:yuanying/modules/live/widgets/live_channel_list.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/modules/live/widgets/live_channel_info_bar.dart';
import 'package:yuanying/modules/live/widgets/live_epg_timeline.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/services/silence_keeper.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  late final LiveController controller;
  final GlobalKey _playerKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    // ===== 主动停止音乐播放，让直播独占音频会话 =====
    _stopMusicForLive();

    if (!Get.isRegistered<LiveController>(tag: 'live')) {
      Get.put(LiveController(), tag: 'live', permanent: true);
    }
    controller = Get.find<LiveController>(tag: 'live');
    controller.ensurePlayerInitialized();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ===== 判断是否需要显示 loading =====
      final hasData = controller.channels.isNotEmpty;
      final hasError = controller.errorMessage.value.isNotEmpty;

      if (hasData && !hasError) {
        // 已有数据：静默刷新（不显示 loading）
        controller.refreshChannels(showLoading: false);
      } else {
        // 首次进入或错误状态：显示 loading
        controller.refreshChannels(showLoading: true);
      }
    });
  }

  /// 直播播放前停止音乐，让直播抢占音频会话
  Future<void> _stopMusicForLive() async {
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
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final bool isFullScreen = controller.isFullScreen.value;
      final bool isLoading = controller.isLoading.value;
      final String errorMsg = controller.errorMessage.value;
      final bool hasChannels = controller.channels.isNotEmpty;

      if (isFullScreen) {
        return const Scaffold(
          backgroundColor: Colors.transparent,
          body: SizedBox.shrink(),
        );
      }

      if (isLoading) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: null,
          body: Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      }

      if (errorMsg.isNotEmpty || !hasChannels) {
        return _buildEmptyOrErrorPage(context);
      }

      return _buildNormalContent(context);
    });
  }

  Widget _buildErrorPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: null,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '直播接口请求失败',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                controller.errorMessage.value.isNotEmpty
                    ? controller.errorMessage.value
                    : '请检查网络或配置',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  await Get.toNamed(AppPages.liveConfig);
                  // 从配置页返回，强制显示 loading 重新加载
                  controller.refreshChannels(showLoading: true);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('直播配置'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyOrErrorPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final msg = controller.errorMessage.value;

    // 判断是否是"无配置"的空状态
    final isNoConfig = msg.isEmpty ||
        msg.contains('暂无直播配置') ||
        msg.contains('暂无有效的直播配置');

    if (isNoConfig) {
      // ===== 空状态：未添加任何配置 =====
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: null,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    Icons.live_tv_outlined,
                    size: 40,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '还没有直播配置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '添加直播源后即可观看电视直播',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.outline,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    await Get.toNamed(AppPages.liveConfig);
                    controller.refreshChannels(showLoading: true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加直播配置'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ===== 其它情况：保持原有的错误样式 =====
    return _buildErrorPage(context);
  }

  Widget _buildNormalContent(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: null,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isDesktop = constraints.maxWidth > 800;
          final Widget playerWidget = LivePlayerView(
            key: _playerKey,
            isFullScreen: false,
          );

          if (isDesktop) {
            return _buildDesktopLayout(playerWidget);
          } else {
            return _buildMobileLayout(playerWidget, 0);
          }
        },
      ),
    );
  }

  // ========================================================================
  // 移动端布局：频道区做成"开壁纸时圆角 10 半透明面板 / 关壁纸时无形"
  // ========================================================================
  Widget _buildMobileLayout(Widget playerWidget, double topPadding) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool bgActive = SettingPref.bgActive;

    final Color bottomBg = bgActive
        ? colorScheme.surface.withValues(alpha: isDark ? 0.72 : 0.62)
        : colorScheme.surface;

    // 1. 移除 SizedBox(height: topPadding) —— 状态栏区域已由 MainPage.AppBar
    //    用黑色填充，LivePage 的 body 起点已经在状态栏下方，无需再留白。
    //    原实现会在状态栏下方额外空出 topPadding 的高度，导致视频位置偏低。
    //
    // 2. 移除外层的 ColoredBox(Colors.black) —— 视频区本身的黑色由 LivePlayerView
    //    内部保证，MainPage 也已经处理了状态栏区域，不需要再包一层黑色。
    //    如果 LivePlayerView 在某些时刻露出透明，仍然需要黑色兜底，
    //    可以保留一个薄的 ColoredBox，但不需要包含 SizedBox。
    //
    // 3. 移除 AnnotatedRegion —— 状态栏图标颜色已由 MainPage.AppBar 的
    //    systemOverlayStyle 控制，LivePage 内部再设置也无法影响状态栏区域
    //    （LivePage 的坐标原点在状态栏下方，AnnotatedRegion 覆盖不到状态栏）。
    //
    // 4. 保留 ColoredBox(Colors.black) 兜底视频区，但去掉 SizedBox(height: topPadding)。
    //    这样视频紧贴状态栏下方，视觉上和状态栏的黑色连续。
    return Column(
      children: [
        // 视频区（黑色兜底，防止 LivePlayerView 未出帧时露底）
        ColoredBox(
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: playerWidget,
          ),
        ),
        // 视频下方整块区域
        Expanded(
          child: ColoredBox(
            color: bottomBg,
            child: Column(
              children: [
                const LiveChannelInfoBar(),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colorScheme.outline.withValues(alpha: 0.08),
                ),
                Expanded(
                  child: Row(
                    children: const [
                      LiveGroupList(width: 110, isDesktop: false),
                      Expanded(child: LiveChannelList()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ========================================================================
  // 桌面端布局：侧栏贴边 + 视频/EPG 各自独立
  //
  //  - 左侧 320 侧栏贴边，无圆角无阴影，右侧 1px 分割线（与 MainPage 侧栏语言一致）
  //  - 右侧视频区是黑底矩形，不带外框圆角
  //  - EPG 独立一条信息带，不再被外层圆角裁剪
  // ========================================================================
  Widget _buildDesktopLayout(Widget playerWidget) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool bgActive = SettingPref.bgActive;

    final Color sideBarBg = bgActive
        ? colorScheme.surface.withValues(alpha: isDark ? 0.72 : 0.62)
        : colorScheme.surface;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ===== 左侧贴边侧栏 =====
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: sideBarBg,
            border: Border(
              right: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: const Row(
            children: [
              LiveGroupList(width: 120, isDesktop: true),
              Expanded(child: LiveChannelList()),
            ],
          ),
        ),
        // ===== 右侧：视频 + EPG 分层融合 =====
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: ColoredBox(
                  // 兜底：视频未出帧时不留壁纸缝隙
                  color: Colors.black,
                  child: playerWidget,
                ),
              ),
              const LiveEpgTimeline(),
            ],
          ),
        ),
      ],
    );
  }
}