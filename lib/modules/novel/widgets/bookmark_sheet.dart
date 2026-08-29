// lib/modules/novel/widgets/bookmark_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 书签数据
class NovelBookmark {
  final int chapter;
  final String chapterTitle;
  final double offset; // 0~1 滚动比例
  final int createdAt;

  NovelBookmark({
    required this.chapter,
    required this.chapterTitle,
    required this.offset,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'chapter': chapter,
    'chapterTitle': chapterTitle,
    'offset': offset,
    'createdAt': createdAt,
  };

  factory NovelBookmark.fromMap(Map<String, dynamic> map) => NovelBookmark(
    chapter: map['chapter'] as int? ?? 0,
    chapterTitle: map['chapterTitle']?.toString() ?? '',
    offset: (map['offset'] as num?)?.toDouble() ?? 0,
    createdAt: map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
  );

  String get timeLabel {
    final t = DateTime.fromMillisecondsSinceEpoch(createdAt);
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// 显示书签列表弹窗
Future<void> showBookmarkSheet(
  BuildContext context, {
  required List<NovelBookmark> bookmarks,
  required int currentChapter,
  required void Function(int chapter, double offset) onJump,
  required Future<void> Function(NovelBookmark) onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.65,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Row(
                    children: [
                      Text(
                        '书签',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '共 ${bookmarks.length} 条',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: bookmarks.isEmpty
                      ? Center(
                          child: Text(
                            '还没有书签',
                            style: TextStyle(
                              color: Theme.of(ctx).colorScheme.outline,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: bookmarks.length,
                          itemBuilder: (context, i) {
                            final b = bookmarks[i];
                            final isCurrent = b.chapter == currentChapter;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.bookmark,
                                size: 18,
                                color: isCurrent
                                    ? Theme.of(ctx).colorScheme.primary
                                    : Theme.of(ctx).colorScheme.outline,
                              ),
                              title: Text(
                                b.chapterTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: isCurrent
                                      ? Theme.of(ctx).colorScheme.primary
                                      : Theme.of(ctx).colorScheme.onSurface,
                                ),
                              ),
                              subtitle: Text(
                                '第 ${b.chapter + 1} 章 · ${b.timeLabel}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Theme.of(ctx).colorScheme.outline,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () async {
                                  await onDelete(b);
                                  setSheet(() {}); // 刷新列表
                                },
                              ),
                              onTap: () {
                                // 先关闭弹窗，再跳转
                                Navigator.pop(ctx);
                                onJump(b.chapter, b.offset);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}