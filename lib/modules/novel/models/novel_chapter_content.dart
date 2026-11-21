import 'dart:math';

class NovelChapterParagraph {
  final String text;
  final int start;
  final int end;

  const NovelChapterParagraph({
    required this.text,
    required this.start,
    required this.end,
  });
}

class NovelTtsChunk {
  final String text;
  final int start;
  final int end;
  final int chapterIndex;

  const NovelTtsChunk({
    required this.text,
    required this.start,
    required this.end,
    required this.chapterIndex,
  });
}

class NovelChapterContent {
  final int chapterIndex;
  final String text;
  final String normalizedText;
  final List<NovelChapterParagraph> paragraphs;

  const NovelChapterContent({
    required this.chapterIndex,
    required this.text,
    required this.normalizedText,
    required this.paragraphs,
  });

  factory NovelChapterContent.fromText({
    required int chapterIndex,
    required String text,
    required String separator,
  }) {
    final normalized = <String>[];
    final paragraphs = <NovelChapterParagraph>[];
    var cursor = 0;
    for (final raw in text.split('\n')) {
      final paragraph = raw.trim();
      if (paragraph.isEmpty) continue;
      normalized.add(paragraph);
      paragraphs.add(
        NovelChapterParagraph(
          text: paragraph,
          start: cursor,
          end: cursor + paragraph.length,
        ),
      );
      cursor += paragraph.length + separator.length;
    }
    return NovelChapterContent(
      chapterIndex: chapterIndex,
      text: text,
      normalizedText: normalized.join(separator),
      paragraphs: paragraphs,
    );
  }

  List<NovelTtsChunk> buildTtsChunks() {
    final chunks = <NovelTtsChunk>[];
    for (final paragraph in paragraphs) {
      var cursor = 0;
      final end = paragraph.text.length;
      while (cursor < end) {
        var chunkEnd = min(cursor + 260, end);
        if (chunkEnd < end) {
          final window = paragraph.text.substring(cursor, chunkEnd);
          final punct = window.lastIndexOf(RegExp(r'[。！？；]'));
          if (punct > 100) chunkEnd = cursor + punct + 1;
        }
        if (chunkEnd <= cursor) chunkEnd = min(cursor + 1, end);
        chunks.add(
          NovelTtsChunk(
            text: paragraph.text.substring(cursor, chunkEnd),
            start: paragraph.start + cursor,
            end: paragraph.start + chunkEnd,
            chapterIndex: chapterIndex,
          ),
        );
        cursor = chunkEnd;
      }
    }
    return chunks;
  }
}
