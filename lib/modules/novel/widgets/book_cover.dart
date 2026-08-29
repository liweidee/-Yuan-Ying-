import 'package:flutter/material.dart';

const List<List<Color>> _coverGradients = [
  [Color(0xFF2A3346), Color(0xFF151B26)],
  [Color(0xFF3A2E46), Color(0xFF191322)],
  [Color(0xFF23403A), Color(0xFF101D1A)],
  [Color(0xFF463A2A), Color(0xFF201812)],
  [Color(0xFF462A30), Color(0xFF1F1214)],
  [Color(0xFF2A4146), Color(0xFF121D20)],
];

class NovelBookCover extends StatelessWidget {
  final String? coverUrl;
  final String title;
  final String? author;
  final double radius;

  const NovelBookCover({
    super.key,
    this.coverUrl,
    required this.title,
    this.author,
    this.radius = 8,
  });

  int get _hash {
    int h = 7;
    for (final c in title.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  Widget _fallback(BuildContext context) {
    final g = _coverGradients[_hash % _coverGradients.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: g,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE8E4DA),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          if (author != null && author!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFE8E4DA).withValues(alpha: 0.55),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _clip(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (coverUrl != null && coverUrl!.isNotEmpty) {
      content = Image.network(
        coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    } else {
      content = _fallback(context);
    }
    return _clip(
      DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A212C),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: content,
      ),
    );
  }
}