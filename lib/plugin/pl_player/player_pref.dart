import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:yuanying/utils/storage.dart';

/// 播放器内核类型
enum PlayerEngineType {
  mediaKit,  // 0: 默认 media_kit
  fvp,       // 1: FVP
}

/// 播放器独立配置类
/// 完全独立于项目原有配置系统，避免与 B站 Pref 冲突
class PlayerPref {
  static Box get _box => GStorage.setting;

  // ===== 基础配置 =====

  /// 震动反馈开关
  static bool get feedBackEnable => _box.get('feedBackEnable', defaultValue: false);
  static set feedBackEnable(bool value) => _box.put('feedBackEnable', value);

  /// 触控滑动阈值
  static double get touchSlopH => _box.get('touchSlopH', defaultValue: 16.0);
  static set touchSlopH(double value) => _box.put('touchSlopH', value);

  /// 屏幕角度（自动旋转灵敏度）
  static int get angleDegrees => _box.get('angleDegrees', defaultValue: 30);
  static set angleDegrees(int value) => _box.put('angleDegrees', value);

  // ===== 播放速度 =====

  /// 默认播放速度
  static double get playSpeedDefault => _box.get('playSpeedDefault', defaultValue: 1.0);
  static set playSpeedDefault(double value) => _box.put('playSpeedDefault', value);

  /// 长按倍速（默认3倍）
  static double get longPressSpeedDefault => _box.get('longPressSpeedDefault', defaultValue: 3.0);
  static set longPressSpeedDefault(double value) => _box.put('longPressSpeedDefault', value);

  /// 倍速列表
  static List<double> get speedList => _box.get('speedList', defaultValue: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0]);
  static set speedList(List<double> value) => _box.put('speedList', value);

  /// 长按自动加倍
  static bool get enableAutoLongPressSpeed => _box.get('enableAutoLongPressSpeed', defaultValue: false);
  static set enableAutoLongPressSpeed(bool value) => _box.put('enableAutoLongPressSpeed', value);

  // ===== 缓冲 =====

  /// 缓冲大小 (MB)
  static double get bufferSize => _box.get('bufferSize', defaultValue: 4.0);
  static set bufferSize(double value) => _box.put('bufferSize', value);

  /// 缓冲秒数
  static double get bufferSec => _box.get('bufferSec', defaultValue: 16.0);
  static set bufferSec(double value) => _box.put('bufferSec', value);

  // ===== 硬件解码 =====

  /// 启用硬件加速
  static bool get enableHA => _box.get('enableHA', defaultValue: true);
  static set enableHA(bool value) => _box.put('enableHA', value);

  /// 硬件解码类型
  static String get hardwareDecoding => _box.get('hardwareDecoding', defaultValue: 'auto');
  static set hardwareDecoding(String value) => _box.put('hardwareDecoding', value);

  // ===== 视频同步 =====

  static String get videoSync => _box.get('videoSync', defaultValue: 'display-resample');
  static set videoSync(String value) => _box.put('videoSync', value);

  static String get autosync => _box.get('autosync', defaultValue: '30');
  static set autosync(String value) => _box.put('autosync', value);

  // ===== 音频 =====

  static String get audioOutput => _box.get('audioOutput', defaultValue: 'opensles,aaudio,audiotrack');
  static set audioOutput(String value) => _box.put('audioOutput', value);

  static String get audioNormalization => _box.get('audioNormalization', defaultValue: '0');
  static set audioNormalization(String value) => _box.put('audioNormalization', value);

  static String get fallbackNormalization => _box.get('fallbackNormalization', defaultValue: '0');
  static set fallbackNormalization(String value) => _box.put('fallbackNormalization', value);

  // ===== 全屏 =====

  /// 全屏模式 (0=auto, 1=none, 2=vertical, 3=horizontal, 4=ratio, 5=gravity)
  static int get fullScreenMode => _box.get('fullScreenMode', defaultValue: 0);
  static set fullScreenMode(int value) => _box.put('fullScreenMode', value);

  /// 横屏模式
  static bool get horizontalScreen => _box.get('horizontalScreen', defaultValue: false);
  static set horizontalScreen(bool value) => _box.put('horizontalScreen', value);

  /// 自动进入全屏
  static bool get autoEnterFullScreen => _box.get('autoEnterFullScreen', defaultValue: false);
  static set autoEnterFullScreen(bool value) => _box.put('autoEnterFullScreen', value);

  /// 自动退出全屏
  static bool get autoExitFullscreen => _box.get('autoExitFullscreen', defaultValue: true);
  static set autoExitFullscreen(bool value) => _box.put('autoExitFullscreen', value);

  /// 移除安全区域
  static bool get removeSafeArea => _box.get('removeSafeArea', defaultValue: false);
  static set removeSafeArea(bool value) => _box.put('removeSafeArea', value);

  // ===== 控制栏 =====

  /// 底部进度条行为 (0=alwaysShow, 1=alwaysHide, 2=onlyShowFullScreen, 3=onlyHideFullScreen)
  static int get btmProgressBehavior => _box.get('btmProgressBehavior', defaultValue: 0);
  static set btmProgressBehavior(int value) => _box.put('btmProgressBehavior', value);

  /// 控制栏长显示
  static bool get enableLongShowControl => _box.get('enableLongShowControl', defaultValue: false);
  static set enableLongShowControl(bool value) => _box.put('enableLongShowControl', value);

  /// 全屏显示操作项
  static bool get showFSActionItem => _box.get('showFSActionItem', defaultValue: true);
  static set showFSActionItem(bool value) => _box.put('showFSActionItem', value);

  /// 全屏显示截图按钮
  static bool get showFsScreenshotBtn => _box.get('showFsScreenshotBtn', defaultValue: true);
  static set showFsScreenshotBtn(bool value) => _box.put('showFsScreenshotBtn', value);

  /// 全屏显示锁屏按钮
  static bool get showFsLockBtn => _box.get('showFsLockBtn', defaultValue: true);
  static set showFsLockBtn(bool value) => _box.put('showFsLockBtn', value);

  // ===== 手势 =====

  /// 滑动调节音量和亮度
  static bool get enableSlideVolumeBrightness => _box.get('enableSlideVolumeBrightness', defaultValue: true);
  static set enableSlideVolumeBrightness(bool value) => _box.put('enableSlideVolumeBrightness', value);

  /// 滑动切换全屏
  static bool get enableSlideFS => _box.get('enableSlideFS', defaultValue: true);
  static set enableSlideFS(bool value) => _box.put('enableSlideFS', value);

  /// 快进快退时长 (秒)
  static int get fastForBackwardDuration => _box.get('fastForBackwardDuration', defaultValue: 10);
  static set fastForBackwardDuration(int value) => _box.put('fastForBackwardDuration', value);

  /// 启用快速双击
  static bool get enableQuickDouble => _box.get('enableQuickDouble', defaultValue: true);
  static set enableQuickDouble(bool value) => _box.put('enableQuickDouble', value);

  /// 全屏手势反转
  static bool get fullScreenGestureReverse => _box.get('fullScreenGestureReverse', defaultValue: false);
  static set fullScreenGestureReverse(bool value) => _box.put('fullScreenGestureReverse', value);

  /// 使用相对滑动
  static bool get useRelativeSlide => _box.get('useRelativeSlide', defaultValue: false);
  static set useRelativeSlide(bool value) => _box.put('useRelativeSlide', value);

  /// 滑动时长 (毫秒)
  static int get sliderDuration => _box.get('sliderDuration', defaultValue: 90);
  static set sliderDuration(int value) => _box.put('sliderDuration', value);

  /// 键盘控制
  static bool get keyboardControl => _box.get('keyboardControl', defaultValue: true);
  static set keyboardControl(bool value) => _box.put('keyboardControl', value);

  /// 拖动字幕
  static bool get enableDragSubtitle => _box.get('enableDragSubtitle', defaultValue: false);
  static set enableDragSubtitle(bool value) => _box.put('enableDragSubtitle', value);

  // ===== 缩放 =====

  /// 启用缩小视频尺寸
  static bool get enableShrinkVideoSize => _box.get('enableShrinkVideoSize', defaultValue: true);
  static set enableShrinkVideoSize(bool value) => _box.put('enableShrinkVideoSize', value);

  /// UI缩放
  static double get uiScale => _box.get('uiScale', defaultValue: 1.0);
  static set uiScale(double value) => _box.put('uiScale', value);

  // ===== 视频适配 =====

  /// 缓存视频适配模式 (VideoFitType 索引)
  static int get cacheVideoFit => _box.get('cacheVideoFit', defaultValue: 1);
  static set cacheVideoFit(int value) => _box.put('cacheVideoFit', value);

  // ===== 播放重复模式 =====

  /// 播放重复模式 (PlayRepeat 索引)
  static int get playRepeat => _box.get('playRepeat', defaultValue: 0);
  static set playRepeat(int value) => _box.put('playRepeat', value);

  // ===== 字幕 =====

  static double get subtitleFontScale => _box.get('subtitleFontScale', defaultValue: 1.2);
  static set subtitleFontScale(double value) => _box.put('subtitleFontScale', value);

  static double get subtitleFontScaleFS => _box.get('subtitleFontScaleFS', defaultValue: 1.8);
  static set subtitleFontScaleFS(double value) => _box.put('subtitleFontScaleFS', value);

  static int get subtitlePaddingH => _box.get('subtitlePaddingH', defaultValue: 24);
  static set subtitlePaddingH(int value) => _box.put('subtitlePaddingH', value);

  static int get subtitlePaddingB => _box.get('subtitlePaddingB', defaultValue: 24);
  static set subtitlePaddingB(int value) => _box.put('subtitlePaddingB', value);

  static double get subtitleBgOpacity => _box.get('subtitleBgOpacity', defaultValue: 0.67);
  static set subtitleBgOpacity(double value) => _box.put('subtitleBgOpacity', value);

  static double get subtitleStrokeWidth => _box.get('subtitleStrokeWidth', defaultValue: 2.0);
  static set subtitleStrokeWidth(double value) => _box.put('subtitleStrokeWidth', value);

  static int get subtitleFontWeight => _box.get('subtitleFontWeight', defaultValue: 5);
  static set subtitleFontWeight(int value) => _box.put('subtitleFontWeight', value);

  // ===== 弹幕 =====

  static bool get enableShowDanmaku => _box.get('enableShowDanmaku', defaultValue: true);
  static set enableShowDanmaku(bool value) => _box.put('enableShowDanmaku', value);

  static bool get enableTapDm => _box.get('enableTapDm', defaultValue: true);
  static set enableTapDm(bool value) => _box.put('enableTapDm', value);

  static bool get mergeDanmaku => _box.get('mergeDanmaku', defaultValue: false);
  static set mergeDanmaku(bool value) => _box.put('mergeDanmaku', value);

  static double get danmakuFontScale => _box.get('danmakuFontScale', defaultValue: 1.0);
  static set danmakuFontScale(double value) => _box.put('danmakuFontScale', value);

  static double get danmakuFontScaleFS => _box.get('danmakuFontScaleFS', defaultValue: 1.2);
  static set danmakuFontScaleFS(double value) => _box.put('danmakuFontScaleFS', value);

  static double get danmakuShowArea => _box.get('danmakuShowArea', defaultValue: 0.5);
  static set danmakuShowArea(double value) => _box.put('danmakuShowArea', value);

  static double get danmakuDuration => _box.get('danmakuDuration', defaultValue: 7.0);
  static set danmakuDuration(double value) => _box.put('danmakuDuration', value);

  static double get danmakuStaticDuration => _box.get('danmakuStaticDuration', defaultValue: 4.0);
  static set danmakuStaticDuration(double value) => _box.put('danmakuStaticDuration', value);

  static double get danmakuStrokeWidth => _box.get('danmakuStrokeWidth', defaultValue: 1.5);
  static set danmakuStrokeWidth(double value) => _box.put('danmakuStrokeWidth', value);

  static int get danmakuFontWeight => _box.get('danmakuFontWeight', defaultValue: 5);
  static set danmakuFontWeight(int value) => _box.put('danmakuFontWeight', value);

  static double get danmakuLineHeight => _box.get('danmakuLineHeight', defaultValue: 1.6);
  static set danmakuLineHeight(double value) => _box.put('danmakuLineHeight', value);

  static double get danmakuOpacity => _box.get('danmakuOpacity', defaultValue: 1.0);
  static set danmakuOpacity(double value) => _box.put('danmakuOpacity', value);

  static bool get danmakuMassiveMode => _box.get('danmakuMassiveMode', defaultValue: false);
  static set danmakuMassiveMode(bool value) => _box.put('danmakuMassiveMode', value);

  static bool get danmakuStatic2Scroll => _box.get('danmakuStatic2Scroll', defaultValue: false);
  static set danmakuStatic2Scroll(bool value) => _box.put('danmakuStatic2Scroll', value);

  static bool get danmakuFixedV => _box.get('danmakuFixedV', defaultValue: false);
  static set danmakuFixedV(bool value) => _box.put('danmakuFixedV', value);

  static int get danmakuWeight => _box.get('danmakuWeight', defaultValue: 0);
  static set danmakuWeight(int value) => _box.put('danmakuWeight', value);

  static Set<int> get danmakuBlockType {
    final list = _box.get('danmakuBlockType', defaultValue: <int>[]);
    return Set<int>.from(list);
  }
  static set danmakuBlockType(Set<int> value) => _box.put('danmakuBlockType', value.toList());

  // 弹幕颜色模式：0=默认（使用原始颜色），1=随机彩色，2=渐变彩色
  static int get danmakuColorMode => _box.get('danmakuColorMode', defaultValue: 0);
  static set danmakuColorMode(int value) => _box.put('danmakuColorMode', value);

  // ===== 后台播放 =====

  static bool get continuePlayInBackground => _box.get('continuePlayInBackground', defaultValue: false);
  static set continuePlayInBackground(bool value) => _box.put('continuePlayInBackground', value);

  static bool get continuePlayingPart => _box.get('continuePlayingPart', defaultValue: true);
  static set continuePlayingPart(bool value) => _box.put('continuePlayingPart', value);

  // ===== 画中画 =====

  static bool get autoPiP => _box.get('autoPiP', defaultValue: false);
  static set autoPiP(bool value) => _box.put('autoPiP', value);

  static bool get pipNoDanmaku => _box.get('pipNoDanmaku', defaultValue: false);
  static set pipNoDanmaku(bool value) => _box.put('pipNoDanmaku', value);

  // ===== 其他 =====

  static bool get preInitPlayer => _box.get('preInitPlayer', defaultValue: false);
  static set preInitPlayer(bool value) => _box.put('preInitPlayer', value);

  static bool get tempPlayerConf => _box.get('tempPlayerConf', defaultValue: false);
  static set tempPlayerConf(bool value) => _box.put('tempPlayerConf', value);

  static bool get darkVideoPage => _box.get('darkVideoPage', defaultValue: false);
  static set darkVideoPage(bool value) => _box.put('darkVideoPage', value);

  static bool get showSeekPreview => _box.get('showSeekPreview', defaultValue: false);
  static set showSeekPreview(bool value) => _box.put('showSeekPreview', value);

  static bool get showViewPoints => _box.get('showViewPoints', defaultValue: true);
  static set showViewPoints(bool value) => _box.put('showViewPoints', value);

  static bool get showRelatedVideo => _box.get('showRelatedVideo', defaultValue: true);
  static set showRelatedVideo(bool value) => _box.put('showRelatedVideo', value);

  static bool get showDmChart => _box.get('showDmChart', defaultValue: false);
  static set showDmChart(bool value) => _box.put('showDmChart', value);

  static bool get showWindowTitleBar => _box.get('showWindowTitleBar', defaultValue: true);
  static set showWindowTitleBar(bool value) => _box.put('showWindowTitleBar', value);

  static bool get enableVerticalExpand => _box.get('enableVerticalExpand', defaultValue: false);
  static set enableVerticalExpand(bool value) => _box.put('enableVerticalExpand', value);

  static bool get autoPlayEnable => _box.get('autoPlayEnable', defaultValue: false);
  static set autoPlayEnable(bool value) => _box.put('autoPlayEnable', value);

  static bool get horizontalSeasonPanel => _box.get('horizontalSeasonPanel', defaultValue: false);
  static set horizontalSeasonPanel(bool value) => _box.put('horizontalSeasonPanel', value);

  static bool get horizontalPreview => _box.get('horizontalPreview', defaultValue: false);
  static set horizontalPreview(bool value) => _box.put('horizontalPreview', value);

  static bool get reverseFromFirst => _box.get('reverseFromFirst', defaultValue: true);
  static set reverseFromFirst(bool value) => _box.put('reverseFromFirst', value);

  /// 系统亮度控制
  static bool get setSystemBrightness => _box.get('setSystemBrightness', defaultValue: false);
  static set setSystemBrightness(bool value) => _box.put('setSystemBrightness', value);

  /// 音量 (移动端)
  static double get playerVolume => _box.get('playerVolume', defaultValue: 100.0);
  static set playerVolume(double value) => _box.put('playerVolume', value);

  /// 最大音量 (桌面端)
  static double get maxVolume => _box.get('maxVolume', defaultValue: 2.0);
  static set maxVolume(double value) => _box.put('maxVolume', value);

  /// 桌面端音量
  static double get desktopVolume => _box.get('desktopVolume', defaultValue: 1.0);
  static set desktopVolume(double value) => _box.put('desktopVolume', value);

  /// 历史记录暂停
  static bool get historyPause => _box.get('historyPause', defaultValue: false);
  static set historyPause(bool value) => _box.put('historyPause', value);

  // ===== 分段跳过配置 =====

  static int? getSkipTypeForSegment(int segmentIndex) {
    final key = 'skipType_$segmentIndex';
    return _box.get(key);
  }

  static void setSkipTypeForSegment(int segmentIndex, int skipTypeIndex) {
    final key = 'skipType_$segmentIndex';
    _box.put(key, skipTypeIndex);
  }

  static int get pgcSkipType => _box.get('pgcSkipType', defaultValue: 1);
  static set pgcSkipType(int value) => _box.put('pgcSkipType', value);

  // 低亮度颜色
  static const String _reduceLuxColorKey = 'reduceLuxColor';

  /// 低亮度颜色，null 表示不启用
  static Color? get reduceLuxColor {
    final int? color = _box.get(_reduceLuxColorKey);
    if (color != null && color != 0xFFFFFFFF) { // 排除白色（可能代表无效）
      return Color(color);
    }
    return null;
  }

  static set reduceLuxColor(Color? color) {
    if (color == null) {
      _box.delete(_reduceLuxColorKey);
    } else {
      _box.put(_reduceLuxColorKey, color.value);
    }
  }

  // ===== 播放请求头策略 =====
  /// 0: 智能模式（推荐），1: 完整模式，2: 最小模式
  static int get requestHeaderStrategy => _box.get('requestHeaderStrategy', defaultValue: 0);
  static set requestHeaderStrategy(int value) => _box.put('requestHeaderStrategy', value);

  // ===== 解析模式 =====
  /// 0: 顺序解析（依次尝试），1: 并发解析（同时调用所有）
  static int get parseMode => _box.get('parseMode', defaultValue: 0);
  static set parseMode(int value) => _box.put('parseMode', value);

  // ===== 推送模式 =====
  /// 0: 手动推送，1: 自动模式
  static int get pushMode => _box.get('pushMode', defaultValue: 0);
  static set pushMode(int value) => _box.put('pushMode', value);

  // ===== 全屏电池电量 =====
  static bool get showBatteryLevel => _box.get('showBatteryLevel', defaultValue: true);
  static set showBatteryLevel(bool value) => _box.put('showBatteryLevel', value);

  // ===== 播放器多内核 =====
  static PlayerEngineType get playerEngine {
    final index = _box.get('playerEngine', defaultValue: 0);
    if (index >= 0 && index < PlayerEngineType.values.length) {
      return PlayerEngineType.values[index];
    }
    return PlayerEngineType.mediaKit;
  }
  static set playerEngine(PlayerEngineType value) {
    _box.put('playerEngine', value.index);
  }
}