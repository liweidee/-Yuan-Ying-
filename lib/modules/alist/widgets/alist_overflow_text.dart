import 'package:flutter/material.dart';

class AlistOverflowText extends StatelessWidget {
  static const ellipsis = "...";
  final String text;
  final TextStyle? style;

  const AlistOverflowText({super.key, required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var ts = DefaultTextStyle.of(context).style;
        if (style != null) ts = ts.merge(style);
        final maxWidth = constraints.biggest.width;
        final tp = TextPainter(
          text: TextSpan(text: text, style: ts),
          textDirection: TextDirection.ltr,
        )..layout();
        if (tp.width <= maxWidth) return Text(text, style: ts);
        return Text(text, style: ts, maxLines: 1, overflow: TextOverflow.ellipsis);
      },
    );
  }
}