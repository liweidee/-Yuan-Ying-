// lib/modules/web_tab/models/ds_env.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:yuanying/core/constants/app_constants.dart';

class DsEnv {
  final String version;
  final String platform;
  final bool isTv;
  final bool isMobile;
  final int gwPort;
  final Map<String, dynamic> safeInsets;
  final Map<String, dynamic>? theme;

  DsEnv({
    required this.version,
    required this.platform,
    required this.isTv,
    required this.isMobile,
    required this.gwPort,
    required this.safeInsets,
    this.theme,
  });

  static String get _platformStr {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static DsEnv fromContext(BuildContext? context, {int gwPort = 5575}) {
    Map<String, dynamic> safe = {'top': 0, 'bottom': 0, 'left': 0, 'right': 0};
    Map<String, dynamic>? theme;
    if (context != null) {
      final mq = MediaQuery.of(context);
      final t = Theme.of(context);
      safe = {
        'top': mq.padding.top,
        'bottom': mq.padding.bottom,
        'left': mq.padding.left,
        'right': mq.padding.right,
      };
      theme = {
        'mode': t.brightness == Brightness.dark ? 'dark' : 'light',
        'isDark': t.brightness == Brightness.dark,
        'primary':
            '#${t.colorScheme.primary.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
      };
    }
    return DsEnv(
      version: AppConstants.version,
      platform: _platformStr,
      isTv: false,
      isMobile: Platform.isAndroid || Platform.isIOS,
      gwPort: gwPort,
      safeInsets: safe,
      theme: theme,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'platform': platform,
        'isTv': isTv,
        'isMobile': isMobile,
        'gwPort': gwPort,
        'safeInsets': safeInsets,
        if (theme != null) 'theme': theme,
      };

  String toJsonString() => jsonEncode(toJson());
}