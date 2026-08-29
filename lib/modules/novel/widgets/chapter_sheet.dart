import 'package:flutter/material.dart';

Future<int?> showChapterSheet(
  BuildContext context, {
  required List<String> titles,
  required int current,
}) {
  bool reversed = false;
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final count = titles.length;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.62,
            minChildSize: 0.35,
            maxChildSize: 0.92,
            builder: (ctx, scrollController) {
              final colorScheme = Theme.of(ctx).colorScheme;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
                    child: Row(
                      children: [
                        Text(
                          '目录',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '共 $count 章 · 当前第 ${current + 1} 章',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              setSheet(() => reversed = !reversed),
                          child: Text(
                            reversed ? '正序' : '倒序',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: count,
                      itemBuilder: (context, i) {
                        final realIndex = reversed ? count - 1 - i : i;
                        final isCurrent = realIndex == current;
                        return ListTile(
                          dense: true,
                          title: Text(
                            titles[realIndex],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: isCurrent
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                          trailing: isCurrent
                              ? Icon(
                                  Icons.menu_book,
                                  size: 15,
                                  color: colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(ctx, realIndex),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}