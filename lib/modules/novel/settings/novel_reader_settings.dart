// lib/modules/novel/settings/novel_reader_settings.dart
import 'package:flutter/material.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

// ============================================================================
// 阅读器设置
// ============================================================================
class NovelReaderSettings {
  static double fontSize = 20;
  static double lineHeight = 1.9;
  static int themeIndex = 0; // 默认暗夜（索引5对应 dark）
  static double paragraphGap = 10;
  static bool pagedMode = true;
  static double letterSpacing = 0;
  static double pagePadding = 22;
  static String fontKey = 'system';
  static String customFontFamily = '';
  static double screenDim = 0;
  static String pageAnim = 'cover'; // 默认覆盖动画

  static Future<void> load() async {
    fontSize = StorageManager.getSetting<double>(SettingBoxKey.novelFontSize) ?? 20;
    lineHeight = StorageManager.getSetting<double>(SettingBoxKey.novelLineHeight) ?? 1.9;
    themeIndex = StorageManager.getSetting<int>(SettingBoxKey.novelThemeIndex) ?? 5;
    paragraphGap = StorageManager.getSetting<double>(SettingBoxKey.novelParagraphGap) ?? 10;
    pagedMode = StorageManager.getSetting<bool>(SettingBoxKey.novelPagedMode) ?? true;
    letterSpacing = StorageManager.getSetting<double>(SettingBoxKey.novelLetterSpacing) ?? 0;
    pagePadding = StorageManager.getSetting<double>(SettingBoxKey.novelPagePadding) ?? 22;
    fontKey = StorageManager.getSetting<String>(SettingBoxKey.novelFontKey) ?? 'system';
    customFontFamily = StorageManager.getSetting<String>(SettingBoxKey.novelCustomFontFamily) ?? '';
    screenDim = StorageManager.getSetting<double>(SettingBoxKey.novelScreenDim) ?? 0;
    pageAnim = StorageManager.getSetting<String>(SettingBoxKey.novelPageAnim) ?? 'cover';
  }

  static Future<void> save() async {
    await StorageManager.setSetting(SettingBoxKey.novelFontSize, fontSize);
    await StorageManager.setSetting(SettingBoxKey.novelLineHeight, lineHeight);
    await StorageManager.setSetting(SettingBoxKey.novelThemeIndex, themeIndex);
    await StorageManager.setSetting(SettingBoxKey.novelParagraphGap, paragraphGap);
    await StorageManager.setSetting(SettingBoxKey.novelPagedMode, pagedMode);
    await StorageManager.setSetting(SettingBoxKey.novelLetterSpacing, letterSpacing);
    await StorageManager.setSetting(SettingBoxKey.novelPagePadding, pagePadding);
    await StorageManager.setSetting(SettingBoxKey.novelFontKey, fontKey);
    await StorageManager.setSetting(SettingBoxKey.novelCustomFontFamily, customFontFamily);
    await StorageManager.setSetting(SettingBoxKey.novelScreenDim, screenDim);
    await StorageManager.setSetting(SettingBoxKey.novelPageAnim, pageAnim);
  }

  static TextStyle applyTextStyle(TextStyle base) {
    return base.copyWith(
      letterSpacing: letterSpacing,
      fontFamilyFallback: switch (fontKey) {
        'serif' =>
          const ['Songti SC', 'STSong', 'Noto Serif CJK SC', 'serif'],
        'kai' => const ['Kaiti SC', 'STKaiti', 'KaiTi', 'serif'],
        'round' => const ['Yuanti SC', 'STYuanti', 'sans-serif'],
        'hei' => const ['Heiti SC', 'STHeiti', 'Noto Sans CJK SC', 'sans-serif'],
        'custom' =>
          [if (customFontFamily.isNotEmpty) customFontFamily, 'serif'],
        _ => null,
      },
    );
  }
}

// ============================================================================
// 阅读主题（11种，移植自 yuedu 项目）
// ============================================================================
class NovelReaderTheme {
  final String name;
  final Color backgroundColor;
  final Color textColor;
  final Color primaryColor;

  const NovelReaderTheme({
    required this.name,
    required this.backgroundColor,
    required this.textColor,
    required this.primaryColor,
  });

  // ----- 11 种预设主题 -----
  static const NovelReaderTheme light = NovelReaderTheme(
    name: '白天',
    backgroundColor: Color(0xFFF5F5F5),
    textColor: Color(0xFF333333),
    primaryColor: Color(0xFF8B4513),
  );

  static const NovelReaderTheme dark = NovelReaderTheme(
    name: '夜间',
    backgroundColor: Color(0xFF1A1A1A),
    textColor: Color(0xFFB0B0B0),
    primaryColor: Color(0xFFD4AF37),
  );

  static const NovelReaderTheme eyeProtection = NovelReaderTheme(
    name: '护眼',
    backgroundColor: Color(0xFFC7EDCC),
    textColor: Color(0xFF2F4F4F),
    primaryColor: Color(0xFF228B22),
  );

  static const NovelReaderTheme parchment = NovelReaderTheme(
    name: '羊皮纸',
    backgroundColor: Color(0xFFF4ECD8),
    textColor: Color(0xFF5D4E37),
    primaryColor: Color(0xFF8B4513),
  );

  static const NovelReaderTheme darkBlue = NovelReaderTheme(
    name: '深蓝',
    backgroundColor: Color(0xFF1E3A5F),
    textColor: Color(0xFFE0E0E0),
    primaryColor: Color(0xFF87CEEB),
  );

  static const NovelReaderTheme pink = NovelReaderTheme(
    name: '粉色',
    backgroundColor: Color(0xFFFCE4EC),
    textColor: Color(0xFF880E4F),
    primaryColor: Color(0xFFE91E63),
  );

  static const NovelReaderTheme coffee = NovelReaderTheme(
    name: '咖啡',
    backgroundColor: Color(0xFF3E2723),
    textColor: Color(0xFFD7CCC8),
    primaryColor: Color(0xFF8D6E63),
  );

  static const NovelReaderTheme forest = NovelReaderTheme(
    name: '森林',
    backgroundColor: Color(0xFF1B5E20),
    textColor: Color(0xFFC8E6C9),
    primaryColor: Color(0xFF4CAF50),
  );

  static const NovelReaderTheme lavender = NovelReaderTheme(
    name: '薰衣草',
    backgroundColor: Color(0xFFF3E5F5),
    textColor: Color(0xFF4A148C),
    primaryColor: Color(0xFF9C27B0),
  );

  static const NovelReaderTheme mint = NovelReaderTheme(
    name: '薄荷',
    backgroundColor: Color(0xFFE0F2F1),
    textColor: Color(0xFF004D40),
    primaryColor: Color(0xFF009688),
  );

  static const NovelReaderTheme dusk = NovelReaderTheme(
    name: '黄昏',
    backgroundColor: Color(0xFF263238),
    textColor: Color(0xFFCFD8DC),
    primaryColor: Color(0xFF607D8B),
  );

  static const List<NovelReaderTheme> allThemes = [
    light,
    dark,
    eyeProtection,
    parchment,
    darkBlue,
    pink,
    coffee,
    forest,
    lavender,
    mint,
    dusk,
  ];

  static NovelReaderTheme getThemeByIndex(int index) {
    if (index >= 0 && index < allThemes.length) {
      return allThemes[index];
    }
    return dark; // 默认返回暗夜
  }
}

// ============================================================================
// 翻页模式（5种，移植自 yuedu 项目）
// ============================================================================
enum NovelPageTurnMode {
  cover,      // 覆盖
  simulation, // 仿真
  slide,      // 滑动
  scroll,     // 滚动
  none,       // 无动画
}

extension NovelPageTurnModeExt on NovelPageTurnMode {
  String get displayName {
    switch (this) {
      case NovelPageTurnMode.cover:
        return '覆盖';
      case NovelPageTurnMode.simulation:
        return '仿真';
      case NovelPageTurnMode.slide:
        return '滑动';
      case NovelPageTurnMode.scroll:
        return '滚动';
      case NovelPageTurnMode.none:
        return '无动画';
    }
  }

  String get storageKey {
    switch (this) {
      case NovelPageTurnMode.cover:
        return 'cover';
      case NovelPageTurnMode.simulation:
        return 'simulation';
      case NovelPageTurnMode.slide:
        return 'slide';
      case NovelPageTurnMode.scroll:
        return 'scroll';
      case NovelPageTurnMode.none:
        return 'none';
    }
  }

  static NovelPageTurnMode fromStorageKey(String key) {
    switch (key) {
      case 'cover':
        return NovelPageTurnMode.cover;
      case 'simulation':
        return NovelPageTurnMode.simulation;
      case 'slide':
        return NovelPageTurnMode.slide;
      case 'scroll':
        return NovelPageTurnMode.scroll;
      case 'none':
        return NovelPageTurnMode.none;
      default:
        return NovelPageTurnMode.cover;
    }
  }
}