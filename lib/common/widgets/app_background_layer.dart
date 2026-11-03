import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/assets.dart';
import 'package:yuanying/models/common/bg_source_type.dart';
import 'package:yuanying/modules/setting/controllers/bg_config_controller.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';

class AppBackgroundLayer extends StatelessWidget {
  final Widget child;

  const AppBackgroundLayer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<BgConfigController>()) return child;
    final ctrl = Get.find<BgConfigController>();

    return Obx(() {
      // 订阅版本号
      final _ = ctrl.version.value;

      if (!SettingPref.bgActive) {
        return child;
      }

      final type = BgSourceType.values[
          SettingPref.bgSourceTypeIndex.clamp(0, BgSourceType.values.length - 1)];

      return Stack(
        fit: StackFit.expand,
        children: [
          // 底层：渐变 / 图片（带模糊 + 透明度）
          Positioned.fill(
            child: RepaintBoundary(
              child: _buildLayer(type),
            ),
          ),

          // 蒙层
          if (SettingPref.bgTint > 0)
            Positioned.fill(
              child: IgnorePointer(child: _buildTint()),
            ),

          // 页面
          child,
        ],
      );
    });
  }

  Widget _buildLayer(BgSourceType type) {
    final opacity = SettingPref.bgOpacity.clamp(0.0, 1.0);
    final blur = SettingPref.bgBlur.clamp(0.0, 1.0);

    Widget base;
    switch (type) {
      case BgSourceType.gradient:
        base = _buildGradient(SettingPref.bgGradientIndex);
        break;
      case BgSourceType.preset:
        base = _buildPresetImage(SettingPref.bgPresetIndex);
        break;
      case BgSourceType.custom:
        base = _buildCustomImage(SettingPref.bgCustomPath);
        break;
      case BgSourceType.none:
        return const SizedBox.shrink();
    }

    // 模糊（只糊"背景图本身"，不动前景）
    if (blur > 0) {
      base = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: blur * 30,
          sigmaY: blur * 30,
          tileMode: TileMode.decal,
        ),
        child: base,
      );
    }

    if (opacity < 1.0) {
      base = Opacity(opacity: opacity, child: base);
    }

    return base;
  }

  Widget _buildGradient(int index) {
    final preset = kBgGradients[index.clamp(0, kBgGradients.length - 1)];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: preset.colors,
        ),
      ),
    );
  }

  Widget _buildPresetImage(int index) {
    return Image.asset(
      Assets.bg(index),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      isAntiAlias: false,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  Widget _buildCustomImage(String path) {
    if (kIsWeb || path.isEmpty) return const SizedBox.shrink();
    final f = File(path);
    if (!f.existsSync()) return const SizedBox.shrink();
    return Image.file(
      f,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      cacheWidth: 1920,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  Widget _buildTint() {
    final t = SettingPref.bgTint.clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: t * 0.20),
            Colors.black.withValues(alpha: t * 0.70),
          ],
        ),
      ),
    );
  }
}