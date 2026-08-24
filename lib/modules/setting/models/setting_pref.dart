import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/models/common/bar_hide_type.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/utils/storage_manager.dart';

/// 外观设置偏好管理
abstract final class SettingPref {
  // ============================================================
  // 字体
  // ============================================================

  static int get appFontWeight {
    final dynamic raw = StorageManager.getSetting<dynamic>(SettingBoxKey.appFontWeight);
    if (raw is int) return raw;
    if (raw is bool) {
      final fixed = raw ? 4 : -1;
      StorageManager.setSetting(SettingBoxKey.appFontWeight, fixed);
      return fixed;
    }
    return -1;
  }
  static set appFontWeight(int v) {
    StorageManager.setSetting(SettingBoxKey.appFontWeight, v);
  }

  static double get defaultTextScale =>
      StorageManager.getSetting<double>(SettingBoxKey.defaultTextScale) ?? 1.0;
  static set defaultTextScale(double v) =>
      StorageManager.setSetting(SettingBoxKey.defaultTextScale, v);

  // ============================================================
  // 界面缩放
  // ============================================================

  static double get uiScale =>
      StorageManager.getSetting<double>(SettingBoxKey.uiScale) ?? 1.0;
  static set uiScale(double v) =>
      StorageManager.setSetting(SettingBoxKey.uiScale, v);

  // ============================================================
  // 页面过渡动画
  // ============================================================

  static Transition get pageTransition {
    // 修复：从存储读取 int，安全转换为 Transition
    final index = StorageManager.getSetting<int>(SettingBoxKey.pageTransition);
    if (index == null || index < 0 || index >= Transition.values.length) {
      return Transition.cupertino;
    }
    return Transition.values[index];
  }
  static set pageTransition(Transition v) =>
      StorageManager.setSetting(SettingBoxKey.pageTransition, v.index);

  // ============================================================
  // 列表宽度
  // ============================================================

  static double get recommendCardWidth =>
      StorageManager.getSetting<double>(SettingBoxKey.recommendCardWidth) ?? 240.0;
  static set recommendCardWidth(double v) =>
      StorageManager.setSetting(SettingBoxKey.recommendCardWidth, v);

  static double get smallCardWidth =>
      StorageManager.getSetting<double>(SettingBoxKey.smallCardWidth) ?? 240.0;
  static set smallCardWidth(double v) =>
      StorageManager.setSetting(SettingBoxKey.smallCardWidth, v);

  // ============================================================
  // 底栏
  // ============================================================

  static bool get floatingNavBar =>
      StorageManager.getSetting<bool>(SettingBoxKey.floatingNavBar) ?? false;
  static set floatingNavBar(bool v) =>
      StorageManager.setSetting(SettingBoxKey.floatingNavBar, v);

  // ============================================================
  // 播放页
  // ============================================================

  static bool get removeSafeArea =>
      StorageManager.getSetting<bool>(SettingBoxKey.removeSafeArea) ?? false;
  static set removeSafeArea(bool v) =>
      StorageManager.setSetting(SettingBoxKey.removeSafeArea, v);

  static bool get darkVideoPage =>
      StorageManager.getSetting<bool>(SettingBoxKey.darkVideoPage) ?? false;
  static set darkVideoPage(bool v) =>
      StorageManager.setSetting(SettingBoxKey.darkVideoPage, v);

  // ============================================================
  // 顶/底栏收齐
  // ============================================================

  static BarHideType get barHideType {
    final index = StorageManager.getSetting<int>(SettingBoxKey.barHideType);
    return BarHideType.values[index ?? BarHideType.sync.index];
  }
  static set barHideType(BarHideType v) =>
      StorageManager.setSetting(SettingBoxKey.barHideType, v.index);

  static bool get hideTopBar =>
      StorageManager.getSetting<bool>(SettingBoxKey.hideTopBar) ?? true;
  static set hideTopBar(bool v) =>
      StorageManager.setSetting(SettingBoxKey.hideTopBar, v);

  static bool get hideBottomBar =>
      StorageManager.getSetting<bool>(SettingBoxKey.hideBottomBar) ?? false;
  static set hideBottomBar(bool v) =>
      StorageManager.setSetting(SettingBoxKey.hideBottomBar, v);

  // ============================================================
  // 默认启动页
  // ============================================================

  static NavigationBarType get defaultHomePage {
    final index = StorageManager.getSetting<int>(SettingBoxKey.defaultHomePage);
    if (index == null || index < 0 || index >= NavigationBarType.values.length) {
      return NavigationBarType.home;
    }
    return NavigationBarType.values[index];
  }
  static set defaultHomePage(NavigationBarType v) =>
      StorageManager.setSetting(SettingBoxKey.defaultHomePage, v.index);

  // ============================================================
  // 弹簧参数
  // ============================================================

  static List<double> get springDescription =>
      StorageManager.getSetting<List<double>>(SettingBoxKey.springDescription) ??
      [0.5, 100.0, 2.2 * 7.071];
  static set springDescription(List<double> v) =>
      StorageManager.setSetting(SettingBoxKey.springDescription, v);

  // ============================================================
  // Navbar排序
  // ============================================================

  static List<int>? get navBarSort =>
      StorageManager.getSetting<List<int>>(SettingBoxKey.navBarSort);
  static set navBarSort(List<int>? v) =>
      StorageManager.setSetting(SettingBoxKey.navBarSort, v);

  // ============================================================
  // 其它设置
  // ============================================================

  static bool get badCertificateCallback =>
      StorageManager.getSetting<bool>(SettingBoxKey.badCertificateCallback) ?? false;
  static set badCertificateCallback(bool v) =>
      StorageManager.setSetting(SettingBoxKey.badCertificateCallback, v);

  static bool get enableHttp2 =>
      StorageManager.getSetting<bool>(SettingBoxKey.enableHttp2) ?? false;
  static set enableHttp2(bool v) =>
      StorageManager.setSetting(SettingBoxKey.enableHttp2, v);

  static double get touchSlopH =>
      StorageManager.getSetting<double>(SettingBoxKey.touchSlopH) ?? 40.0;
  static set touchSlopH(double v) =>
      StorageManager.setSetting(SettingBoxKey.touchSlopH, v);

  static double get refreshDragPercentage =>
      StorageManager.getSetting<double>(SettingBoxKey.refreshDragPercentage) ?? 0.25;
  static set refreshDragPercentage(double v) =>
      StorageManager.setSetting(SettingBoxKey.refreshDragPercentage, v);

  static double get refreshDisplacement =>
      StorageManager.getSetting<double>(SettingBoxKey.refreshDisplacement) ?? 40.0;
  static set refreshDisplacement(double v) =>
      StorageManager.setSetting(SettingBoxKey.refreshDisplacement, v);

  static bool get autoClearCache =>
      StorageManager.getSetting<bool>(SettingBoxKey.autoClearCache) ?? false;
  static set autoClearCache(bool v) =>
      StorageManager.setSetting(SettingBoxKey.autoClearCache, v);

  static num get maxCacheSize =>
      StorageManager.getSetting<num>(SettingBoxKey.maxCacheSize) ?? 0;
  static set maxCacheSize(num v) =>
      StorageManager.setSetting(SettingBoxKey.maxCacheSize, v);

  static bool get autoUpdate =>
      StorageManager.getSetting<bool>(SettingBoxKey.autoUpdate) ?? true;
  static set autoUpdate(bool v) =>
      StorageManager.setSetting(SettingBoxKey.autoUpdate, v);

  static bool get slideDismissReplyPage =>
    StorageManager.getSetting<bool>(SettingBoxKey.slideDismissReplyPage) ?? false;
  static set slideDismissReplyPage(bool v) =>
    StorageManager.setSetting(SettingBoxKey.slideDismissReplyPage, v);

  static bool get enableShrinkVideoSize =>
    StorageManager.getSetting<bool>(SettingBoxKey.enableShrinkVideoSize) ?? true;
  static set enableShrinkVideoSize(bool v) =>
      StorageManager.setSetting(SettingBoxKey.enableShrinkVideoSize, v);

  static bool get feedBackEnable =>
      StorageManager.getSetting<bool>(SettingBoxKey.feedBackEnable) ?? false;
  static set feedBackEnable(bool v) =>
      StorageManager.setSetting(SettingBoxKey.feedBackEnable, v);

  // ============================================================
  // 代理设置
  // ============================================================

  static bool get enableSystemProxy =>
      StorageManager.getSetting<bool>(SettingBoxKey.enableSystemProxy) ?? false;
  static set enableSystemProxy(bool v) =>
      StorageManager.setSetting(SettingBoxKey.enableSystemProxy, v);

  static String get systemProxyHost =>
      StorageManager.getSetting<String>(SettingBoxKey.systemProxyHost) ?? '';
  static set systemProxyHost(String v) =>
      StorageManager.setSetting(SettingBoxKey.systemProxyHost, v);

  static String get systemProxyPort =>
      StorageManager.getSetting<String>(SettingBoxKey.systemProxyPort) ?? '';
  static set systemProxyPort(String v) =>
      StorageManager.setSetting(SettingBoxKey.systemProxyPort, v);

  // ============================================================
  // WebDAV 设置
  // ============================================================

  static String get webdavUri =>
      StorageManager.getSetting<String>(SettingBoxKey.webdavUri) ?? '';
  static set webdavUri(String v) =>
      StorageManager.setSetting(SettingBoxKey.webdavUri, v);

  static String get webdavUsername =>
      StorageManager.getSetting<String>(SettingBoxKey.webdavUsername) ?? '';
  static set webdavUsername(String v) =>
      StorageManager.setSetting(SettingBoxKey.webdavUsername, v);

  static String get webdavPassword =>
      StorageManager.getSetting<String>(SettingBoxKey.webdavPassword) ?? '';
  static set webdavPassword(String v) =>
      StorageManager.setSetting(SettingBoxKey.webdavPassword, v);

  static String get webdavDirectory =>
      StorageManager.getSetting<String>(SettingBoxKey.webdavDirectory) ?? '/';
  static set webdavDirectory(String v) =>
      StorageManager.setSetting(SettingBoxKey.webdavDirectory, v);

  // ============================================================
  // 返回时直接退出
  // ============================================================

  static bool get directExitOnBack =>
      StorageManager.getSetting<bool>(SettingBoxKey.directExitOnBack) ?? false;
  static set directExitOnBack(bool v) =>
      StorageManager.setSetting(SettingBoxKey.directExitOnBack, v);

  static NavigationBarStyle get navigationBarStyle {
    final index = StorageManager.getSetting<int>(SettingBoxKey.navigationBarStyle);
    return NavigationBarStyle.values[index ?? 0];
  }
  static set navigationBarStyle(NavigationBarStyle v) =>
      StorageManager.setSetting(SettingBoxKey.navigationBarStyle, v.index);

  static bool get enableDebugLog =>
      StorageManager.getSetting<bool>(SettingBoxKey.enableDebugLog) ?? false;
  static set enableDebugLog(bool v) =>
      StorageManager.setSetting(SettingBoxKey.enableDebugLog, v);

  // ============================================================
  // 弹幕API配置
  // ============================================================

  static List<Map<String, dynamic>> get danmakuApis {
    final data = StorageManager.getSetting<List<dynamic>>(SettingBoxKey.danmakuApis);
    if (data == null) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  static set danmakuApis(List<Map<String, dynamic>> v) =>
      StorageManager.setSetting(SettingBoxKey.danmakuApis, v);

  static String get danmakuCurrentKey =>
      StorageManager.getSetting<String>(SettingBoxKey.danmakuCurrentKey) ?? '';
  static set danmakuCurrentKey(String v) =>
      StorageManager.setSetting(SettingBoxKey.danmakuCurrentKey, v);

  static bool get danmakuAutoMatch =>
      StorageManager.getSetting<bool>(SettingBoxKey.danmakuAutoMatch) ?? false;
  static set danmakuAutoMatch(bool v) =>
      StorageManager.setSetting(SettingBoxKey.danmakuAutoMatch, v);

  // ============================================================
  // TMDB 配置
  // ============================================================

  static String get tmdbAccessToken =>
      StorageManager.getSetting<String>(SettingBoxKey.tmdbAccessToken) ?? '';
  static set tmdbAccessToken(String v) =>
      StorageManager.setSetting(SettingBoxKey.tmdbAccessToken, v);

  static String get tmdbApiProxy =>
      StorageManager.getSetting<String>(SettingBoxKey.tmdbApiProxy) ?? 'https://api.tmdb.org';
  static set tmdbApiProxy(String v) =>
      StorageManager.setSetting(SettingBoxKey.tmdbApiProxy, v);

  static String get tmdbImageProxy =>
      StorageManager.getSetting<String>(SettingBoxKey.tmdbImageProxy) ?? 'https://images.tmdb.org/t/p';
  static set tmdbImageProxy(String v) =>
      StorageManager.setSetting(SettingBoxKey.tmdbImageProxy, v);
}