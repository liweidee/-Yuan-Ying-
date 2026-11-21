import 'package:yuanying/modules/novel/models/novel_chapter_content.dart';

class NovelTtsReadingSession {
  int? readingChapter;
  NovelChapterContent? content;
  int readingOffset = 0;
  bool manualTakeover = false;

  void begin({
    required int chapterIndex,
    required NovelChapterContent chapterContent,
    required int offset,
  }) {
    readingChapter = chapterIndex;
    content = chapterContent;
    readingOffset = offset;
    manualTakeover = false;
  }

  void updateChunk(NovelTtsChunk chunk) {
    if (readingChapter != chunk.chapterIndex) return;
    readingOffset = chunk.start;
  }

  void takeOver() {
    manualTakeover = true;
  }

  void resumeFollow() {
    manualTakeover = false;
  }

  void advance(NovelChapterContent nextContent) {
    readingChapter = nextContent.chapterIndex;
    content = nextContent;
    readingOffset = 0;
  }

  void clear() {
    readingChapter = null;
    content = null;
    readingOffset = 0;
    manualTakeover = false;
  }
}
