import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/dialog/select_dialog.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

class PlaySpeedSetPage extends StatefulWidget {
  const PlaySpeedSetPage({super.key});

  @override
  State<PlaySpeedSetPage> createState() => _PlaySpeedSetPageState();
}

class _PlaySpeedSetPageState extends State<PlaySpeedSetPage> {
  late List<double> speedList;
  late double defaultSpeed;

  @override
  void initState() {
    super.initState();
    speedList = PlayerPref.speedList;
    defaultSpeed = PlayerPref.playSpeedDefault;
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('倍速设置'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        actions: [
          TextButton(
            onPressed: () {
              PlayerPref.speedList = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];
              PlayerPref.playSpeedDefault = 1.0;
              speedList = PlayerPref.speedList;
              defaultSpeed = PlayerPref.playSpeedDefault;
              _refresh();
            },
            child: const Text('重置'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Style.safeSpace),
        children: [
          // 默认倍速选择
          _buildSelectItem(
            title: '默认倍速',
            currentValue: defaultSpeed,
            onSelected: (value) {
              PlayerPref.playSpeedDefault = value;
              defaultSpeed = value;
              _refresh();
            },
          ),
          const SizedBox(height: 16),

          // 倍速列表
          Row(
            children: [
              Text(
                '倍速列表',
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: _showAddSpeedDialog,
                child: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: speedList.map((speed) {
              final isProtected = speed == 1.0 || speed == defaultSpeed; // 不可删除
              final isDefault = speed == defaultSpeed;                  // 高亮标志
              return Chip(
                label: Text('${speed}x'),
                backgroundColor: isDefault
                    ? colorScheme.primaryContainer.withOpacity(0.2)
                    : null,
                onDeleted: isProtected
                    ? null
                    : () {
                        speedList.remove(speed);
                        PlayerPref.speedList = speedList;
                        _refresh();
                      },
                deleteIcon: isProtected ? null : const Icon(Icons.close, size: 16),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showAddSpeedDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
          title: const Text('添加倍速'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '请输入倍速值',
              hintStyle: TextStyle(color: colorScheme.outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            inputFormatters: [
              // 允许数字和小数点
              FilteringTextInputFormatter.allow(RegExp(r'^[0-9.]+$')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                '取消',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                final value = double.tryParse(controller.text);
                if (value != null && value > 0 && !speedList.contains(value)) {
                  speedList.add(value);
                  speedList.sort();
                  PlayerPref.speedList = speedList;
                  Navigator.pop(context);
                  _refresh();
                }
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSelectItem({
    required String title,
    required double currentValue,
    required ValueChanged<double> onSelected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: Style.mdRadius,
      onTap: () async {
        final result = await showDialog<double>(
          context: context,
          builder: (context) => SelectDialog<double>(
            title: title,
            value: currentValue,
            values: speedList.map((e) => (e, '${e}x')).toList(),
          ),
        );
        if (result != null && mounted) {
          onSelected(result);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: Style.mdRadius,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '当前: ${currentValue}x',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}