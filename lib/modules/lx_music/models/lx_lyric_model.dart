/// 单个字/词（逐字歌词用）
class LxLyricWord {
  final Duration time;
  final String text;
  Duration? duration;

  LxLyricWord({
    required this.time,
    required this.text,
    this.duration,
  });
}

/// 歌词行
class LxLyricLine {
  final Duration time;
  final String text;
  final String? translation;
  final String? romanization;
  final List<LxLyricWord>? words;

  LxLyricLine({
    required this.time,
    required this.text,
    this.translation,
    this.romanization,
    this.words,
  });

  bool get hasWords => words != null && words!.isNotEmpty;
}