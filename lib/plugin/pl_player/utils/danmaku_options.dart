import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/utils/extension/box_ext.dart';

abstract final class DanmakuOptions {
  static Set<int> get blockTypes => PlayerPref.danmakuBlockType;
  static bool get blockColorful => blockTypes.contains(6);

  static int get danmakuWeight => PlayerPref.danmakuWeight;
  static double get danmakuFontScaleFS => PlayerPref.danmakuFontScaleFS;
  static double get danmakuFontScale => PlayerPref.danmakuFontScale;
  static int get danmakuFontWeight => PlayerPref.danmakuFontWeight;
  static double get danmakuShowArea => PlayerPref.danmakuShowArea;
  static double get danmakuDuration => PlayerPref.danmakuDuration;
  static double get danmakuStaticDuration => PlayerPref.danmakuStaticDuration;
  static double get danmakuStrokeWidth => PlayerPref.danmakuStrokeWidth;
  static bool get danmakuFixedV => PlayerPref.danmakuFixedV;
  static bool get danmakuStatic2Scroll => PlayerPref.danmakuStatic2Scroll;
  static bool get danmakuMassiveMode => PlayerPref.danmakuMassiveMode;
  static double get danmakuLineHeight => PlayerPref.danmakuLineHeight;

  static bool get sameFontScale => danmakuFontScale == danmakuFontScaleFS;

  static DanmakuOption get({
    required bool notFullscreen,
    double speed = 1.0,
  }) {
    return DanmakuOption(
      fontSize: 15 * (notFullscreen ? danmakuFontScale : danmakuFontScaleFS),
      fontWeight: danmakuFontWeight,
      area: danmakuShowArea,
      duration: danmakuDuration / speed,
      staticDuration: danmakuStaticDuration / speed,
      hideBottom: blockTypes.contains(4),
      hideScroll: blockTypes.contains(2),
      hideTop: blockTypes.contains(5),
      hideSpecial: blockTypes.contains(7),
      strokeWidth: danmakuStrokeWidth,
      scrollFixedVelocity: danmakuFixedV,
      massiveMode: danmakuMassiveMode,
      static2Scroll: danmakuStatic2Scroll,
      safeArea: true,
      lineHeight: danmakuLineHeight,
    );
  }

  static Future<void>? save(double danmakuOpacity) {
    return GStorage.setting.putAllNE({
      SettingBoxKey.danmakuBlockType: blockTypes.toList(),
      SettingBoxKey.danmakuShowArea: danmakuShowArea,
      SettingBoxKey.danmakuFontScale: danmakuFontScale,
      SettingBoxKey.danmakuFontScaleFS: danmakuFontScaleFS,
      SettingBoxKey.danmakuDuration: danmakuDuration,
      SettingBoxKey.danmakuStaticDuration: danmakuStaticDuration,
      SettingBoxKey.danmakuStrokeWidth: danmakuStrokeWidth,
      SettingBoxKey.danmakuFontWeight: danmakuFontWeight,
      SettingBoxKey.danmakuLineHeight: danmakuLineHeight,
      SettingBoxKey.danmakuMassiveMode: danmakuMassiveMode,
      SettingBoxKey.danmakuStatic2Scroll: danmakuStatic2Scroll,
      SettingBoxKey.danmakuFixedV: danmakuFixedV,
      SettingBoxKey.danmakuWeight: danmakuWeight,
      SettingBoxKey.danmakuOpacity: danmakuOpacity,
    });
  }
}