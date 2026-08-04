import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/utils/extension/num_ext.dart';
import 'package:yuanying/utils/get_ext.dart';

class FontSizeSelectPage extends StatefulWidget {
  const FontSizeSelectPage({super.key});

  @override
  State<FontSizeSelectPage> createState() => _FontSizeSelectPageState();
}

class _FontSizeSelectPageState extends State<FontSizeSelectPage> {
  final List<double> list = List.generate(16, (index) => 0.85 + index * 0.05);
  late final double minSize = list.first;
  late final double maxSize = list.last;
  late double currentSize = SettingPref.defaultTextScale;

  void setFontSize() {
    SettingPref.defaultTextScale = currentSize;
    // ===== 修复：保存后立即刷新应用 =====
    Get.back(result: currentSize);
    Get.appUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('字体大小'),
        actions: [
          TextButton(
            onPressed: () {
              currentSize = 1.0;
              setFontSize();
            },
            child: const Text('重置'),
          ),
          TextButton(onPressed: setFontSize, child: const Text('确定')),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  '当前字体大小:${currentSize == 1.0 ? '默认' : currentSize}',
                  style: TextStyle(fontSize: 14 * currentSize),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                color: colorScheme.surface,
              ),
              child: Row(
                children: [
                  const Text('小'),
                  Expanded(
                    child: Slider(
                      min: minSize,
                      value: currentSize,
                      max: maxSize,
                      divisions: list.length - 1,
                      secondaryTrackValue: 1,
                      onChanged: (double val) {
                        currentSize = val.toPrecision(2);
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    '大',
                    style: TextStyle(fontSize: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}