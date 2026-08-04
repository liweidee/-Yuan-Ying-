// lib/common/extensions/theme_ext.dart
import 'package:flutter/material.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';

extension ThemeDataExtension on ThemeData {
  bool get isDark => brightness == Brightness.dark;
  bool get isLight => brightness == Brightness.light;
}

extension ColorSchemeExtension on ColorScheme {
  bool get isDark => brightness == Brightness.dark;
  bool get isLight => brightness == Brightness.light;
  
  // 通用免费色（非B站专属）
  Color get freeColor => const Color(0xFFFF9800);
}

// 颜色扩展（播放器需要）
extension ColorExtension on Color {
  Color darken([double amount = .5]) {
    assert(amount >= 0 && amount <= 1, 'Amount must be between 0 and 1');
    return Color.lerp(this, Colors.black, amount)!;
  }

  ColorScheme asColorSchemeSeed([
    FlexSchemeVariant variant = FlexSchemeVariant.material,
    Brightness brightness = Brightness.light,
  ]) => SeedColorScheme.fromSeeds(
    primaryKey: this,
    variant: variant,
    brightness: brightness,
    useExpressiveOnContainerColors: false,
  );
}

// 亮度扩展（播放器需要）
extension BrightnessExt on Brightness {
  Brightness get reverse => isLight ? Brightness.dark : Brightness.light;
  bool get isLight => this == Brightness.light;
  bool get isDark => this == Brightness.dark;
}