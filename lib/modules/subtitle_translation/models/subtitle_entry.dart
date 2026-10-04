/// 字幕条目（翻译模块专用，与项目的 Subtitle 解耦）。
class SubtitleEntry {
  const SubtitleEntry({
    required this.start,
    required this.end,
    required this.text,
    this.translatedText,
  });

  final Duration start;
  final Duration end;
  final String text;
  final String? translatedText;

  SubtitleEntry copyWith({
    Duration? start,
    Duration? end,
    String? text,
    String? translatedText,
  }) {
    return SubtitleEntry(
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
      translatedText: translatedText ?? this.translatedText,
    );
  }
}

/// 字幕翻译进度。
class SubtitleTranslationProgress {
  const SubtitleTranslationProgress({
    required this.done,
    required this.total,
  });

  final int done;
  final int total;

  double get percent => total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
}