import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/modules/setting/widgets/slider_dialog.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/feed_back.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

class ExtraSettingPage extends StatefulWidget {
  const ExtraSettingPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<ExtraSettingPage> createState() => _ExtraSettingPageState();
}

class _ExtraSettingPageState extends State<ExtraSettingPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showAppBar = widget.showAppBar;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      resizeToAvoidBottomInset: false,
      appBar: showAppBar
          ? AppBar(
              title: const Text('其它设置'),
              centerTitle: false,
              elevation: 0,
              backgroundColor: theme.colorScheme.surface,
              foregroundColor: theme.colorScheme.onSurface,
            )
          : null,
      body: ListView(
        padding: EdgeInsets.only(
          left: Style.safeSpace,
          right: Style.safeSpace,
          bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
        ),
        children: [
          // ===== 禁用 SSL 证书验证 =====
          _buildSwitchItem(
            icon: Icons.security,
            title: '禁用 SSL 证书验证',
            subtitle: '谨慎开启，禁用容易受到中间人攻击',
            value: SettingPref.badCertificateCallback,
            onChanged: (v) {
              SettingPref.badCertificateCallback = v;
              setState(() {});
            },
            needReboot: true,
          ),
          const SizedBox(height: 8),

          // ===== 横向滑动阈值 =====
          _buildNavigateItem(
            icon: Icons.pan_tool_alt_outlined,
            title: '横向滑动阈值',
            subtitle: '当前: ${SettingPref.touchSlopH}',
            onTap: () => _showTouchSlopDialog(context, () => setState(() {})),
          ),
          const SizedBox(height: 8),

          // ===== 刷新滑动距离 =====
          _buildNavigateItem(
            icon: Icons.refresh,
            title: '刷新滑动距离',
            subtitle: '当前滑动距离: ${SettingPref.refreshDragPercentage}x',
            onTap: () => _showRefreshDragDialog(context, () => setState(() {})),
          ),
          const SizedBox(height: 8),

          // ===== 刷新指示器高度 =====
          _buildNavigateItem(
            icon: Icons.height,
            title: '刷新指示器高度',
            subtitle: '当前指示器高度: ${SettingPref.refreshDisplacement}',
            onTap: () => _showRefreshDialog(context, () => setState(() {})),
          ),
          const SizedBox(height: 8),

          // ===== 侧滑关闭二级页面 =====
          _buildSwitchItem(
            icon: Icons.touch_app_outlined,
            title: '侧滑关闭二级页面',
            subtitle: '开启后可通过侧滑手势关闭页面（需重启应用）',
            value: SettingPref.slideDismissReplyPage,
            onChanged: (v) {
              SettingPref.slideDismissReplyPage = v;
              setState(() {});
            },
            needReboot: true,
          ),
          const SizedBox(height: 8),

          // ===== 启用双指缩小视频 =====
          _buildSwitchItem(
            icon: Icons.pinch,
            title: '启用双指缩小视频',
            subtitle: '开启后双指捏合可缩小视频画面',
            value: SettingPref.enableShrinkVideoSize,
            onChanged: (v) {
              SettingPref.enableShrinkVideoSize = v;
              setState(() {});
            },
            needReboot: true,
          ),
          const SizedBox(height: 8),

          // ===== 启用 HTTP/2 =====
          _buildSwitchItem(
            icon: Icons.swap_horizontal_circle_outlined,
            title: '启用 HTTP/2',
            subtitle: null,
            value: SettingPref.enableHttp2,
            onChanged: (v) {
              SettingPref.enableHttp2 = v;
              setState(() {});
            },
            needReboot: true,
          ),
          const SizedBox(height: 8),

          // ===== 震动反馈 =====
          _buildSwitchItem(
            icon: Icons.vibration_outlined,
            title: '震动反馈',
            subtitle: '请确定手机设置中已开启震动反馈',
            value: PlayerPref.feedBackEnable,
            onChanged: (v) {
              PlayerPref.feedBackEnable = v;
              enableFeedback = v;  // 更新 feed_back.dart 中的全局变量
              setState(() {});
            },
          ),
          const SizedBox(height: 8),

          // ===== 设置代理 =====
          _buildProxyItem(
            context: context,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),

          // ===== 自动清除缓存 =====
          _buildSwitchItem(
            icon: Icons.auto_delete_outlined,
            title: '自动清除缓存',
            subtitle: '每次启动时清除缓存',
            value: SettingPref.autoClearCache,
            onChanged: (v) {
              SettingPref.autoClearCache = v;
              setState(() {});
            },
          ),
          const SizedBox(height: 8),

          // ===== 最大缓存大小 =====
          _buildNavigateItem(
            icon: Icons.delete_outlined,
            title: '最大缓存大小',
            subtitle: () {
              final num = SettingPref.maxCacheSize;
              return '当前最大缓存大小: ${num == 0 ? "无限" : _formatSize(num)}';
            }(),
            onTap: () => _showCacheDialog(context, () => setState(() {})),
          ),
          const SizedBox(height: 8),

          // ===== 检查更新 =====
          _buildSwitchItem(
            icon: Icons.system_update_alt,
            title: '检查更新',
            subtitle: '每次启动时检查是否需要更新',
            value: SettingPref.autoUpdate,
            onChanged: (v) {
              SettingPref.autoUpdate = v;
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================================
  // UI 构建方法（与 setting_page.dart 完全一致）
  // ============================================================

  /// 带图标的设置项卡片（点击跳转）
  Widget _buildNavigateItem({
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
              // 图标背景容器
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.2),
                  borderRadius: Style.mdRadius,
                ),
                child: Icon(icon, color: colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
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

  /// 带开关的设置项卡片
  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool needReboot = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
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
            // 图标背景容器
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.2),
                borderRadius: Style.mdRadius,
              ),
              child: Icon(icon, color: colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null)
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
            Switch(
              value: value,
              onChanged: (v) {
                onChanged(v);
                if (needReboot) {
                  SmartDialog.showToast('重启生效');
                }
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  /// 代理设置项（Split 样式）
  Widget _buildProxyItem({
    required BuildContext context,
    required VoidCallback onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool enabled = SettingPref.enableSystemProxy;

    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
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
            // 图标背景容器
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.2),
                borderRadius: Style.mdRadius,
              ),
              child: Icon(Icons.airplane_ticket_outlined, color: colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => _showProxyDialog(context, onChanged),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '设置代理',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '设置代理 host:port',
                        style: TextStyle(fontSize: 12, color: colorScheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 25,
              child: VerticalDivider(
                width: 1,
                color: colorScheme.outline.withOpacity(0.3),
              ),
            ),
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: enabled,
                onChanged: (v) {
                  SettingPref.enableSystemProxy = v;
                  onChanged();
                  SmartDialog.showToast('重启生效');
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 对话框函数
  // ============================================================

  void _showInputDialog({
    required BuildContext context,
    required String title,
    required String hintText,
    required String suffixText,
    required String initialValue,
    required void Function(String value) onConfirm,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    String value = initialValue;
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
          backgroundColor: colorScheme.surface,
          title: Text(title, style: TextStyle(color: colorScheme.onSurface)),
          content: TextFormField(
            autofocus: true,
            initialValue: initialValue,
            keyboardType: keyboardType,
            onChanged: (v) => value = v,
            inputFormatters: inputFormatters,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: colorScheme.outline.withOpacity(0.5)),
              suffixText: suffixText,
              suffixStyle: TextStyle(color: colorScheme.outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '取消',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                onConfirm(value);
                Get.back();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _showTouchSlopDialog(BuildContext context, VoidCallback setState) {
    _showInputDialog(
      context: context,
      title: '横向滑动阈值',
      hintText: '请输入阈值',
      suffixText: '',
      initialValue: SettingPref.touchSlopH.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[\d.]+$'))],
      onConfirm: (value) {
        try {
          final val = double.parse(value);
          StorageManager.setSetting(SettingBoxKey.touchSlopH, val);
          setState();
          SmartDialog.showToast('设置成功');
        } catch (_) {
          SmartDialog.showToast('请输入有效数字');
        }
      },
    );
  }

  void _showRefreshDragDialog(BuildContext context, VoidCallback setState) async {
    final res = await showDialog<double>(
      context: context,
      builder: (context) => SliderDialog(
        title: const Text('刷新滑动距离'),
        min: 0.1,
        max: 0.5,
        divisions: 8,
        precise: 2,
        value: SettingPref.refreshDragPercentage,
        suffix: 'x',
      ),
    );
    if (res != null) {
      StorageManager.setSetting(SettingBoxKey.refreshDragPercentage, res);
      setState();
      SmartDialog.showToast('设置成功');
    }
  }

  void _showRefreshDialog(BuildContext context, VoidCallback setState) async {
    final res = await showDialog<double>(
      context: context,
      builder: (context) => SliderDialog(
        title: const Text('刷新指示器高度'),
        min: 10.0,
        max: 100.0,
        divisions: 9,
        value: SettingPref.refreshDisplacement,
      ),
    );
    if (res != null) {
      StorageManager.setSetting(SettingBoxKey.refreshDisplacement, res);
      setState();
      SmartDialog.showToast('设置成功');
    }
  }

  void _showCacheDialog(BuildContext context, VoidCallback setState) {
    _showInputDialog(
      context: context,
      title: '最大缓存大小',
      hintText: '0 表示无限',
      suffixText: 'MB',
      initialValue: (SettingPref.maxCacheSize / (1024 * 1024)).toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[\d.]+$'))],
      onConfirm: (value) {
        try {
          final val = num.parse(value);
          StorageManager.setSetting(SettingBoxKey.maxCacheSize, val * 1024 * 1024);
          setState();
          SmartDialog.showToast('设置成功');
        } catch (_) {
          SmartDialog.showToast('请输入有效数字');
        }
      },
    );
  }

  void _showProxyDialog(BuildContext context, VoidCallback setState) {
    String host = SettingPref.systemProxyHost;
    String port = SettingPref.systemProxyPort;

    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
          backgroundColor: colorScheme.surface,
          title: Text('设置代理', style: TextStyle(color: colorScheme.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              TextFormField(
                initialValue: host,
                decoration: InputDecoration(
                  labelText: 'Host',
                  hintText: '请输入 Host，使用 . 分割',
                  hintStyle: TextStyle(color: colorScheme.outline.withOpacity(0.5)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  isDense: true,
                ),
                onChanged: (e) => host = e,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: port,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Port',
                  hintText: '请输入 Port',
                  hintStyle: TextStyle(color: colorScheme.outline.withOpacity(0.5)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  isDense: true,
                ),
                onChanged: (e) => port = e,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '取消',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                Get.back();
                StorageManager.setSetting(SettingBoxKey.systemProxyHost, host);
                StorageManager.setSetting(SettingBoxKey.systemProxyPort, port);
                setState();
                SmartDialog.showToast('代理设置已保存，重启生效');
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  String _formatSize(num value) {
    const unitArr = ['B', 'K', 'M', 'G', 'T', 'P'];
    int index = 0;
    var v = value.toDouble();
    while (v >= 1024) {
      index++;
      v = v / 1024;
    }
    return '${v.toStringAsFixed(2)}${unitArr[index]}';
  }
}