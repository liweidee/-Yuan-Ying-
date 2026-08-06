import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/custom_icon.dart';
import 'package:yuanying/common/widgets/dialog/header_strategy_dialog.dart';
import 'package:yuanying/common/widgets/dialog/player_engine_dialog.dart';
import 'package:yuanying/common/widgets/dialog/parse_mode_dialog.dart';
import 'package:yuanying/common/widgets/dialog/push_mode_dialog.dart';
import 'package:yuanying/common/widgets/dialog/select_dialog.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/plugin/pl_player/models/bottom_progress_behavior.dart';
import 'package:yuanying/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:yuanying/plugin/pl_player/models/play_repeat.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class PlaySettingPage extends StatefulWidget {
  const PlaySettingPage({super.key});

  @override
  State<PlaySettingPage> createState() => _PlaySettingPageState();
}

class _PlaySettingPageState extends State<PlaySettingPage> {
  late int _headerStrategy;
  late int _parseMode;
  late int _pushMode;

  @override
  void initState() {
    super.initState();
    _headerStrategy = PlayerPref.requestHeaderStrategy.clamp(0, 2);
    _parseMode = PlayerPref.parseMode.clamp(0, 1);
    _pushMode = PlayerPref.pushMode.clamp(0, 1);
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('播放设置'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(Style.safeSpace),
        children: [
          // ===== 播放器切换 =====
          _buildSettingItem(
              icon: Icons.settings_overscan,
              title: '默认播放器',
              subtitle: _getEngineLabel(),
              onTap: _showEngineDialog,
            ),
            const SizedBox(height: 8),
          // ===== 请求头策略 =====
          _buildSettingItem(
            icon: Icons.http_outlined,
            title: '播放请求头策略',
            subtitle: _getStrategyLabel(_headerStrategy),
            onTap: _showHeaderStrategyDialog,
          ),
          const SizedBox(height: 8),

          // ===== 解析模式 =====
          _buildSettingItem(
            icon: Icons.transform_outlined,
            title: '解析模式',
            subtitle: _getParseModeLabel(_parseMode),
            onTap: _showParseModeDialog,
          ),
          const SizedBox(height: 8),

          // ===== 推送模式 =====
          _buildSettingItem(
            icon: Icons.send,
            title: '推送模式',
            subtitle: _getPushModeLabel(_pushMode),
            onTap: _showPushModeDialog,
          ),
          const SizedBox(height: 8),

          // ===== 1. 弹幕开关 =====
          _buildSwitchItem(
            icon: CustomIcons.dm_settings,
            title: '弹幕开关',
            subtitle: '是否展示弹幕',
            value: PlayerPref.enableShowDanmaku,
            onChanged: (value) {
              PlayerPref.enableShowDanmaku = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 2. 倍速设置（跳转） =====
          _buildNavigateItem(
            icon: Icons.speed_outlined,
            title: '倍速设置',
            subtitle: '管理自定义倍速列表',
            onTap: () => Get.toNamed('/playSpeedSet'),
          ),
          const SizedBox(height: 8),

          // ===== 3. 自动播放 =====
          _buildSwitchItem(
            icon: Icons.play_circle_outline,
            title: '自动播放',
            subtitle: '进入详情页自动播放',
            value: PlayerPref.autoPlayEnable,
            onChanged: (value) {
              PlayerPref.autoPlayEnable = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 4. 全屏锁定按钮 =====
          _buildSwitchItem(
            icon: Icons.lock_outline,
            title: '全屏显示锁定按钮',
            value: PlayerPref.showFsLockBtn,
            onChanged: (value) {
              PlayerPref.showFsLockBtn = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 5. 全屏截图按钮 =====
          _buildSwitchItem(
            icon: Icons.camera_alt_outlined,
            title: '全屏显示截图按钮',
            value: PlayerPref.showFsScreenshotBtn,
            onChanged: (value) {
              PlayerPref.showFsScreenshotBtn = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 6. 全屏电池电量 =====
          _buildSwitchItem(
            icon: Icons.battery_3_bar,
            title: '全屏显示电池电量',
            value: PlayerPref.showBatteryLevel,
            onChanged: (value) {
              PlayerPref.showBatteryLevel = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 7. 双击快退/快进 =====
          _buildSwitchItem(
            icon: Icons.touch_app_outlined,
            title: '双击快退/快进',
            subtitle: '左侧双击快退/右侧双击快进，关闭则双击均为暂停/播放',
            value: PlayerPref.enableQuickDouble,
            onChanged: (value) {
              PlayerPref.enableQuickDouble = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 8. 左右滑动调节亮度/音量 =====
          _buildSwitchItem(
            icon: Icons.tune,
            title: '左右侧滑动调节亮度/音量',
            value: PlayerPref.enableSlideVolumeBrightness,
            onChanged: (value) {
              PlayerPref.enableSlideVolumeBrightness = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 9. 中间滑动全屏切换 =====
          _buildSwitchItem(
            icon: Icons.swap_vert,
            title: '中间滑动进入/退出全屏',
            value: PlayerPref.enableSlideFS,
            onChanged: (value) {
              PlayerPref.enableSlideFS = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 10. 双击快进时长 =====
          _buildSelectItem<int>(
            icon: Icons.fast_forward_outlined,
            title: '双击快进/快退时长',
            subtitle: '当前: ${PlayerPref.fastForBackwardDuration}s',
            values: const [5, 10, 15],
            displayValues: const ['5s', '10s', '15s'],
            currentValue: PlayerPref.fastForBackwardDuration,
            onSelected: (value) {
              PlayerPref.fastForBackwardDuration = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 11. 滑动快进时长 =====
          _buildSelectItem<int>(
            icon: Icons.drag_handle_outlined,
            title: '滑动快进/快退时长',
            subtitle: '当前: ${PlayerPref.sliderDuration}${PlayerPref.useRelativeSlide ? '%' : 's'}',
            values: const [25, 50, 90, 100],
            displayValues: const ['25%', '50%', '90%', '100%'],
            currentValue: PlayerPref.sliderDuration,
            onSelected: (value) {
              PlayerPref.sliderDuration = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 12. 键盘控制 =====
          _buildSwitchItem(
            icon: Icons.keyboard_outlined,
            title: '启用键盘控制',
            value: PlayerPref.keyboardControl,
            onChanged: (value) {
              PlayerPref.keyboardControl = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 13. 自动全屏 =====
          _buildSwitchItem(
            icon: Icons.fullscreen_outlined,
            title: '自动全屏',
            subtitle: '视频开始播放时进入全屏',
            value: PlayerPref.autoEnterFullScreen,
            onChanged: (value) {
              PlayerPref.autoEnterFullScreen = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 14. 自动退出全屏 =====
          _buildSwitchItem(
            icon: Icons.fullscreen_exit_outlined,
            title: '自动退出全屏',
            subtitle: '视频结束播放时退出全屏',
            value: PlayerPref.autoExitFullscreen,
            onChanged: (value) {
              PlayerPref.autoExitFullscreen = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 15. 后台播放 =====
          _buildSwitchItem(
            icon: Icons.motion_photos_pause_outlined,
            title: '后台播放',
            subtitle: '进入后台时继续播放',
            value: PlayerPref.continuePlayInBackground,
            onChanged: (value) {
              PlayerPref.continuePlayInBackground = value;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 16. 默认全屏方向 =====
          _buildSelectItem<FullScreenMode>(
            icon: Icons.screen_rotation_outlined,
            title: '默认全屏方向',
            subtitle: '当前: ${FullScreenMode.values[PlayerPref.fullScreenMode].desc}',
            values: FullScreenMode.values,
            displayValues: FullScreenMode.values.map((e) => e.desc).toList(),
            currentValue: FullScreenMode.values[PlayerPref.fullScreenMode],
            onSelected: (value) {
              PlayerPref.fullScreenMode = value.index;
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 17. 底部进度条展示 =====
          _buildSelectItem<BtmProgressBehavior>(
            icon: Icons.border_bottom_outlined,
            title: '底部进度条展示',
            subtitle: '当前: ${BtmProgressBehavior.values[PlayerPref.btmProgressBehavior].desc}',
            values: BtmProgressBehavior.values,
            displayValues: BtmProgressBehavior.values.map((e) => e.desc).toList(),
            currentValue: BtmProgressBehavior.values[PlayerPref.btmProgressBehavior],
            onSelected: (value) {
              PlayerPref.btmProgressBehavior = value.index;
              // 如果播放器已初始化，同步更新 Rx
              try {
                final controller = Get.find<PlPlayerController>();
                controller.progressType.value = value.index;
              } catch (_) {}
              _refresh();
            },
          ),
          const SizedBox(height: 8),

          // ===== 18. 顺序播放 =====
          _buildSelectItem<PlayRepeat>(
            icon: Icons.repeat,
            title: '播放顺序',
            subtitle: '当前: ${PlayRepeat.values[PlayerPref.playRepeat].label}',
            values: PlayRepeat.values,
            displayValues: PlayRepeat.values.map((e) => e.label).toList(),
            currentValue: PlayRepeat.values[PlayerPref.playRepeat],
            onSelected: (value) {
              PlayerPref.playRepeat = value.index;
              _refresh();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ========== 原有方法 ==========
  String _getEngineLabel() {
    final currentType = PlayerPref.playerEngine;
    return currentType == PlayerEngineType.mediaKit ? '当前：MPV（默认）' : '当前：MDK（实验性）';
  }

  String _getStrategyLabel(int index) {
    switch (index) {
      case 0: return '当前：智能模式（推荐）';
      case 1: return '当前：完整模式';
      case 2: return '当前：最小模式';
      default: return '当前：智能模式（推荐）';
    }
  }

  String _getParseModeLabel(int index) {
    switch (index) {
      case 0: return '当前：顺序解析';
      case 1: return '当前：并发解析';
      default: return '当前：顺序解析';
    }
  }

  String _getPushModeLabel(int index) {
    switch (index) {
      case 0: return '当前：手动推送';
      case 1: return '当前：自动模式';
      default: return '当前：手动推送';
    }
  }

  void _showEngineDialog() async {
    final result = await PlayerEngineDialog.show(context);
    if (result == null) return;

    final currentType = PlayerPref.playerEngine;
    final newType = result == PlayerEngineOption.mpv
        ? PlayerEngineType.mediaKit
        : PlayerEngineType.fvp;

    if (newType == currentType) return;

    SmartDialog.showLoading(msg: '正在切换播放器...');
    try {
      final controller = PlPlayerController.getInstance();
      await controller.switchEngine(newType);
      SmartDialog.dismiss();
      setState(() {});
      SmartDialog.showToast('已切换到 ${result.title} 播放器');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('切换失败：$e');
    }
  }

  void _showHeaderStrategyDialog() async {
    final result = await HeaderStrategyDialog.show(context);
    if (result != null) {
      _headerStrategy = result.index;
      PlayerPref.requestHeaderStrategy = result.index;
      _refresh();
    }
  }

  void _showParseModeDialog() async {
    final result = await ParseModeDialog.show(context);
    if (result != null) {
      _parseMode = result.index;
      PlayerPref.parseMode = result.index;
      _refresh();
    }
  }

  void _showPushModeDialog() async {
    final result = await PushModeDialog.show(context);
    if (result != null) {
      _pushMode = result.index;
      PlayerPref.pushMode = result.index;
      _refresh();
    }
  }

  // ========== 统一图标容器 ==========

  Widget _buildIconContainer(IconData icon) {
    final colorScheme = ColorScheme.of(context);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.2),
        borderRadius: Style.mdRadius,
      ),
      child: Icon(icon, color: colorScheme.primary, size: 24),
    );
  }

  // ========== UI 组件 ==========

  /// 原有卡片式设置项（用于请求头策略、解析模式、推送模式）
  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: Style.mdRadius,
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildIconContainer(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
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
      ),
    );
  }

  /// Switch 项（新增）
  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    String? subtitle,
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
          _buildIconContainer(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                if (subtitle != null)
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

  /// 跳转项（新增）
  Widget _buildNavigateItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: Style.mdRadius,
      onTap: onTap,
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
            _buildIconContainer(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  if (subtitle != null)
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
            Icon(Icons.chevron_right, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }

  /// 选择项（新增）
  Widget _buildSelectItem<T>({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<T> values,
    required List<String> displayValues,
    required T currentValue,
    required ValueChanged<T> onSelected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: Style.mdRadius,
      onTap: () async {
        final result = await showDialog<T>(
          context: context,
          builder: (context) => SelectDialog<T>(
            title: title,
            value: currentValue,
            values: values.asMap().entries.map((e) => (e.value, displayValues[e.key])).toList(),
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
            _buildIconContainer(icon),
            const SizedBox(width: 12),
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
            Icon(Icons.chevron_right, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}