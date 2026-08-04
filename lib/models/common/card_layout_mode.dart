import 'package:flutter/material.dart';

/// 首页卡片布局模式
enum CardLayoutMode {
  /// 三列网格（默认）
  grid3(
    label: '三列',
    icon: Icons.grid_view,
    modeIndex: 0,
  ),
  /// 两列网格
  grid2(
    label: '两列',
    icon: Icons.view_column,
    modeIndex: 1,
  ),
  /// 图文列表
  list(
    label: '列表',
    icon: Icons.format_list_bulleted,  // 更换为无边框简洁图标
    modeIndex: 2,
  );

  final String label;
  final IconData icon;
  final int modeIndex;

  const CardLayoutMode({
    required this.label,
    required this.icon,
    required this.modeIndex,
  });

  static CardLayoutMode fromIndex(int index) {
    return CardLayoutMode.values.firstWhere(
      (e) => e.modeIndex == index,
      orElse: () => CardLayoutMode.grid3,
    );
  }

  CardLayoutMode next() {
    final nextIndex = (modeIndex + 1) % CardLayoutMode.values.length;
    return CardLayoutMode.fromIndex(nextIndex);
  }

  bool get isGrid => this != CardLayoutMode.list;

  int get columns {
    switch (this) {
      case CardLayoutMode.grid3:
        return 3;
      case CardLayoutMode.grid2:
        return 2;
      case CardLayoutMode.list:
        return 0;
    }
  }
}