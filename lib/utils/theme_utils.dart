import 'package:flutter/material.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:yuanying/models/common/theme/theme_type.dart';
import 'package:yuanying/models/common/theme/theme_color_type.dart';
import 'package:yuanying/utils/extension/theme_ext.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';

abstract final class ThemeUtils {
  static ThemeData lightTheme = _buildLightTheme();
  static ThemeData darkTheme = _buildDarkTheme();
  static ThemeMode themeMode = ThemeMode.system;

  // 刷新主题
  static void refreshTheme() {
    lightTheme = _buildLightTheme();
    darkTheme = _buildDarkTheme();
  }

  static ThemeData get currentTheme {
    if (themeMode == ThemeMode.dark) {
      return darkTheme;
    }
    if (themeMode == ThemeMode.system) {
      final brightness = WidgetsBinding.instance.window.platformBrightness;
      if (brightness == Brightness.dark) {
        return darkTheme;
      }
    }
    return lightTheme;
  }

  static bool get isDarkMode {
    return currentTheme.brightness == Brightness.dark;
  }

  static ThemeData _buildLightTheme() {
    return _buildThemeData(Brightness.light);
  }

  static ThemeData _buildDarkTheme() {
    return _buildThemeData(Brightness.dark);
  }

  static ThemeData _buildThemeData(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final int colorIndex = _getCustomColor();
    final Color seedColor = colorThemeTypes[colorIndex].color;

    final ColorScheme colorScheme = seedColor.asColorSchemeSeed(
      FlexSchemeVariant.material3Legacy,
      brightness,
    );

    // ===== 应用字重设置 =====
    final int appFontWeightValue = SettingPref.appFontWeight;
    final FontWeight? fontWeight = appFontWeightValue == -1
        ? null
        : FontWeight.values[appFontWeightValue.clamp(0, FontWeight.values.length - 1)];

    // 构建基础 textTheme，如果 fontWeight 为 null 则使用默认
    TextTheme baseTextTheme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
    ).textTheme;

    // 如果有自定义字重，则覆盖所有样式
    if (fontWeight != null) {
      baseTextTheme = baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(fontWeight: fontWeight),
        displayMedium: baseTextTheme.displayMedium?.copyWith(fontWeight: fontWeight),
        displaySmall: baseTextTheme.displaySmall?.copyWith(fontWeight: fontWeight),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(fontWeight: fontWeight),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(fontWeight: fontWeight),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(fontWeight: fontWeight),
        titleLarge: baseTextTheme.titleLarge?.copyWith(fontWeight: fontWeight),
        titleMedium: baseTextTheme.titleMedium?.copyWith(fontWeight: fontWeight),
        titleSmall: baseTextTheme.titleSmall?.copyWith(fontWeight: fontWeight),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(fontWeight: fontWeight),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(fontWeight: fontWeight),
        bodySmall: baseTextTheme.bodySmall?.copyWith(fontWeight: fontWeight),
        labelLarge: baseTextTheme.labelLarge?.copyWith(fontWeight: fontWeight),
        labelMedium: baseTextTheme.labelMedium?.copyWith(fontWeight: fontWeight),
        labelSmall: baseTextTheme.labelSmall?.copyWith(fontWeight: fontWeight),
      );
    }

    ThemeData themeData = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      textTheme: baseTextTheme,  // 应用字重
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.0,  // 禁用滚动颜色变化
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: fontWeight ?? FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        margin: EdgeInsets.zero,
        surfaceTintColor: colorScheme.onSurfaceVariant.withOpacity(0.05),
        shadowColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: fontWeight ?? FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        surfaceTintColor: colorScheme.onSurfaceVariant.withOpacity(0.05),
      ),
      popupMenuTheme: PopupMenuThemeData(
        surfaceTintColor: colorScheme.onSurfaceVariant.withOpacity(0.05),
      ),
      snackBarTheme: SnackBarThemeData(
        actionTextColor: colorScheme.primary,
        backgroundColor: colorScheme.secondaryContainer,
        contentTextStyle: TextStyle(
          color: colorScheme.onSecondaryContainer,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        thumbIcon: WidgetStateProperty.resolveWith<Icon?>(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return const Icon(Icons.done, size: 16);
            }
            return null;
          },
        ),
      ),
    );

    // 暗色模式下，如果开启了纯黑主题
    if (isDark && _isPureBlackTheme()) {
      themeData = _darkenTheme(themeData);
    }

    return themeData;
  }

  // 纯黑主题暗色增强
  static ThemeData _darkenTheme(ThemeData themeData) {
    final colorScheme = themeData.colorScheme;
    return themeData.copyWith(
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: themeData.appBarTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      cardTheme: themeData.cardTheme.copyWith(
        color: Colors.black,
      ),
      dialogTheme: themeData.dialogTheme.copyWith(
        backgroundColor: Colors.grey[900],
      ),
      bottomSheetTheme: themeData.bottomSheetTheme.copyWith(
        backgroundColor: Colors.grey[900],
      ),
      colorScheme: colorScheme.copyWith(
        surface: Colors.black,
        surfaceTint: colorScheme.surfaceTint.darken(0.3),
        primary: colorScheme.primary.darken(0.1),
        onSurface: colorScheme.onSurface.darken(0.15),
      ),
    );
  }

  static int _getCustomColor() {
    return StorageManager.getSetting<int>('custom_color', defaultValue: 0) ?? 0;
  }

  static bool _isPureBlackTheme() {
    return StorageManager.getSetting<bool>('pure_black_theme', defaultValue: false) ?? false;
  }

  static Future<void> setThemeMode(ThemeType type) async {
    themeMode = type.toThemeMode;
    await StorageManager.setSetting('theme_mode', type.index);
    refreshTheme();
  }

  static Future<void> setCustomColor(int index) async {
    await StorageManager.setSetting('custom_color', index);
    refreshTheme();
  }

  // 设置纯黑主题
  static Future<void> setPureBlackTheme(bool value) async {
    await StorageManager.setSetting('pure_black_theme', value);
    refreshTheme();
  }

  // 获取纯黑主题状态
  static bool getPureBlackTheme() {
    return _isPureBlackTheme();
  }

  static ThemeType getThemeType() {
    final index = StorageManager.getSetting<int>('theme_mode', defaultValue: ThemeType.system.index);
    return ThemeType.values[index ?? ThemeType.system.index];
  }

  static int getCustomColorIndex() {
    return StorageManager.getSetting<int>('custom_color', defaultValue: 0) ?? 0;
  }
}