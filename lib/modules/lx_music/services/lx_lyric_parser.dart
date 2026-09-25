import '../models/lx_lyric_model.dart';

/// LRC 歌词解析器
///
/// 输出 [LxLyricLine] 列表，供 flutter_lyric 或自绘使用。
class LxLyricParser {
  LxLyricParser._();

  static final RegExp _timeRegExp =
      RegExp(r'\[(\d{2}):(\d{2})\.?(\d{0,3})\]');
  static final RegExp _tagRegExp = RegExp(r'\[([a-zA-Z]+):(.+)\]');
  static final RegExp _wordTimeRegExp = RegExp(r'<(\d{2}):(\d{2})\.?(\d{0,3})>');

  static List<LxLyricLine> parse(String lyricText) {
    if (lyricText.isEmpty) return [];

    final List<LxLyricLine> lines = [];
    final Map<String, String> tags = {};
    final List<MapEntry<Duration, String>> timedLines = [];

    final List<String> rawLines = lyricText.split('\n');

    for (final line in rawLines) {
      final String trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      final tagMatch = _tagRegExp.firstMatch(trimmedLine);
      if (tagMatch != null) {
        tags[tagMatch.group(1)!] = tagMatch.group(2)!;
        continue;
      }

      final matches = _timeRegExp.allMatches(trimmedLine).toList();
      if (matches.isEmpty) continue;

      final String text = trimmedLine.replaceAll(_timeRegExp, '').trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final time = _parseDuration(
            match.group(1)!, match.group(2)!, match.group(3)!);
        timedLines.add(MapEntry(time, text));
      }
    }

    timedLines.sort((a, b) => a.key.compareTo(b.key));

    for (final entry in timedLines) {
      final words = _parseWords(entry.value);
      if (words != null && words.isNotEmpty) {
        lines.add(LxLyricLine(
          time: words.first.time,
          text: words.map((w) => w.text).join(),
          words: words,
        ));
      } else {
        lines.add(LxLyricLine(
          time: entry.key,
          text: entry.value,
        ));
      }
    }

    return lines;
  }

  static List<LxLyricWord>? _parseWords(String lineText) {
    final matches = _wordTimeRegExp.allMatches(lineText).toList();
    if (matches.isEmpty) return null;

    final words = <LxLyricWord>[];
    final pureText = lineText.replaceAll(_wordTimeRegExp, '').trim();
    if (pureText.isEmpty) return null;

    final chars = pureText.split('');
    if (matches.length == chars.length) {
      for (int i = 0; i < matches.length; i++) {
        final m = matches[i];
        final t = _parseDuration(m.group(1)!, m.group(2)!, m.group(3)!);
        words.add(LxLyricWord(time: t, text: chars[i]));
      }
    } else if (matches.length < chars.length) {
      for (int i = 0; i < chars.length; i++) {
        final tagIdx = (i * matches.length / chars.length)
            .floor()
            .clamp(0, matches.length - 1);
        final m = matches[tagIdx];
        final t = _parseDuration(m.group(1)!, m.group(2)!, m.group(3)!);
        words.add(LxLyricWord(time: t, text: chars[i]));
      }
    } else {
      for (int i = 0; i < chars.length; i++) {
        final m = matches[i];
        final t = _parseDuration(m.group(1)!, m.group(2)!, m.group(3)!);
        words.add(LxLyricWord(time: t, text: chars[i]));
      }
    }

    for (int i = 0; i < words.length; i++) {
      words[i].duration = i + 1 < words.length
          ? words[i + 1].time - words[i].time
          : const Duration(seconds: 1);
    }

    return words;
  }

  static Duration _parseDuration(String mm, String ss, String ms) {
    final int minutes = int.parse(mm);
    final int seconds = int.parse(ss);
    final int milliseconds = ms.isNotEmpty ? int.parse(ms.padRight(3, '0')) : 0;
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  /// 合并翻译
  static List<LxLyricLine> mergeWithTranslation(
    List<LxLyricLine> original,
    String? translationText,
  ) {
    if (translationText == null || translationText.isEmpty) {
      return original;
    }

    final List<LxLyricLine> translationLines = parse(translationText);
    final Map<Duration, String> translationMap = {
      for (final line in translationLines) line.time: line.text,
    };

    return original.map((line) {
      final translation = translationMap[line.time];
      return LxLyricLine(
        time: line.time,
        text: line.text,
        translation: translation,
        words: line.words,
      );
    }).toList();
  }
}