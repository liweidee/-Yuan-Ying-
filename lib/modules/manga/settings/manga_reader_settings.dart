// lib/modules/manga/settings/manga_reader_settings.dart
import 'package:flutter/material.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

/// 漫画阅读模式
enum MangaReadMode {
  vertical,   // 纵向（单页上下滑动）
  horizontal, // 横向（双页左右滑动）
  strip,      // 条漫（长图滚动）
}

extension MangaReadModeExt on MangaReadMode {
  String get displayName {
    switch (this) {
      case MangaReadMode.vertical:
        return '纵向';
      case MangaReadMode.horizontal:
        return '横向';
      case MangaReadMode.strip:
        return '条漫';
    }
  }

  int get value {
    switch (this) {
      case MangaReadMode.vertical:
        return 0;
      case MangaReadMode.horizontal:
        return 1;
      case MangaReadMode.strip:
        return 2;
    }
  }

  static MangaReadMode fromValue(int value) {
    switch (value) {
      case 0:
        return MangaReadMode.vertical;
      case 1:
        return MangaReadMode.horizontal;
      case 2:
        return MangaReadMode.strip;
      default:
        return MangaReadMode.vertical;
    }
  }

  static MangaReadMode next(MangaReadMode current) {
    switch (current) {
      case MangaReadMode.vertical:
        return MangaReadMode.horizontal;
      case MangaReadMode.horizontal:
        return MangaReadMode.strip;
      case MangaReadMode.strip:
        return MangaReadMode.vertical;
    }
  }
}

/// 漫画阅读器设置
class MangaReaderSettings {
  static MangaReadMode readMode = MangaReadMode.vertical;
  static bool autoScroll = false;
  static double autoScrollSpeed = 3.0; // 秒
  static double zoomLevel = 1.0;

  static const double zoomMin = 0.5;
  static const double zoomMax = 3.0;
  static const double zoomStep = 0.1;

  static const List<double> speedPresets = [2.0, 3.0, 5.0, 8.0, 10.0];

  static Future<void> load() async {
    final modeValue = StorageManager.getSetting<int>(SettingBoxKey.mangaReadMode) ?? 0;
    readMode = MangaReadModeExt.fromValue(modeValue);
    autoScroll = StorageManager.getSetting<bool>(SettingBoxKey.mangaAutoScroll) ?? false;
    autoScrollSpeed = StorageManager.getSetting<double>(SettingBoxKey.mangaAutoScrollSpeed) ?? 3.0;
    zoomLevel = StorageManager.getSetting<double>(SettingBoxKey.mangaZoomLevel) ?? 1.0;
    zoomLevel = zoomLevel.clamp(zoomMin, zoomMax);
  }

  static Future<void> save() async {
    await StorageManager.setSetting(SettingBoxKey.mangaReadMode, readMode.value);
    await StorageManager.setSetting(SettingBoxKey.mangaAutoScroll, autoScroll);
    await StorageManager.setSetting(SettingBoxKey.mangaAutoScrollSpeed, autoScrollSpeed);
    await StorageManager.setSetting(SettingBoxKey.mangaZoomLevel, zoomLevel);
  }

  static void toggleReadMode() {
    readMode = MangaReadModeExt.next(readMode);
  }

  static void toggleAutoScroll() {
    autoScroll = !autoScroll;
  }

  static void setZoom(double value) {
    zoomLevel = value.clamp(zoomMin, zoomMax);
  }

  static void zoomIn() {
    zoomLevel = (zoomLevel + zoomStep).clamp(zoomMin, zoomMax);
  }

  static void zoomOut() {
    zoomLevel = (zoomLevel - zoomStep).clamp(zoomMin, zoomMax);
  }

  static void resetZoom() {
    zoomLevel = 1.0;
  }
}