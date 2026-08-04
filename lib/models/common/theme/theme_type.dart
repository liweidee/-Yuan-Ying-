import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

enum ThemeType {
  light('浅色'),
  dark('深色'),
  system('跟随系统');

  final String desc;
  const ThemeType(this.desc);

  ThemeMode get toThemeMode {
    switch (this) {
      case ThemeType.light:
        return ThemeMode.light;
      case ThemeType.dark:
        return ThemeMode.dark;
      case ThemeType.system:
        return ThemeMode.system;
    }
  }

  Icon get icon {
    switch (this) {
      case ThemeType.light:
        return const Icon(MdiIcons.weatherSunny);
      case ThemeType.dark:
        return const Icon(MdiIcons.weatherNight);
      case ThemeType.system:
        return const Icon(MdiIcons.themeLightDark);
    }
  }
}