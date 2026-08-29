import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:fvp/fvp.dart' as fvp;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:yuanying/common/widgets/back_detector.dart';
import 'package:yuanying/common/widgets/custom_toast.dart';
import 'package:yuanying/common/widgets/route_aware_mixin.dart';
import 'package:yuanying/common/widgets/scale_app.dart';
import 'package:yuanying/common/widgets/scroll_behavior.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/danmaku/controllers/danmaku_controller.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/t4/services/t4_api_service.dart';
import 'package:yuanying/t4/services/drpy2_api_service.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/theme_utils.dart';
import 'package:yuanying/modules/action/services/action_service.dart';
import 'package:yuanying/modules/action/widgets/action_renderer.dart';
import 'package:yuanying/services/search_filter_service.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/utils/cache_manager.dart';
import 'package:yuanying/utils/update.dart';
import 'package:yuanying/http/init.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;
import 'package:yuanying/t4/services/catvod_open_service.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:yuanying/t4/services/python_runtime.dart';
import 'package:yuanying/services/debug_log_service.dart';
import 'package:yuanying/nodejs/nodejs_service.dart';
import 'package:yuanying/t4/services/nodejs_spider_service.dart';
import 'package:yuanying/services/catvod_log_service.dart';
import 'package:yuanying/modules/novel/services/novel_tts_service.dart';
import 'package:yuanying/modules/novel/services/novel_font_service.dart';

// ============================================================================
// 全局变量
// ============================================================================
// ===== WebView 环境（用于 Windows 平台） =====
WebViewEnvironment? webViewEnvironment;

// ============================================================================
// 自定义 HttpOverrides
// ============================================================================
class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // 兜底：如果 Dio 未配置 SSL，使用此设置
    if (SettingPref.badCertificateCallback) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      PythonRuntime.dispose();
    }
  }
}

void main() async {
  // ==========================================================================
  // 第一步：Hive 初始化（必须在任何存储操作之前）
  // ==========================================================================
  if (!kIsWeb) {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    Hive.init(appDocumentDir.path);
  }

  // ==========================================================================
  // 第二步：存储初始化（必须在任何 getSetting 之前）
  // ==========================================================================
  await GStorage.init();
  await StorageManager.init();

  // 打开播放器相关 Box
  await Hive.openBox('player_settings');
  await Hive.openBox('app_settings');
  await Hive.openBox('video_settings');

  // ==========================================================================
  // 第三步：UI 缩放适配（现在可以安全调用 getSetting）
  // ==========================================================================
  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: StorageManager.getSetting<double>(SettingBoxKey.uiScale) ?? 1.0,
  );

  // ==========================================================================
  // 第四步：媒体播放器初始化
  // ==========================================================================
  media_kit.MediaKit.ensureInitialized();
  if (!kIsWeb) {
    fvp.registerWith(options: {
      /// 全平台接管核心
      /// 不设置或置空时，FVP 会自动无缝接管全部 5+1 个移动与桌面端平台。
      // 'platforms': ['windows', 'macos', 'linux', 'android', 'ios'], 

      /// 全平台动态硬解链
      /// 核心机制：自左向右优先匹配系统最强硬解，若硬件不支持，自动平滑降级至 FFmpeg 软解。
      'video.decoders': _getGlobalOptimalDecoders(),

      /// 极速寻帧优化
      /// 默认为 false（即精确寻帧，但高码率视频拖动进度条会卡顿）。
      /// 设置为 true 后，开启关键帧快速寻帧，进度条拖动瞬间响应，体验极佳。
      'fastSeek': true, 

      /// 网络流低延迟优化
      /// 专为直播流、RTMP/RTSP、监控等网络视频流设计。
      /// 显著降低首帧加载时间，若只做本地点播可将此行注释。
      'lowLatency': 1, 
    });
  }

  // ==========================================================================
  // 第五步：窗口管理器初始化（桌面端）
  // ==========================================================================
  if (PlatformUtils.isDesktop) {
    await windowManager.ensureInitialized();

    final savedSize = StorageManager.getSetting<String>(SettingBoxKey.windowSize);
    final isMaximized = StorageManager.getSetting<bool>(SettingBoxKey.isWindowMaximized) ?? false;

    Size? windowSize;
    if (savedSize != null && savedSize.isNotEmpty) {
      try {
        final parts = savedSize.split('×');
        if (parts.length == 2) {
          final width = double.tryParse(parts[0]);
          final height = double.tryParse(parts[1]);
          if (width != null && height != null && width >= 400 && height >= 720) {
            windowSize = Size(width, height);
          }
        }
      } catch (_) {}
    }

    final windowOptions = WindowOptions(
      size: windowSize ?? const Size(1100, 720),
      minimumSize: const Size(400, 720),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: '源影',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (isMaximized) {
        await windowManager.maximize();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });

    windowManager.addListener(_WindowListener());

    if (Platform.isWindows) {
      final appSupportDir = await getApplicationSupportDirectory();
      if (await WebViewEnvironment.getAvailableVersion() != null) {
        webViewEnvironment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: path.join(appSupportDir.path, 'flutter_inappwebview'),
          ),
        );
      }
    }
  }

  // ==========================================================================
  // 第六步：主题初始化
  // ==========================================================================
  ThemeUtils.themeMode = ThemeUtils.getThemeType().toThemeMode;
  ThemeUtils.refreshTheme();

  // ==========================================================================
  // 第七步：系统 UI 配置
  // ==========================================================================
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // ==========================================================================
  // 第八步：设置全局 HttpOverrides
  // ==========================================================================
  HttpOverrides.global = _CustomHttpOverrides();

  // ===== 初始化 HTTP 客户端 =====
  HttpClientFactory.init();

  // ===== 缓存清理与更新检查 =====
  CacheManager.autoClearCache();

  // 延迟执行更新检查
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (SettingPref.autoUpdate) {
      Update.checkUpdate(true);
    }
  });

  // ==========================================================================
  // 第九步：注册全局控制器
  // ==========================================================================
  // 1. 猫影视日志服务（必须先初始化，供 NodeJSService 使用）
  await Get.putAsync<CatVodLogService>(() async {
    final service = CatVodLogService();
    await service.init();
    return service;
  });

  // 2. 其他服务
  Get.put(T4ApiService(), permanent: true);
  Get.put(Drpy2ApiService(), permanent: true);
  Get.put(CatvodOpenService(), permanent: true);
  Get.put(NodeJSService(), permanent: true);
  Get.put(NodeJSSpiderService(), permanent: true);
  Get.put(SourceManager(), permanent: true);
  Get.put(DanmakuController(), permanent: true);
  Get.put(ActionService(), permanent: true);
  Get.put(ActionRenderer(), permanent: true);
  Get.put(SearchFilterService(), permanent: true);
  Get.put(DebugLogService());
  Get.put(NovelTtsService(), permanent: true);
  await NovelFontService.init();

  // ==========================================================================
  // 第十步：启动应用
  // ==========================================================================
  WidgetsBinding.instance.addObserver(_AppLifecycleObserver());
  runApp(const MyApp());
}

// ============================================================================
// WindowListener 实现
// ============================================================================
class _WindowListener extends WindowListener {
  @override
  void onWindowResized() {
    windowManager.getSize().then((size) {
      if (size.width >= 400 && size.height >= 720) {
        StorageManager.setSetting(
          SettingBoxKey.windowSize,
          '${size.width.toInt()}×${size.height.toInt()}',
        );
      }
    });
  }

  @override
  void onWindowMaximized() {
    StorageManager.setSetting(SettingBoxKey.isWindowMaximized, true);
  }

  @override
  void onWindowUnmaximized() {
    StorageManager.setSetting(SettingBoxKey.isWindowMaximized, false);
  }

  @override
  void onWindowMoved() {}

  @override
  void onWindowClose() {}

  @override
  void onWindowMinimized() {}

  @override
  void onWindowRestored() {}

  @override
  void onWindowBlur() {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowEnterFullscreen() {}

  @override
  void onWindowLeaveFullscreen() {}

  @override
  void onWindowFocused() {}

  @override
  void onWindowUnfocused() {}
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static void _onBack() {
    if (SmartDialog.checkExist()) {
      SmartDialog.dismiss();
      return;
    }
    final navigator = Get.key.currentState;
    if (navigator?.canPop() == true) {
      navigator!.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '源影',
      debugShowCheckedModeBanner: false,

      // ===== 主题 =====
      theme: ThemeUtils.lightTheme,
      darkTheme: ThemeUtils.darkTheme,
      themeMode: ThemeUtils.themeMode,

      // ===== 滚动行为 =====
      scrollBehavior: PlatformUtils.isDesktop ? AppScrollBehavior() : null,

      // ===== 路由 =====
      initialRoute: '/',
      getPages: AppPages.routes,

      // ===== 页面过渡动画 - 从 SettingPref 读取，类型安全 =====
      defaultTransition: SettingPref.pageTransition,

      // ===== 字体大小 - 应用 textScaleFactor =====
      builder: (context, child) {
        // 获取字体大小设置
        final textScale = SettingPref.defaultTextScale;
        // 获取界面缩放设置
        final uiScale = SettingPref.uiScale;

        Widget app = FlutterSmartDialog.init(
          toastBuilder: CustomToast.new,
          loadingBuilder: LoadingWidget.new,
          notifyStyle: const FlutterSmartNotifyStyle(
            warningBuilder: NotifyWarning.new,
          ),
        )(context, child)!;

        // 应用字体大小
        app = MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: app,
        );

        if (PlatformUtils.isDesktop) {
          app = BackDetector(
            onBack: _onBack,
            child: app,
          );
        }
        return app;
      },

      navigatorObservers: [
        routeObserver,
        FlutterSmartDialog.observer,
      ],
    );
  }
}

/// 生产环境验证：全平台最优底层硬件解码矩阵
List<String> _getGlobalOptimalDecoders() {
  // 1. Windows 端：优先使用 D3D11 渲染架构，追加 NVDEC 压榨 NVIDIA 独显性能
  if (Platform.isWindows) {
    return ['D3D11', 'NVDEC', 'DXVA', 'FFmpeg']; 
  } 
  // 2. 苹果生态 (macOS & iOS)：强制优先走 Apple 官方原生 VideoToolbox (VT) 核心硬解
  else if (Platform.isMacOS || Platform.isIOS) {
    return ['VT', 'FFmpeg']; 
  } 
  // 3. 安卓端：强制优先走系统级 AMediaCodec 硬解（完美融合新版 Flutter 的 Impeller 引擎渲染）
  else if (Platform.isAndroid) {
    return ['AMediaCodec', 'FFmpeg']; 
  } 
  // 4. Linux 端：兼容常见的 VAAPI 与 VDPAU 显卡硬解方案
  else if (Platform.isLinux) {
    return ['VAAPI', 'VDPAU', 'FFmpeg']; 
  } 
  // 5. 鸿蒙等其他平台兜底
  return ['FFmpeg']; 
}