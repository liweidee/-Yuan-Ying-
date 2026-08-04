import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';

extension ThemeDataExt on ThemeData {
  bool get isLight => brightness == Brightness.light;
  bool get isDark => brightness == Brightness.dark;
}

extension ColorExtension on Color {
  Color darken([double amount = 0.5]) {
    assert(amount >= 0 && amount <= 1, 'Amount must be between 0 and 1');
    return Color.lerp(this, Colors.black, amount)!;
  }

  ColorScheme asColorSchemeSeed([
    FlexSchemeVariant variant = FlexSchemeVariant.material3Legacy,
    Brightness brightness = Brightness.light,
  ]) {
    return SeedColorScheme.fromSeeds(
      primaryKey: this,
      variant: variant,
      brightness: brightness,
      useExpressiveOnContainerColors: false,
    );
  }
}

extension BrightnessExt on Brightness {
  Brightness get reverse {
    return this == Brightness.light ? Brightness.dark : Brightness.light;
  }

  bool get isLight => this == Brightness.light;
  bool get isDark => this == Brightness.dark;
}