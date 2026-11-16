import 'package:flutter/material.dart';

import 'package:yuanying/plugin/pl_player/player_pref.dart';

/// 信息显示配置弹窗（全屏播放器右上角"更多设置" → 信息显示）
class InfoDisplayDialog extends StatefulWidget {
  const InfoDisplayDialog({super.key});

  @override
  State<InfoDisplayDialog> createState() => _InfoDisplayDialogState();
}

class _InfoDisplayDialogState extends State<InfoDisplayDialog> {
  static const _positions = ['关', '左上', '右上', '左下', '右下'];
  static const _styles = ['无底', '黑底', '黑底+阴影'];
  static const _insetPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 24);
  static const _borderRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.8;

    return Dialog(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
      insetPadding: _insetPadding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== 标题栏 =====
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.dashboard_customize_outlined,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '信息显示',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: colorScheme.outline,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            // ===== 选项列表 =====
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    _buildRow('电量', PlayerPref.batteryPosition, (v) {
                      PlayerPref.batteryPosition = v;
                      setState(() {});
                    }),
                    _buildRow('当前时间', PlayerPref.infoTimePosition, (v) {
                      PlayerPref.infoTimePosition = v;
                      setState(() {});
                    }),
                    _buildRow('视频帧率', PlayerPref.infoFpsPosition, (v) {
                      PlayerPref.infoFpsPosition = v;
                      setState(() {});
                    }),
                    _buildRow('分辨率', PlayerPref.infoResolutionPosition, (v) {
                      PlayerPref.infoResolutionPosition = v;
                      setState(() {});
                    }),
                    _buildRow('播放进度', PlayerPref.infoProgressPosition, (v) {
                      PlayerPref.infoProgressPosition = v;
                      setState(() {});
                    }),
                    _buildRow('网速', PlayerPref.infoSpeedPosition, (v) {
                      PlayerPref.infoSpeedPosition = v;
                      setState(() {});
                    }),
                    const SizedBox(height: 6),
                    _buildStyleRow(),
                  ],
                ),
              ),
            ),
            // ===== 说明文案 =====
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                '仅在全屏下生效，选中的信息常驻在画面角落，不随操作菜单隐藏。'
                '帧率取决于视频源，网速仅 MPV 内核支持。无数据时显示 --。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 位置行（5 列：关 / 左上 / 右上 / 左下 / 右下） =====
  Widget _buildRow(String label, int current, ValueChanged<int> onChanged) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
            ),
          ),
          Expanded(
            child: Row(
              children: List.generate(_positions.length, (i) {
                final selected = i == current;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          // 极淡主色底；若需纯无背景，删掉本行 color 即可
                          color: selected
                              ? colorScheme.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          border: Border.all(
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.outline.withValues(alpha: 0.3),
                            width: selected ? 1.2 : 1.0,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _positions[i],
                          style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ===== 样式行（3 列：无底 / 黑底 / 黑底+阴影） =====
  Widget _buildStyleRow() {
    final colorScheme = Theme.of(context).colorScheme;
    final current = PlayerPref.infoBadgeStyle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '样式',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
            ),
          ),
          Expanded(
            child: Row(
              children: List.generate(_styles.length, (i) {
                final selected = i == current;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        PlayerPref.infoBadgeStyle = i;
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          // 极淡主色底；若需纯无背景，删掉本行 color 即可
                          color: selected
                              ? colorScheme.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          border: Border.all(
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.outline.withValues(alpha: 0.3),
                            width: selected ? 1.2 : 1.0,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _styles[i],
                          style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}