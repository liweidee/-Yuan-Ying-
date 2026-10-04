import 'dart:convert';

import '../models/subtitle_entry.dart';

/// 字幕文本解析器。
///
/// 输入格式自动识别：
///  1. JSON `[{"from": 0.0, "to": 2.5, "content": "..."}]`（T4 站点常见）
///  2. WebVTT（`WEBVTT` 开头）
///  3. SRT（`00:00:00,000 --> ...`）
abstract final class SubtitleSrtParser {
  static List<SubtitleEntry> parse(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const [];

    // 1. JSON
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return _parseJsonList(decoded);
        }
      } catch (_) {
        // fallthrough
      }
    }

    // 2. VTT
    if (trimmed.startsWith('WEBVTT')) {
      return _parseVtt(content);
    }

    // 3. SRT
    return _parseSrt(content);
  }

  /// 序列化为 SRT 文本（优先输出译文）。
  static String serialize(List<SubtitleEntry> entries, {bool bilingual = false}) {
    final buffer = StringBuffer();
    var index = 1;
    for (final e in entries) {
      final primary = (e.translatedText != null && e.translatedText!.isNotEmpty)
          ? e.translatedText!
          : e.text;
      final display = bilingual && e.translatedText != null && e.translatedText!.isNotEmpty
          ? '$primary\n${e.text}'
          : primary;
      buffer.writeln(index);
      buffer.writeln(
        '${_fmt(e.start)} --> ${_fmt(e.end)}',
      );
      buffer.writeln(display);
      buffer.writeln();
      index++;
    }
    return buffer.toString();
  }

  // ---------------- JSON ----------------

  static List<SubtitleEntry> _parseJsonList(List<dynamic> list) {
    final out = <SubtitleEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final from = _toDouble(item['from']);
      final to = _toDouble(item['to']);
      final text = (item['content'] ?? item['text'] ?? '').toString().trim();
      if (from == null || to == null || text.isEmpty) continue;
      out.add(SubtitleEntry(
        start: Duration(milliseconds: (from * 1000).round()),
        end: Duration(milliseconds: (to * 1000).round()),
        text: text,
      ));
    }
    return out;
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // ---------------- VTT ----------------

  static List<SubtitleEntry> _parseVtt(String content) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final out = <SubtitleEntry>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty || line == 'WEBVTT' || line.startsWith('NOTE') ||
          RegExp(r'^\d+$').hasMatch(line)) {
        i++;
        continue;
      }
      if (!line.contains('-->')) {
        i++;
        continue;
      }
      final range = _parseTimestampLine(line, allowComma: false);
      if (range == null) {
        i++;
        continue;
      }
      i++;
      final textLines = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        textLines.add(lines[i]);
        i++;
      }
      final text = textLines.join('\n').trim();
      if (text.isNotEmpty) {
        out.add(SubtitleEntry(
          start: range.$1,
          end: range.$2,
          text: text,
        ));
      }
    }
    return out;
  }

  // ---------------- SRT ----------------

  static List<SubtitleEntry> _parseSrt(String content) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final out = <SubtitleEntry>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        i++;
        continue;
      }
      if (!line.contains('-->')) {
        i++;
        continue;
      }
      final range = _parseTimestampLine(line, allowComma: true);
      if (range == null) {
        i++;
        continue;
      }
      i++;
      final textLines = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        textLines.add(lines[i]);
        i++;
      }
      final text = textLines.join('\n').trim();
      if (text.isNotEmpty) {
        out.add(SubtitleEntry(
          start: range.$1,
          end: range.$2,
          text: text,
        ));
      }
    }
    return out;
  }

  static (Duration, Duration)? _parseTimestampLine(
    String line, {
    required bool allowComma,
  }) {
    final parts = line.split('-->');
    if (parts.length != 2) return null;
    final s = _parseTs(parts[0].trim());
    final e = _parseTs(parts[1].trim());
    if (s == null || e == null) return null;
    return (s, e);
  }

  static Duration? _parseTs(String s) {
    // 兼容 00:00:00,000 / 00:00:00.000 / 00:00.000
    final normalized = s.replaceAll(',', '.');
    final segs = normalized.split(':');
    if (segs.length < 2) return null;
    try {
      var hours = 0;
      var minutes = 0;
      double seconds;
      if (segs.length == 3) {
        hours = int.parse(segs[0]);
        minutes = int.parse(segs[1]);
        seconds = double.parse(segs[2]);
      } else {
        minutes = int.parse(segs[0]);
        seconds = double.parse(segs[1]);
      }
      return Duration(
        milliseconds:
            (hours * 3600000) + (minutes * 60000) + (seconds * 1000).round(),
      );
    } catch (_) {
      return null;
    }
  }

  static String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }
}