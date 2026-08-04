abstract final class StorageKeys {
  // Hive Box 名称
  static const String settingBox = 'app_settings';
  static const String cacheBox = 'app_cache';

  // T4 相关
  static const String t4Sites = 't4_sites';
  static const String t4CurrentSiteKey = 't4_current_site_key';

  // 历史记录
  static const String historyList = 'history_list';

  // 收藏
  static const String favoriteFolders = 'favorite_folders';

  // 设置 - 主题
  static const String themeMode = 'theme_mode';
  static const String customColor = 'custom_color';
  static const String pureBlackTheme = 'pure_black_theme';
}

/// 存储键值定义
abstract final class SettingBoxKey {
  static const String desktopVolume = 'desktopVolume';
  static const String enableBackgroundPlay = 'enableBackgroundPlay';
  static const String subtitleFontScale = 'subtitleFontScale';
  static const String subtitleFontScaleFS = 'subtitleFontScaleFS';
  static const String subtitlePaddingH = 'subtitlePaddingH';
  static const String subtitlePaddingB = 'subtitlePaddingB';
  static const String subtitleBgOpacity = 'subtitleBgOpacity';
  static const String subtitleStrokeWidth = 'subtitleStrokeWidth';
  static const String subtitleFontWeight = 'subtitleFontWeight';
  static const String defaultVideoQa = 'defaultVideoQa';
  static const String defaultVideoQaCellular = 'defaultVideoQaCellular';
  static const String superResolutionType = 'superResolutionType';
  static const String continuePlayInBackground = 'continuePlayInBackground';
  static const String tempPlayerConf = 'tempPlayerConf';
  static const String danmakuBlockType = 'danmakuBlockType';
  static const String danmakuShowArea = 'danmakuShowArea';
  static const String danmakuFontScale = 'danmakuFontScale';
  static const String danmakuFontScaleFS = 'danmakuFontScaleFS';
  static const String danmakuDuration = 'danmakuDuration';
  static const String danmakuStaticDuration = 'danmakuStaticDuration';
  static const String danmakuStrokeWidth = 'danmakuStrokeWidth';
  static const String danmakuFontWeight = 'danmakuFontWeight';
  static const String danmakuLineHeight = 'danmakuLineHeight';
  static const String danmakuMassiveMode = 'danmakuMassiveMode';
  static const String danmakuStatic2Scroll = 'danmakuStatic2Scroll';
  static const String danmakuFixedV = 'danmakuFixedV';
  static const String danmakuWeight = 'danmakuWeight';
  static const String danmakuOpacity = 'danmakuOpacity';
  static const String enableShowDanmaku = 'enableShowDanmaku';
  static const String enableLongShowControl = 'enableLongShowControl';
  static const String bufferSize = 'bufferSize';
  static const String bufferSec = 'bufferSec';
  static const String audioOutput = 'audioOutput';
  static const String videoSync = 'videoSync';
  static const String autosync = 'autosync';
  static const String fullScreenMode = 'fullScreenMode';
  static const String btmProgressBehavior = 'btmProgressBehavior';
  static const String useRelativeSlide = 'useRelativeSlide';
  static const String sliderDuration = 'sliderDuration';
  static const String cacheVideoFit = 'cacheVideoFit';
  static const String setSystemBrightness = 'setSystemBrightness';
  static const String playerVolume = 'playerVolume';
  static const String maxVolume = 'maxVolume';
  static const String angleDegrees = 'angleDegrees';
  static const String fastForBackwardDuration = 'fastForBackwardDuration';
  static const String enableQuickDouble = 'enableQuickDouble';
  static const String fullScreenGestureReverse = 'fullScreenGestureReverse';
  static const String showSeekPreview = 'showSeekPreview';
  static const String showViewPoints = 'showViewPoints';
  static const String showRelatedVideo = 'showRelatedVideo';
  static const String darkVideoPage = 'darkVideoPage';
  static const String preInitPlayer = 'preInitPlayer';
  static const String removeSafeArea = 'removeSafeArea';
  static const String autoPiP = 'autoPiP';
  static const String enableHA = 'enableHA';
  static const String hardwareDecoding = 'hardwareDecoding';
  static const String playSpeedDefault = 'playSpeedDefault';
  static const String longPressSpeedDefault = 'longPressSpeedDefault';
  static const String showFSActionItem = 'showFSActionItem';
  static const String enableShrinkVideoSize = 'enableShrinkVideoSize';
  static const String enableSlideVolumeBrightness = 'enableSlideVolumeBrightness';
  static const String enableSlideFS = 'enableSlideFS';
  static const String enableDragSubtitle = 'enableDragSubtitle';
  static const String showFsScreenshotBtn = 'showFsScreenshotBtn';
  static const String showFsLockBtn = 'showFsLockBtn';
  static const String keyboardControl = 'keyboardControl';
  static const String uiScale = 'uiScale';
  static const String autoEnterFullScreen = 'autoEnterFullScreen';
  static const String autoExitFullscreen = 'autoExitFullscreen';
  static const String autoPlayEnable = 'autoPlayEnable';
  static const String enableVerticalExpand = 'enableVerticalExpand';
  static const String pipNoDanmaku = 'pipNoDanmaku';
  static const String showWindowTitleBar = 'showWindowTitleBar';
  static const String feedBackEnable = 'feedBackEnable';
  static const String touchSlopH = 'touchSlopH';
  static const String horizontalScreen = 'horizontalScreen';
  static const String playRepeat = 'playRepeat';
  static const String audioNormalization = 'audioNormalization';
  static const String fallbackNormalization = 'fallbackNormalization';
  static const String historyPause = 'historyPause';
  static const String continuePlayingPart = 'continuePlayingPart';
  static const String enableTapDm = 'enableTapDm';
  static const String mergeDanmaku = 'mergeDanmaku';
  static const String enableAutoLongPressSpeed = 'enableAutoLongPressSpeed';
  static const String horizontalSeasonPanel = 'horizontalSeasonPanel';
  static const String horizontalPreview = 'horizontalPreview';
  static const String reverseFromFirst = 'reverseFromFirst';
  static const String showDmChart = 'showDmChart';

  static const String pageTransition = 'pageTransition';
  static const String dynamicColor = 'dynamicColor';
  static const String schemeVariant = 'schemeVariant';
  static const String windowSize = 'windowSize';
  static const String isWindowMaximized = 'isWindowMaximized';
  static const String enableLog = 'enableLog';
  static const String badCertificateCallback = 'badCertificateCallback';
  static const String toastOpacity = 'toastOpacity';
  static const String displayMode = 'displayMode';
  static const String downloadPath = 'downloadPath';

  // ===== 外观设置相关 =====
  static const String appFontWeight = 'appFontWeight';
  static const String defaultTextScale = 'textScale';
  static const String floatingNavBar = 'floatingNavBar';
  static const String barHideType = 'barHideType';
  static const String defaultHomePage = 'defaultHomePage';
  static const String springDescription = 'springDescription';
  static const String navBarSort = 'navBarSort';
  static const String directExitOnBack = 'directExitOnBack';
  static const String smallCardWidth = 'smallCardWidth';
  static const String recommendCardWidth = 'recommendCardWidth';
  static const String hideTopBar = 'hideSearchBar';
  static const String hideBottomBar = 'hideTabBar';
  static const String navigationBarStyle = 'navigation_bar_style';

  // ===== 其它设置 =====
  static const String refreshDragPercentage = 'refreshDragPercentage';
  static const String refreshDisplacement = 'refreshDisplacement';
  static const String autoClearCache = 'autoClearCache';
  static const String maxCacheSize = 'maxCacheSize';
  static const String autoUpdate = 'autoUpdate';
  static const String enableHttp2 = 'enableHttp2';
  static const String enableSystemProxy = 'enableSystemProxy';
  static const String systemProxyHost = 'systemProxyHost';
  static const String systemProxyPort = 'systemProxyPort';
  static const String slideDismissReplyPage = 'slideDismissReplyPage';

  // ===== WebDAV 设置 =====
  static const String webdavUri = 'webdav_uri';
  static const String webdavUsername = 'webdav_username';
  static const String webdavPassword = 'webdav_password';
  static const String webdavDirectory = 'webdav_directory';

  /// 调试日志总开关
  static const String enableDebugLog = 'enableDebugLog';

  static const String lastSelectedSiteKey = 'last_selected_site_key';

  static const String localFileScanPaths = 'local_file_scan_paths';
}

abstract final class VideoBoxKey {
  static const String cacheVideoFit = 'cacheVideoFit';
  static const String playRepeat = 'playRepeat';
  static const String playSpeedDefault = 'playSpeedDefault';
  static const String longPressSpeedDefault = 'longPressSpeedDefault';
  static const String speedsList = 'speedsList';
}

abstract final class LocalCacheKey {
  static const String blackMids = 'blackMids';
  static const String danmakuFilterRules = 'danmakuFilterRules';
  static const String buvid = 'buvid';
  static const String historyPause = 'historyPause';
}