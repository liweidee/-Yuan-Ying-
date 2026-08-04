import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/common/widgets/scroll_behavior.dart';
import 'package:yuanying/modules/danmaku/controllers/danmaku_controller.dart';

/// 弹幕设置面板 - 优化版
class DanmakuSettings extends StatefulWidget {
  final DetailController controller;

  const DanmakuSettings({super.key, required this.controller});

  @override
  State<DanmakuSettings> createState() => _DanmakuSettingsState();
}

class _DanmakuSettingsState extends State<DanmakuSettings> {
  late final DetailController controller;
  late final PlPlayerController playerController;

  // 从 PlayerPref 读取的值
  late final RxBool enableShowDanmaku;
  late final RxDouble danmakuOpacity;
  late final RxDouble danmakuShowArea;
  late final RxDouble danmakuFontScale;
  late final RxDouble danmakuFontScaleFS;
  late final RxDouble danmakuStrokeWidth;
  late final RxInt danmakuFontWeight;
  late final RxDouble danmakuDuration;
  late final RxDouble danmakuStaticDuration;
  late final RxDouble danmakuLineHeight;
  late final RxBool danmakuMassiveMode;
  late final RxBool danmakuStatic2Scroll;
  late final RxBool danmakuFixedV;
  late final RxInt danmakuColorMode;

  @override
  void initState() {
    super.initState();
    controller = widget.controller;
    playerController = controller.playerController;

    enableShowDanmaku = playerController.enableShowDanmaku;
    danmakuOpacity = playerController.danmakuOpacity;
    danmakuShowArea = PlayerPref.danmakuShowArea.obs;
    danmakuFontScale = PlayerPref.danmakuFontScale.obs;
    danmakuFontScaleFS = PlayerPref.danmakuFontScaleFS.obs;
    danmakuStrokeWidth = PlayerPref.danmakuStrokeWidth.obs;
    danmakuFontWeight = PlayerPref.danmakuFontWeight.obs;
    danmakuDuration = PlayerPref.danmakuDuration.obs;
    danmakuStaticDuration = PlayerPref.danmakuStaticDuration.obs;
    danmakuLineHeight = PlayerPref.danmakuLineHeight.obs;
    danmakuMassiveMode = PlayerPref.danmakuMassiveMode.obs;
    danmakuStatic2Scroll = PlayerPref.danmakuStatic2Scroll.obs;
    danmakuFixedV = PlayerPref.danmakuFixedV.obs;
    danmakuColorMode = PlayerPref.danmakuColorMode.obs;
  }

  /// 保存所有设置并触发版本更新
  void _saveAll() {
    PlayerPref.danmakuShowArea = danmakuShowArea.value;
    PlayerPref.danmakuFontScale = danmakuFontScale.value;
    PlayerPref.danmakuFontScaleFS = danmakuFontScaleFS.value;
    PlayerPref.danmakuStrokeWidth = danmakuStrokeWidth.value;
    PlayerPref.danmakuFontWeight = danmakuFontWeight.value;
    PlayerPref.danmakuDuration = danmakuDuration.value;
    PlayerPref.danmakuStaticDuration = danmakuStaticDuration.value;
    PlayerPref.danmakuLineHeight = danmakuLineHeight.value;
    PlayerPref.danmakuMassiveMode = danmakuMassiveMode.value;
    PlayerPref.danmakuStatic2Scroll = danmakuStatic2Scroll.value;
    PlayerPref.danmakuFixedV = danmakuFixedV.value;
    PlayerPref.danmakuColorMode = danmakuColorMode.value;

    // 触发版本号更新，通知 DanmakuView 重建
    if (Get.isRegistered<DanmakuController>()) {
      final ctrl = Get.find<DanmakuController>();
      ctrl.configVersion.value++;
      // print('弹幕设置已保存，configVersion = ${ctrl.configVersion.value}');
    }
  }

  Widget _resetBtn(Object def, VoidCallback onPressed) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        tooltip: '默认值: $def',
        icon: const Icon(Icons.refresh, size: 18),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: theme.colorScheme.outline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.8,
          expand: false,
          builder: (context, scrollController) {
            return ScrollConfiguration(
              behavior: const NoScrollbarBehavior(),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                children: [
                  // 顶部拖拽条
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: colorScheme.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Center(
                    child: Text('弹幕设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 16),

                  // ===== 弹幕开关 =====
                  _buildSwitchItem(
                    title: '显示弹幕',
                    value: enableShowDanmaku.value,
                    onChanged: (value) {
                      controller.toggleDanmaku(); // 此方法会切换 enableShowDanmaku 并保存
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 6),

                  // ===== 其他开关 =====
                  _buildSwitchItem(
                    title: '海量弹幕',
                    value: danmakuMassiveMode.value,
                    onChanged: (value) {
                      danmakuMassiveMode.value = value;
                      _saveAll();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildSwitchItem(
                    title: '固定转滚动',
                    value: danmakuStatic2Scroll.value,
                    onChanged: (value) {
                      danmakuStatic2Scroll.value = value;
                      _saveAll();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildSwitchItem(
                    title: '滚动弹幕固定速度',
                    value: danmakuFixedV.value,
                    onChanged: (value) {
                      danmakuFixedV.value = value;
                      _saveAll();
                      setState(() {});
                    },
                  ),

                  const SizedBox(height: 12),
                  // ===== 颜色模式选择 =====
                  _buildColorModeRow(colorScheme),
                  const SizedBox(height: 16),

                  // ===== 弹幕样式滑块 =====
                  _buildSliderWithResetDouble(
                    label: '显示区域',
                    value: danmakuShowArea,
                    min: 0.1,
                    max: 1,
                    divisions: 9,
                    displayFormat: (v) => '${(v * 100).toInt()}%',
                    defaultValue: 0.5,
                    onChanged: (val) {
                      danmakuShowArea.value = val;
                      _saveAll();
                      setState(() {});
                    },
                  ),
                  _buildSliderWithResetDouble(
                    label: '不透明度',
                    value: danmakuOpacity,
                    min: 0,
                    max: 1,
                    divisions: 10,
                    displayFormat: (v) => '${(v * 100).toInt()}%',
                    defaultValue: 1.0,
                    onChanged: (val) {
                      danmakuOpacity.value = val;
                      playerController.danmakuOpacity.value = val;
                      // 不透明度不需要重建 DanmakuView，但需保存
                      PlayerPref.danmakuOpacity = val;
                      setState(() {});
                    },
                  ),
                  _buildSliderWithResetInt(
                    label: '字体粗细',
                    value: danmakuFontWeight,
                    min: 0,
                    max: 8,
                    divisions: 8,
                    displayFormat: (v) => '${v + 1}',
                    defaultValue: 5,
                    onChanged: (val) {
                      danmakuFontWeight.value = val;
                      _saveAll();
                      setState(() {});
                    },
                    note: '（可能无法精确调节）',
                  ),
                  _buildSliderWithResetDouble(
                    label: '描边粗细',
                    value: danmakuStrokeWidth,
                    min: 0,
                    max: 5,
                    divisions: 10,
                    displayFormat: (v) => v.toStringAsFixed(1),
                    defaultValue: 1.5,
                    onChanged: (val) {
                      danmakuStrokeWidth.value = val;
                      _saveAll();
                      setState(() {});
                    },
                  ),
                  _buildSliderWithResetDouble(
                    label: '字体大小',
                    value: danmakuFontScale,
                    min: 0.5,
                    max: 2.5,
                    divisions: 20,
                    displayFormat: (v) => '${(v * 100).toStringAsFixed(1)}%',
                    defaultValue: 1.0,
                    onChanged: (val) {
                      danmakuFontScale.value = val;
                      _saveAll();
                      setState(() {});
                    },
                  ),
                  _buildSliderWithResetDouble(
                    label: '全屏字体大小',
                    value: danmakuFontScaleFS,
                    min: 0.5,
                    max: 2.5,
                    divisions: 20,
                    displayFormat: (v) => '${(v * 100).toStringAsFixed(1)}%',
                    defaultValue: 1.2,
                    onChanged: (val) {
                      danmakuFontScaleFS.value = val;
                      _saveAll();
                      setState(() {});
                    },
                  ),
                  _buildSliderWithResetDouble(
                    label: '滚动弹幕时长',
                    value: danmakuDuration,
                    min: 1,
                    max: 50,
                    divisions: 49,
                    displayFormat: (v) => '${v.toInt()} 秒',
                    defaultValue: 7.0,
                    onChanged: (val) {
                      danmakuDuration.value = val;
                      _saveAll();
                      setState(() {});
                    },
                  ),
                  _buildSliderWithResetDouble(
                    label: '静态弹幕时长',
                    value: danmakuStaticDuration,
                    min: 1,
                    max: 50,
                    divisions: 49,
                    displayFormat: (v) => '${v.toInt()} 秒',
                    defaultValue: 4.0,
                    onChanged: (val) {
                      danmakuStaticDuration.value = val;
                      _saveAll();
                      setState(() {});
                    },
                  ),
                  _buildSliderWithResetDouble(
                    label: '弹幕行高',
                    value: danmakuLineHeight,
                    min: 1.0,
                    max: 3.0,
                    divisions: 20,
                    displayFormat: (v) => v.toStringAsFixed(1),
                    defaultValue: 1.6,
                    onChanged: (val) {
                      danmakuLineHeight.value = val;
                      _saveAll();
                      setState(() {});
                    },
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSwitchItem({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14),
        ),
        Transform.scale(
          scale: 0.85,
          child: Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildColorModeRow(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('弹幕颜色', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        Obx(() {
          final current = danmakuColorMode.value;
          return SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('默认')),
              ButtonSegment(value: 1, label: Text('随机')),
              ButtonSegment(value: 2, label: Text('渐变')),
            ],
            selected: {current},
            onSelectionChanged: (Set<int> newSelection) {
              final mode = newSelection.first;
              danmakuColorMode.value = mode;
              _saveAll();
              setState(() {});
            },
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return colorScheme.primary;
                }
                return colorScheme.onSurface;
              }),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSliderWithResetDouble({
    required String label,
    required RxDouble value,
    required double min,
    required double max,
    int? divisions,
    required String Function(double) displayFormat,
    required double defaultValue,
    required ValueChanged<double> onChanged,
    String note = '',
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Obx(() => Text(
                '$label ${displayFormat(value.value)}',
                style: const TextStyle(fontSize: 13),
              )),
              _resetBtn(
                defaultValue,
                () {
                  value.value = defaultValue;
                  onChanged(defaultValue);
                  setState(() {});
                },
              ),
            ],
          ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 2),
              child: Text(
                note,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
              ),
            ),
          Obx(() => Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value.value.clamp(min, max),
            label: displayFormat(value.value),
            onChanged: (val) {
              value.value = val;
              onChanged(val);
              setState(() {});
            },
          )),
        ],
      ),
    );
  }

  Widget _buildSliderWithResetInt({
    required String label,
    required RxInt value,
    required double min,
    required double max,
    int? divisions,
    required String Function(int) displayFormat,
    required int defaultValue,
    required ValueChanged<int> onChanged,
    String note = '',
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Obx(() => Text(
                '$label ${displayFormat(value.value)}',
                style: const TextStyle(fontSize: 13),
              )),
              _resetBtn(
                defaultValue,
                () {
                  value.value = defaultValue;
                  onChanged(defaultValue);
                  setState(() {});
                },
              ),
            ],
          ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 2),
              child: Text(
                note,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
              ),
            ),
          Obx(() => Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value.value.toDouble().clamp(min, max),
            label: displayFormat(value.value),
            onChanged: (val) {
              final intVal = val.toInt();
              value.value = intVal;
              onChanged(intVal);
              setState(() {});
            },
          )),
        ],
      ),
    );
  }
}

/// 隐藏滚动条的 Behavior
class _NoScrollbarBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// 自定义 SliderTrackShape
class _MSliderTrackShape extends RoundedRectSliderTrackShape {
  const _MSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    SliderThemeData? sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    const double trackHeight = 3;
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2 + 4;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}