import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class PlaySpeedSetPage extends StatefulWidget {
  const PlaySpeedSetPage({super.key});

  @override
  State<PlaySpeedSetPage> createState() => _PlaySpeedSetPageState();
}

class _PlaySpeedSetPageState extends State<PlaySpeedSetPage> {
  late List<double> speedList;
  late double defaultSpeed;
  late double longPressSpeed;
  late bool enableAutoLongPress;

  final List<({int id, String title, Icon icon})> sheetMenu = [
    (id: 1, title: '设置为默认倍速', icon: const Icon(Icons.speed, size: 21)),
    (id: 2, title: '设置为默认长按倍速', icon: const Icon(Icons.speed_sharp, size: 21)),
    (id: -1, title: '删除该项', icon: const Icon(Icons.delete_outline, size: 21)),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    speedList = List.from(PlayerPref.speedList);
    defaultSpeed = PlayerPref.playSpeedDefault;
    longPressSpeed = PlayerPref.longPressSpeedDefault;
    enableAutoLongPress = PlayerPref.enableAutoLongPressSpeed;
  }

  void _refresh() => setState(() {});

  void _reset() {
    final defaultList = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];
    PlayerPref.speedList = defaultList;
    PlayerPref.playSpeedDefault = 1.0;
    PlayerPref.longPressSpeedDefault = 3.0;
    PlayerPref.enableAutoLongPressSpeed = false;
    _loadData();
    _refresh();
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
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '请输入倍速值',
              hintStyle: TextStyle(color: colorScheme.outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^[0-9.]+$')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text('取消', style: TextStyle(color: colorScheme.outline)),
            ),
            TextButton(
              onPressed: () {
                final value = double.tryParse(controller.text);
                if (value != null && value > 0) {
                  if (speedList.contains(value)) {
                    SmartDialog.showToast('该倍速已存在');
                    return;
                  }
                  speedList.add(value);
                  speedList.sort();
                  PlayerPref.speedList = speedList;
                  Get.back();
                  _refresh();
                } else {
                  SmartDialog.showToast('请输入有效的正数');
                }
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
  }

  void _showBottomSheet(int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      clipBehavior: Clip.hardEdge,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).shortestSide.clamp(0.0, 640.0),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ...sheetMenu.map(
              (item) => ListTile(
                enabled: !(enableAutoLongPress && item.id == 2),
                onTap: () {
                  Get.back();
                  _menuAction(index, item.id);
                },
                minLeadingWidth: 0,
                iconColor: colorScheme.onSurface,
                leading: item.icon,
                title: Text(item.title, style: const TextStyle(fontSize: 14)),
              ),
            ),
            SizedBox(height: 25 + MediaQuery.viewPaddingOf(context).bottom),
          ],
        );
      },
    );
  }

  void _menuAction(int index, int id) {
    final speed = speedList[index];
    if (id == 1) {
      defaultSpeed = speed;
      PlayerPref.playSpeedDefault = speed;
    } else if (id == 2) {
      longPressSpeed = speed;
      PlayerPref.longPressSpeedDefault = speed;
    } else if (id == -1) {
      if ([1.0, defaultSpeed, longPressSpeed].contains(speed)) {
        SmartDialog.showToast('不支持删除默认倍速');
        return;
      }
      speedList.removeAt(index);
      PlayerPref.speedList = speedList;
    }
    _refresh();
  }

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
            onPressed: _reset,
            child: const Text('重置'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Style.safeSpace),
        children: [
          // 1. 默认倍速（仅显示）
          _buildDisplayItem(
            title: '默认倍速',
            currentValue: defaultSpeed,
          ),
          const SizedBox(height: 16),

          // 2. 动态长按倍速开关
          _buildSwitchItem(
            title: '动态长按倍速',
            subtitle: '根据默认倍速长按时自动双倍',
            value: enableAutoLongPress,
            onChanged: (val) {
              enableAutoLongPress = val;
              PlayerPref.enableAutoLongPressSpeed = val;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // 3. 默认长按倍速（仅显示，条件显示）
          if (!enableAutoLongPress)
            _buildDisplayItem(
              title: '默认长按倍速',
              currentValue: longPressSpeed,
            ),
          const SizedBox(height: 16),

          // 4. 倍速列表标题 + 添加按钮
          Row(
            children: [
              Text('倍速列表', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: _showAddSpeedDialog,
                child: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 5. 倍速按钮列表
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: speedList.map((speed) {
              final isDefault = speed == defaultSpeed;
              return FilledButton.tonal(
                onPressed: () {
                  final index = speedList.indexOf(speed);
                  _showBottomSheet(index);
                },
                style: FilledButton.styleFrom(
                  // 高亮当前默认倍速，使用更深的主题色
                  backgroundColor: isDefault
                      ? colorScheme.primary
                      : null,
                  foregroundColor: isDefault
                      ? colorScheme.onPrimary
                      : null,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text('${speed}x'),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 仅显示当前值，不可点击
  Widget _buildDisplayItem({
    required String title,
    required double currentValue,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
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
        ],
      ),
    );
  }

  Widget _buildSwitchItem({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                    subtitle,
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}