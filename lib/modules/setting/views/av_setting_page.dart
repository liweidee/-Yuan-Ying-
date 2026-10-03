// lib/modules/setting/views/av_setting_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/plugin/pl_player/models/hwdec_type.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/common/widgets/dialog/ordered_multi_select_dialog.dart';

/// 音视频设置页
///
/// 覆盖项：
/// - 开启硬解（enableHA）
/// - 硬解模式（hardwareDecoding）
/// - 缓冲大小（bufferSize，MB）
/// - 缓冲时长（bufferSec，秒）
/// - 自动同步（autosync，0=关闭）
///
/// 说明：原项目的「首选解码格式 / 蜂窝网络首选解码格式」未对齐。
/// 原因：源影使用 T4/CatVod 协议，`PlayUrl.qualities` 只有 (label, url)，
///      没有 codec 信息；引擎打开的是一条 URL，无 DASH 多编码可选。
class AvSettingPage extends StatefulWidget {
  const AvSettingPage({super.key});

  @override
  State<AvSettingPage> createState() => _AvSettingPageState();
}

class _AvSettingPageState extends State<AvSettingPage> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('音视频设置'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: ListView(
        padding: EdgeInsets.only(
          left: Style.safeSpace,
          right: Style.safeSpace,
          bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
        ),
        children: [
          _buildEngineBanner(),
          // ===== 开启硬解 =====
          _buildSwitchItem(
            icon: Icons.flash_on_outlined,
            title: '开启硬解',
            subtitle: '以较低功耗播放视频，若异常卡死请关闭',
            value: PlayerPref.enableHA,
            onChanged: (v) {
              PlayerPref.enableHA = v;
              _refresh();
              SmartDialog.showToast('下次播放生效');
            },
          ),
          const SizedBox(height: 8),

          // ===== 硬解模式 =====
          _buildNavigateItem(
            icon: Icons.memory_outlined,
            title: '硬解模式',
            subtitle: '当前：${PlayerPref.hardwareDecoding.replaceAll(',', ' → ')}',
            onTap: _showHwDecDialog,
          ),
          const SizedBox(height: 8),

          // ===== 缓冲大小 =====
          _buildNavigateItem(
            icon: Icons.storage_outlined,
            title: '缓冲大小',
            subtitle:
                '当前：${PlayerPref.bufferSize}MB（前向和后向缓冲区大小，对应 mpv 的 --demuxer-max-bytes）',
            onTap: () => _showDecimalDialog(
              title: '缓冲大小',
              currentValue: PlayerPref.bufferSize,
              suffix: 'MB',
              min: 1,
              max: 1024,
              onConfirm: (v) => PlayerPref.bufferSize = v,
            ),
          ),
          const SizedBox(height: 8),

          // ===== 缓冲时长 =====
          _buildNavigateItem(
            icon: Icons.av_timer,
            title: '缓冲时长',
            subtitle:
                '当前：${PlayerPref.bufferSec}s（实际缓冲为大小/时长二者最小值，对应 mpv 的 --cache-secs）',
            onTap: () => _showDecimalDialog(
              title: '缓冲时长',
              currentValue: PlayerPref.bufferSec,
              suffix: 's',
              min: 1,
              max: 300,
              onConfirm: (v) => PlayerPref.bufferSec = v,
            ),
          ),
          const SizedBox(height: 8),

          // ===== 自动同步 =====
          _buildNavigateItem(
            icon: Icons.sync_rounded,
            title: '自动同步',
            subtitle:
                '当前：${PlayerPref.autosync}（0 表示关闭，对应 mpv 的 --autosync）',
            onTap: _showAutoSyncDialog,
          ),
          const SizedBox(height: 8),

          // ===== 底部说明 =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Text(
              '提示：以上设置仅对 MPV 内核生效，MDK 内核（FVP）不支持。'
              '修改后请在切换剧集或重新打开视频时观察效果。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部内核提示条：告知用户当前内核是否支持这些设置
  Widget _buildEngineBanner() {
    final colorScheme = ColorScheme.of(context);
    final isMpv = PlayerPref.playerEngine == PlayerEngineType.mediaKit;

    if (isMpv) {
      // MPV 内核：中性信息条
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withOpacity(0.35),
          borderRadius: Style.mdRadius,
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '当前内核：MPV（以下设置已生效）',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // MDK 内核：警告信息条
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withOpacity(0.4),
        borderRadius: Style.mdRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded,
                color: colorScheme.error, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前内核：MDK（FVP）',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '以下设置暂不生效。如需使用，请到「设置 → 播放设置 → 默认播放器」切换到 MPV 内核。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // UI 组件（与 extra_setting_page.dart 风格保持一致）
  // ============================================================

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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style:
                          TextStyle(fontSize: 12, color: colorScheme.outline),
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

  Widget _buildNavigateItem({
    required IconData icon,
    required String title,
    required String subtitle,
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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style:
                          TextStyle(fontSize: 12, color: colorScheme.outline),
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

  // ============================================================
  // 数值输入 Dialog（缓冲大小 / 缓冲时长）
  // ============================================================

  Future<void> _showDecimalDialog({
    required String title,
    required double currentValue,
    required String suffix,
    required double min,
    required double max,
    required ValueChanged<double> onConfirm,
  }) async {
    final controller = TextEditingController(text: currentValue.toString());
    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            decoration: InputDecoration(
              suffixText: suffix,
              suffixStyle: TextStyle(color: colorScheme.outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              helperText: '有效范围：$min ~ $max $suffix',
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
                final parsed = double.tryParse(controller.text);
                if (parsed == null) {
                  SmartDialog.showToast('请输入有效数字');
                  return;
                }
                if (parsed < min || parsed > max) {
                  SmartDialog.showToast('数值超出范围');
                  return;
                }
                Get.back(result: parsed);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (result == null) return;
    onConfirm(result);
    _refresh();
    SmartDialog.showToast('设置已保存，下次播放生效');
  }

  // ============================================================
  // 自动同步 Dialog（整数输入）
  // ============================================================

  Future<void> _showAutoSyncDialog() async {
    final controller = TextEditingController(text: PlayerPref.autosync);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
          title: const Text('自动同步'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              helperText: '0 表示关闭；移动端常用 30，桌面端可保持 0',
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
                final v = controller.text.trim();
                if (v.isEmpty) {
                  SmartDialog.showToast('请输入数字');
                  return;
                }
                Get.back(result: v);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (result == null) return;
    PlayerPref.autosync = result;
    _refresh();
    SmartDialog.showToast('设置已保存，下次播放生效');
  }

  // ============================================================
  // 硬解模式 Dialog（单选，对齐源影现有 setting_sheet 的交互）
  // ============================================================
  //
  // 说明：PiliPlus 的硬解模式是 OrderedMultiSelect（可设置回退链），
  // 存储格式为逗号分隔字符串（"mediacodec,auto-safe"）。
  // 源影的 PlayerPref.hardwareDecoding 同样是 String，因此：
  //   - 若用户通过 PiliPlus 导入了带逗号的旧值，media_kit 会原样传给 mpv，
  //     mpv 原生支持逗号回退链，可正常工作。
  //   - 这里 UI 用单选，选择后写入单一值。若需完全对齐 PiliPlus 的多选+排序，
  //     需要额外引入 OrderedMultiSelectDialog 组件。
  Future<void> _showHwDecDialog() async {
    // 从存储的逗号分隔字符串解析出已选列表
    // 例如 "mediacodec,auto-safe" → [HwDecType.mediacodec, HwDecType.autoSafe]
    final raw = PlayerPref.hardwareDecoding;
    final initValues = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => HwDecType.values.firstWhere(
              (e) => e.hwdec == s,
              orElse: () => HwDecType.auto,
            ))
        .toList();

    final result = await showDialog<List<HwDecType>>(
      context: context,
      builder: (context) => OrderedMultiSelectDialog<HwDecType>(
        title: '硬解模式',
        initValues: initValues,
        // 显示格式：hwdec + 描述
        values: {
          for (final e in HwDecType.values)
            e: '${e.hwdec}\n${e.desc}',
        },
      ),
    );

    if (result == null || result.isEmpty) return;

    // 存回逗号分隔字符串
    PlayerPref.hardwareDecoding = result.map((e) => e.hwdec).join(',');
    _refresh();
    SmartDialog.showToast(
      '硬解模式已切换：${result.map((e) => e.hwdec).join(' → ')}',
    );
  }
}