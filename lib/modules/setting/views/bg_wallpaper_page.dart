import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/common/assets.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/models/common/bg_source_type.dart';
import 'package:yuanying/modules/setting/controllers/bg_config_controller.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';

class BgWallpaperPage extends StatefulWidget {
  const BgWallpaperPage({super.key});

  @override
  State<BgWallpaperPage> createState() => _BgWallpaperPageState();
}

class _BgWallpaperPageState extends State<BgWallpaperPage> {
  late final BgConfigController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = Get.find<BgConfigController>();
  }

  /// 辅助方法：选择背景时自动开启总开关
  void _applyAndEnable(BgSourceType type) {
    ctrl.setSourceType(type);
    if (!SettingPref.bgEnabled) {
      ctrl.setEnabled(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    // 页面底色：如果没有开启壁纸，用实色；如果开启了，用透明让底层壁纸透出来
    final bgColor = SettingPref.bgActive ? Colors.transparent : cs.surface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('背景壁纸'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: bgColor,
        foregroundColor: cs.onSurface,
      ),
      body: Obx(() {
        final _ = ctrl.version.value;

        final enabled = SettingPref.bgEnabled;
        // 如果类型是 none 或越界，回退到渐变
        final rawType = BgSourceType.values[SettingPref.bgSourceTypeIndex.clamp(0, BgSourceType.values.length - 1)];
        final type = rawType == BgSourceType.none ? BgSourceType.gradient : rawType;

        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          children: [
            // ==========================================
            // 1. 全局开关（唯一控制壁纸显隐的地方）
            // ==========================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: Style.mdRadius,
                clipBehavior: Clip.antiAlias,
                child: SwitchListTile(
                  title: const Text('启用背景壁纸'),
                  subtitle: const Text('开启后，在支持的页面显示所选背景', style: TextStyle(fontSize: 12)),
                  value: enabled,
                  onChanged: (v) {
                    ctrl.setEnabled(v);
                    // 如果打开开关但当前是无效类型，默认切到渐变
                    if (v && rawType == BgSourceType.none) {
                      ctrl.setSourceType(BgSourceType.gradient);
                    }
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ==========================================
            // 2. 背景样式选择（去掉了“无”）
            // ==========================================
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 渐变色
                  for (int i = 0; i < kBgGradients.length; i++) ...[
                    _buildColorSquare(
                      label: kBgGradients[i].label,
                      colors: kBgGradients[i].colors,
                      isSelected: type == BgSourceType.gradient &&
                          SettingPref.bgGradientIndex == i,
                      onTap: () {
                        _applyAndEnable(BgSourceType.gradient);
                        ctrl.setGradientIndex(i);
                      },
                    ),
                    const SizedBox(width: 16),
                  ],
                  // 自定义
                  _buildCustomSquare(
                    isSelected: type == BgSourceType.custom,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ==========================================
            // 3. 预设图 (1~21)
            // ==========================================
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 1; i <= Assets.bgCount; i++) ...[
                    _buildPresetSquare(
                      index: i,
                      isSelected: type == BgSourceType.preset &&
                          SettingPref.bgPresetIndex == i,
                      onTap: () {
                        _applyAndEnable(BgSourceType.preset);
                        ctrl.setPresetIndex(i);
                      },
                    ),
                    if (i < Assets.bgCount) const SizedBox(width: 12),
                  ],
                ],
              ),
            ),

            // 如果当前是自定义，展示管理按钮
            if (type == BgSourceType.custom) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildCustomManageBlock(),
              ),
            ],

            const SizedBox(height: 32),

            // ==========================================
            // 4. 参数滑块区
            // ==========================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _CustomSlider(
                    title: '背景透明度',
                    value: SettingPref.bgOpacity,
                    onChanged: ctrl.setOpacity,
                  ),
                  const SizedBox(height: 24),
                  _CustomSlider(
                    title: '模糊强度',
                    value: SettingPref.bgBlur,
                    isBlur: true,
                    onChanged: ctrl.setBlur,
                  ),
                  const SizedBox(height: 24),
                  _CustomSlider(
                    title: '蒙层浓度',
                    value: SettingPref.bgTint,
                    onChanged: ctrl.setTint,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 恢复默认按钮
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('恢复默认'),
                      content: const Text('将关闭壁纸并清空自定义图片，确定？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await ctrl.resetAll();
                },
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('恢复默认'),
              ),
            ),
          ],
        );
      }),
    );
  }

  // ========================================================================
  // UI 构造组件 (不变)
  // ========================================================================

  Widget _buildColorSquare({
    required String label,
    required List<Color> colors,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: const Color(0xFFC75B5B), width: 2)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? const Color(0xFFC75B5B) : cs.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomSquare({required bool isSelected}) {
    final hasImage = SettingPref.bgCustomPath.isNotEmpty &&
        File(SettingPref.bgCustomPath).existsSync();

    return InkWell(
      onTap: () async {
        if (!hasImage) {
          await _pickImage();
        } else {
          _applyAndEnable(BgSourceType.custom);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFC75B5B)
                    : Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.5),
                width: isSelected ? 2 : 1,
              ),
              image: hasImage
                  ? DecorationImage(
                      image: FileImage(File(SettingPref.bgCustomPath)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasImage
                ? null
                : Icon(
                    Icons.add_photo_alternate_outlined,
                    color: isSelected
                        ? const Color(0xFFC75B5B)
                        : Theme.of(context).colorScheme.outline,
                    size: 28,
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            '自定义',
            style: TextStyle(
              fontSize: 12,
              color: isSelected
                  ? const Color(0xFFC75B5B)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSquare({
    required int index,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: const Color(0xFFC75B5B), width: 2)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isSelected ? 6 : 8),
              child: Image.asset(
                Assets.bg(index),
                fit: BoxFit.cover,
                cacheWidth: 150,
                errorBuilder: (_, __, ___) => Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.image_not_supported,
                      color: cs.outline, size: 20),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$index',
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? const Color(0xFFC75B5B) : cs.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomManageBlock() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '当前已启用自定义图片',
              style: TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _pickImage,
            child: const Text('更换'),
          ),
          TextButton(
            onPressed: () async {
              await ctrl.clearCustom();
              // 清除后，默认回退到第一张预设图
              await ctrl.setSourceType(BgSourceType.preset);
              await ctrl.setPresetIndex(1);
            },
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.image,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (result == null || result.path == null) return;
      SmartDialog.showLoading();
      final err = await ctrl.uploadCustom(result.path!);
      SmartDialog.dismiss();
      if (err != null) {
        SmartDialog.showToast(err);
      } else {
        _applyAndEnable(BgSourceType.custom);
        SmartDialog.showToast('已应用自定义背景');
      }
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('选择文件失败：$e');
    }
  }
}

// ============================================================================
// 自定义刻度滑块组件 (不变)
// ============================================================================
class _CustomSlider extends StatelessWidget {
  final String title;
  final double value;
  final bool isBlur;
  final ValueChanged<double> onChanged;

  const _CustomSlider({
    required this.title,
    required this.value,
    required this.onChanged,
    this.isBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = value.clamp(0.0, 1.0);
    final displayValue =
        (isBlur && percent == 0) ? '关' : '${(percent * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title · $displayValue',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _updateValue(details.localPosition.dx, width),
              onHorizontalDragUpdate: (details) =>
                  _updateValue(details.localPosition.dx, width),
              child: SizedBox(
                height: 32,
                child: CustomPaint(
                  size: Size(width, 32),
                  painter: _SliderPainter(value: percent),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _updateValue(double dx, double width) {
    const padding = 8.0;
    final usableWidth = width - padding * 2;
    final localX = (dx - padding).clamp(0.0, usableWidth);
    final rawValue = localX / usableWidth;
    final snappedValue = (rawValue * 19).round() / 19;
    onChanged(snappedValue);
  }
}

class _SliderPainter extends CustomPainter {
  final double value;

  _SliderPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 8.0;
    final trackWidth = size.width - padding * 2;
    final trackCenterY = size.height / 2;
    final trackHeight = 8.0;
    final radius = trackHeight / 2;

    final trackRect = Rect.fromLTRB(
      padding,
      trackCenterY - radius,
      padding + trackWidth,
      trackCenterY + radius,
    );

    final bgPaint = Paint()..color = const Color(0xFFFFE0E0);
    canvas.drawRRect(
        RRect.fromRectAndRadius(trackRect, Radius.circular(radius)), bgPaint);

    final dotPaint = Paint()..color = const Color(0xFF333333);
    for (int i = 0; i <= 19; i++) {
      final dotX = trackRect.left + trackWidth * (i / 19);
      canvas.drawCircle(Offset(dotX, trackCenterY), 1.5, dotPaint);
    }

    if (value > 0) {
      final activeRect = Rect.fromLTRB(
        trackRect.left,
        trackRect.top,
        trackRect.left + trackWidth * value,
        trackRect.bottom,
      );
      final activePaint = Paint()..color = const Color(0xFF9E5252);
      canvas.drawRRect(
          RRect.fromRectAndRadius(activeRect, Radius.circular(radius)),
          activePaint);
    }

    final thumbX = trackRect.left + trackWidth * value;
    final thumbPaint = Paint()
      ..color = const Color(0xFF9E5252)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(thumbX, trackCenterY - 14),
      Offset(thumbX, trackCenterY + 14),
      thumbPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SliderPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}