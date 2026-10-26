// lib/modules/action/widgets/simple_html_text.dart
import 'package:flutter/material.dart';

/// 轻量 HTML 渲染器：
///
/// 支持以下标签（可嵌套）：
///   - `<b>` / `<strong>`      加粗
///   - `<i>` / `<em>`          斜体
///   - `<u>`                   下划线
///   - `<s>` / `<del>`         删除线
///   - `<font color="...">`    字体颜色
///     （支持 red / blue / #RRGGBB / #RGB / rgb(r,g,b) / rgba(r,g,b,a)）
///   - `<span style="color:...">`  简化支持内联 color
///   - `<br>` / `<br/>`        换行
///   - `<p>`                   段落（行尾自动换行）
///   - `<code>`                等宽字体 + 淡背景
///
/// 其他标签一律当作纯文本处理（剥离掉标签本身）。
class SimpleHtmlText extends StatelessWidget {
  const SimpleHtmlText({
    super.key,
    required this.data,
    this.baseStyle,
    this.textAlign = TextAlign.start,
    this.maxLines,
  });

  final String data;
  final TextStyle? baseStyle;
  final TextAlign textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveBase = (baseStyle ??
            TextStyle(
              fontSize: 14,
              color: cs.onSurface,
              height: 1.5,
            ))
        .copyWith();

    final spans = _parse(data, effectiveBase, cs);

    return RichText(
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : TextOverflow.clip,
      text: TextSpan(children: spans),
    );
  }

  // ============================================================
  // 解析主逻辑
  // ============================================================

  List<TextSpan> _parse(String html, TextStyle base, ColorScheme cs) {
    final spans = <TextSpan>[];
    final buffer = StringBuffer();

    // 样式栈：每个元素记录它"进入"时新加的样式
    final styleStack = <TextStyle>[base];

    // 段落标记：处理 <p> 自动换行
    bool pendingParagraphBreak = false;

    void flush() {
      if (buffer.isEmpty) return;
      final currentStyle = styleStack.last;

      // 有未处理的段落换行，前置换行符
      final text = pendingParagraphBreak && spans.isNotEmpty
          ? '\n${buffer.toString()}'
          : buffer.toString();
      pendingParagraphBreak = false;

      spans.add(TextSpan(text: text, style: currentStyle));
      buffer.clear();
    }

    int i = 0;
    while (i < html.length) {
      final char = html[i];

      if (char == '<') {
        // 找到标签结束
        final end = html.indexOf('>', i);
        if (end == -1) {
          // 不闭合的 `<`，当普通字符
          buffer.write(char);
          i++;
          continue;
        }

        final tagContent = html.substring(i + 1, end).trim();
        final isClosing = tagContent.startsWith('/');
        final tagName = (isClosing ? tagContent.substring(1) : tagContent)
            .split(RegExp(r'\s'))
            .first
            .toLowerCase();

        if (tagName.isEmpty) {
          // 空标签 `<>`，当普通字符
          buffer.write(char);
          i++;
          continue;
        }

        // ---- 换行标签 ----
        if (tagName == 'br') {
          buffer.write('\n');
          i = end + 1;
          continue;
        }

        // ---- 段落标签 ----
        if (tagName == 'p') {
          if (isClosing) {
            buffer.write('\n');
          } else if (spans.isNotEmpty || buffer.isNotEmpty) {
            pendingParagraphBreak = true;
          }
          i = end + 1;
          continue;
        }

        // ---- 有样式的标签 ----
        if ([
          'b',
          'strong',
          'i',
          'em',
          'u',
          's',
          'del',
          'code',
          'font',
          'span',
        ].contains(tagName)) {
          flush();

          if (isClosing) {
            if (styleStack.length > 1) {
              styleStack.removeLast();
            }
          } else {
            final currentStyle = styleStack.last;
            final newStyle = _applyTagStyle(
              tagName: tagName,
              attrs: tagContent.substring(tagName.length).trim(),
              base: currentStyle,
              cs: cs,
            );
            styleStack.add(newStyle);
          }
          i = end + 1;
          continue;
        }

        // ---- 其他未知标签：剥离 ----
        i = end + 1;
        continue;
      }

      // ---- 普通字符 ----
      buffer.write(char);
      i++;
    }

    flush();
    return spans;
  }

  // ============================================================
  // 标签样式映射
  // ============================================================

  TextStyle _applyTagStyle({
    required String tagName,
    required String attrs,
    required TextStyle base,
    required ColorScheme cs,
  }) {
    switch (tagName) {
      case 'b':
      case 'strong':
        return base.copyWith(fontWeight: FontWeight.bold);

      case 'i':
      case 'em':
        return base.copyWith(fontStyle: FontStyle.italic);

      case 'u':
        // 修正：TextStyle.copyWith 的参数名是 decoration，不是 textDecoration
        return base.copyWith(decoration: TextDecoration.underline);

      case 's':
      case 'del':
        // 修正：同上
        return base.copyWith(decoration: TextDecoration.lineThrough);

      case 'code':
        return base.copyWith(
          fontFamily: 'monospace',
          backgroundColor:
              cs.surfaceContainerHighest.withValues(alpha: 0.6),
        );

      case 'font':
        final color = _extractColorFromAttrs(attrs, cs);
        return color != null ? base.copyWith(color: color) : base;

      case 'span':
        final color = _extractColorFromStyle(attrs, cs);
        return color != null ? base.copyWith(color: color) : base;

      default:
        return base;
    }
  }

  // ============================================================
  // 颜色解析
  // ============================================================

  /// 从 `<font color="red">` 的属性串提取颜色
  Color? _extractColorFromAttrs(String attrs, ColorScheme cs) {
    final match = RegExp(
      r'''color\s*=\s*["']?\s*([^"'\s>]+)''',
      caseSensitive: false,
    ).firstMatch(attrs);
    if (match == null) return null;
    return _parseColorValue(match.group(1), cs);
  }

  /// 从 `<span style="color: red">` 的属性串提取颜色
  Color? _extractColorFromStyle(String attrs, ColorScheme cs) {
    final match = RegExp(
      r'''color\s*:\s*([^;"'\s]+)''',
      caseSensitive: false,
    ).firstMatch(attrs);
    if (match == null) return null;
    return _parseColorValue(match.group(1), cs);
  }

  /// 解析颜色值：red / #RRGGBB / #RGB / rgb(r,g,b) / rgba(r,g,b,a)
  Color? _parseColorValue(String? raw, ColorScheme cs) {
    if (raw == null || raw.isEmpty) return null;
    final value = raw.trim().toLowerCase();

    // ---- 主题色关键字（依赖 cs，不能用 const） ----
    switch (value) {
      case 'primary':
        return cs.primary;
      case 'secondary':
        return cs.secondary;
      case 'error':
        return cs.error;
    }

    // ---- 命名色（全部是 const Color，可以用 const Map） ----
    const named = <String, Color>{
      'red': Color(0xFFF44336),
      'green': Color(0xFF4CAF50),
      'blue': Color(0xFF2196F3),
      'yellow': Color(0xFFFFEB3B),
      'orange': Color(0xFFFF9800),
      'purple': Color(0xFF9C27B0),
      'pink': Color(0xFFE91E63),
      'cyan': Color(0xFF00BCD4),
      'teal': Color(0xFF009688),
      'brown': Color(0xFF795548),
      'gray': Color(0xFF9E9E9E),
      'grey': Color(0xFF9E9E9E),
      'black': Color(0xFF000000),
      'white': Color(0xFFFFFFFF),
    };
    if (named.containsKey(value)) return named[value];

    // ---- #RRGGBB ----
    if (value.startsWith('#') && value.length == 7) {
      try {
        return Color(int.parse('FF${value.substring(1)}', radix: 16));
      } catch (_) {}
    }

    // ---- #RGB ----
    if (value.startsWith('#') && value.length == 4) {
      try {
        final r = value[1];
        final g = value[2];
        final b = value[3];
        return Color(int.parse('FF$r$r$g$g$b$b', radix: 16));
      } catch (_) {}
    }

    // ---- rgb(r,g,b) / rgba(r,g,b,a) ----
    final rgbMatch = RegExp(
            r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)')
        .firstMatch(value);
    if (rgbMatch != null) {
      try {
        final r = int.parse(rgbMatch.group(1)!);
        final g = int.parse(rgbMatch.group(2)!);
        final b = int.parse(rgbMatch.group(3)!);
        final aStr = rgbMatch.group(4);
        final a = aStr != null ? (double.tryParse(aStr) ?? 1.0) : 1.0;
        return Color.fromRGBO(r, g, b, a.clamp(0.0, 1.0));
      } catch (_) {}
    }

    return null;
  }
}