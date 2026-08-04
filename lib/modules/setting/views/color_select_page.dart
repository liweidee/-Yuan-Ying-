// lib/modules/setting/views/color_select_page.dart
import 'package:flutter/material.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/models/common/theme/theme_color_type.dart';
import 'package:yuanying/common/widgets/color_palette.dart';
import 'package:yuanying/utils/theme_utils.dart';

class ColorSelectPage extends StatefulWidget {
  const ColorSelectPage({super.key});

  @override
  State<ColorSelectPage> createState() => _ColorSelectPageState();
}

class _ColorSelectPageState extends State<ColorSelectPage> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = ThemeUtils.getCustomColorIndex();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('选择应用主题'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, _selectedIndex);
            },
            child: Text(
              '保存',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 22,
          runSpacing: 18,
          children: colorThemeTypes.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isSelected = _selectedIndex == index;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _selectedIndex = index;
                });
              },
              child: Column(
                spacing: 3,
                children: [
                  ColorPalette(
                    color: item.color,
                    selected: isSelected,
                    size: 48,
                    borderWidth: 3,
                  ),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}