import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/models/common/bg_source_type.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/theme_utils.dart';
import 'package:yuanying/utils/get_ext.dart';

class BgConfigController extends GetxController {
  /// 只作为 Obx 触发源
  final RxInt version = 0.obs;

  void _bump() => version.value++;

  // ==== 通用设置（仅触发背景层重建）====
  Future<void> setOpacity(double v) async {
    SettingPref.bgOpacity = v.clamp(0.0, 1.0);
    _bump();
  }

  Future<void> setBlur(double v) async {
    SettingPref.bgBlur = v.clamp(0.0, 1.0);
    _bump();
  }

  Future<void> setTint(double v) async {
    SettingPref.bgTint = v.clamp(0.0, 1.0);
    _bump();
  }

  Future<void> setGradientIndex(int i) async {
    SettingPref.bgGradientIndex = i;
    _bump();
  }

  Future<void> setPresetIndex(int i) async {
    SettingPref.bgPresetIndex = i;
    _bump();
  }

  // ==== 会改变"是否启用"的设置（需重建主题）====
  Future<void> setEnabled(bool v) async {
    SettingPref.bgEnabled = v;
    _bump();
    _rebuildTheme();
  }

  Future<void> setSourceType(BgSourceType t) async {
    SettingPref.bgSourceTypeIndex = t.index;
    _bump();
    _rebuildTheme();
  }

  Future<void> clearCustom() async {
    final old = SettingPref.bgCustomPath;
    if (old.isNotEmpty) {
      try {
        final f = File(old);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    SettingPref.bgCustomPath = '';
    _bump();
    _rebuildTheme();
  }

  // ==== 上传自定义图片 ====
  /// 返回错误消息；null 表示成功
  Future<String?> uploadCustom(String srcPath) async {
    if (kIsWeb) return 'Web 端暂不支持上传自定义背景';

    try {
      final src = File(srcPath);
      if (!await src.exists()) return '源文件不存在';

      final dir = await getApplicationDocumentsDirectory();
      final bgDir = Directory(p.join(dir.path, 'yuanying_bg'));
      if (!await bgDir.exists()) await bgDir.create(recursive: true);

      // 清理旧文件
      for (final f in bgDir.listSync()) {
        if (f is File) {
          try { await f.delete(); } catch (_) {}
        }
      }

      final ext = p.extension(srcPath).toLowerCase();
      final dst = File(
        p.join(bgDir.path, 'custom_${DateTime.now().millisecondsSinceEpoch}$ext'),
      );
      await src.copy(dst.path);

      SettingPref.bgCustomPath = dst.path;
      SettingPref.bgSourceTypeIndex = BgSourceType.custom.index;
      SettingPref.bgEnabled = true;
      _bump();
      _rebuildTheme();
      return null;
    } catch (e) {
      return '保存失败：$e';
    }
  }

  /// 全部恢复默认
  Future<void> resetAll() async {
    SettingPref.bgEnabled = false;
    SettingPref.bgSourceTypeIndex = BgSourceType.none.index;
    SettingPref.bgGradientIndex = 0;
    SettingPref.bgPresetIndex = 1;
    SettingPref.bgOpacity = 0.6;
    SettingPref.bgBlur = 0.0;
    SettingPref.bgTint = 0.0;
    await clearCustom();
    _bump();
    _rebuildTheme();
  }

  void _rebuildTheme() {
    ThemeUtils.refreshTheme();
    Get.updateMyAppTheme();
  }
}