import 'dart:convert';

import 'package:flutter/material.dart';

/// 弹幕颜色色盘工具：默认预设、hex 互转、成对颜色解析、导入解析
///
/// - 随机彩色：每个条目是单色 `#RRGGBB`
/// - 渐变基色：每个条目是成对色 `#RRGGBB|#RRGGBB`（起始色|结束色）
/// - 兼容旧数据：渐变条目若为单色，解析为 start=end
abstract final class DanmakuColorPalette {
  // ===== 默认预设 =====
  static List<String> get defaultRandomColors =>
      _generateRandom(49, 1.0, 0.55);

  static List<String> get defaultGradientColors =>
      _generateGradient(24, 0.85, 0.55, 60.0);

  static List<String> _generateRandom(int count, double sat, double light) {
    return List.generate(count, (i) {
      final hue = i * 360.0 / count;
      return colorToHex(HSLColor.fromAHSL(1.0, hue, sat, light).toColor());
    });
  }

  static List<String> _generateGradient(
    int count,
    double sat,
    double light,
    double hueShift,
  ) {
    return List.generate(count, (i) {
      final h1 = i * 360.0 / count;
      final h2 = (h1 + hueShift) % 360;
      final start =
          colorToHex(HSLColor.fromAHSL(1.0, h1, sat, light).toColor());
      final end = colorToHex(HSLColor.fromAHSL(1.0, h2, sat, light).toColor());
      return '$start|$end';
    });
  }

  // ===== Color <-> Hex =====
  static String colorToHex(Color color) {
    final argb = color.toARGB32();
    final r = ((argb >> 16) & 0xFF).toRadixString(16).padLeft(2, '0');
    final g = ((argb >> 8) & 0xFF).toRadixString(16).padLeft(2, '0');
    final b = (argb & 0xFF).toRadixString(16).padLeft(2, '0');
    return '#${(r + g + b).toUpperCase()}';
  }

  /// 支持 `#RRGGBB` / `#AARRGGBB` / `RRGGBB`，失败返回 null
  static Color? parseHex(String hex) {
    var s = hex.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return Color(v);
  }

  // ===== 成对颜色 =====
  /// 解析成对条目。
  /// - `#AABBCC|#DDEEFF` → (start, end)
  /// - `#AABBCC` → (start, start)，兼容旧的单色渐变盘
  /// - 无法解析 → (white, white) 兜底
  static (Color, Color) parsePair(String entry) {
    final parts = entry.split('|');
    if (parts.length >= 2) {
      final s = parseHex(parts[0]) ?? Colors.white;
      final e = parseHex(parts[1]) ?? Colors.white;
      return (s, e);
    }
    final c = parseHex(entry) ?? Colors.white;
    return (c, c);
  }

  static String serializePair(Color start, Color end) {
    return '${colorToHex(start)}|${colorToHex(end)}';
  }

  // ===== 导入解析 =====
  /// 解析导入文本。渐变条目支持 `#A|#B`，也支持两个相邻单色自动配对。
  /// [preferKey] 传 `random` / `gradient` 时优先从 JSON 对应字段取。
  static List<String> parseInput(String text, {String? preferKey}) {
    final out = <String>[];
    final trimmed = text.trim();
    if (trimmed.isEmpty) return out;

    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          if (preferKey != null && decoded[preferKey] is List) {
            for (final e in decoded[preferKey] as List) {
              if (e is String) {
                final normalized = _normalizeEntry(e, preferKey);
                if (normalized != null) out.add(normalized);
              }
            }
            if (out.isNotEmpty) return out;
          }
          _scanJson(decoded, out, preferKey);
          if (out.isNotEmpty) return out;
        }
      } catch (_) {}
    }

    // 纯文本按分隔符切分
    final tokens = trimmed.split(RegExp(r'[,，;；\s\n\r\t]+'));

    if (preferKey == 'gradient') {
      // 先尝试识别完整 `#A|#B` token
      final pairRegex = RegExp(r'#[0-9A-Fa-f]{6}\|#[0-9A-Fa-f]{6}');
      for (final t in tokens) {
        if (pairRegex.hasMatch(t)) out.add(t.toUpperCase());
      }
      if (out.isNotEmpty) return out;
      // 退化为两个相邻单色配对
      final singles = <String>[];
      for (final t in tokens) {
        final c = parseHex(t);
        if (c != null) singles.add(colorToHex(c));
      }
      for (var i = 0; i + 1 < singles.length; i += 2) {
        out.add('${singles[i]}|${singles[i + 1]}');
      }
      return out;
    }

    for (final t in tokens) {
      final c = parseHex(t);
      if (c != null) out.add(colorToHex(c));
    }
    return out;
  }

  static String? _normalizeEntry(String e, String? preferKey) {
    if (preferKey == 'gradient') {
      if (e.contains('|')) {
        final parts = e.split('|');
        final s = parseHex(parts[0]);
        final en = parts.length > 1 ? parseHex(parts[1]) : null;
        if (s != null && en != null) return serializePair(s, en);
        if (s != null) return serializePair(s, s);
        return null;
      }
      final c = parseHex(e);
      if (c != null) return serializePair(c, c);
      return null;
    }
    final c = parseHex(e);
    return c != null ? colorToHex(c) : null;
  }

  static void _scanJson(dynamic v, List<String> out, String? preferKey) {
    if (v is String) {
      final n = _normalizeEntry(v, preferKey);
      if (n != null) out.add(n);
    } else if (v is List) {
      for (final e in v) {
        _scanJson(e, out, preferKey);
      }
    } else if (v is Map) {
      for (final val in v.values) {
        _scanJson(val, out, preferKey);
      }
    }
  }
}