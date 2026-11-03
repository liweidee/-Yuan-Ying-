import 'package:flutter/material.dart';

enum BgSourceType {
  none,      // 无
  gradient,  // 渐变色
  preset,    // 预设图
  custom,    // 自定义上传
}

class BgGradientPreset {
  final String label;
  final List<Color> colors;

  const BgGradientPreset(this.label, this.colors);
}

/// 7 套渐变色预设，与 DsPlayer 主题色板对应
const kBgGradients = <BgGradientPreset>[
  BgGradientPreset('晨雾纸白', [Color(0xFFF5F1E8), Color(0xFFE8E2D6)]),
  BgGradientPreset('暗夜蓝黑', [Color(0xFF1A2332), Color(0xFF0A0E14)]),
  BgGradientPreset('暮色暖橙', [Color(0xFFE89A5C), Color(0xFF8B3A1E)]),
  BgGradientPreset('海雾青蓝', [Color(0xFF7AB8C9), Color(0xFF2B5A6B)]),
  BgGradientPreset('紫霞',     [Color(0xFFB88DC9), Color(0xFF5D3A73)]),
  BgGradientPreset('森野晨绿', [Color(0xFF8FB87D), Color(0xFF2D4A26)]),
  BgGradientPreset('灰岩',     [Color(0xFFB0B5BC), Color(0xFF4A4F57)]),
];