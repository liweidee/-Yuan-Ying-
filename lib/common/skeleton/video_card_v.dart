import 'package:flutter/material.dart';
import 'package:yuanying/common/skeleton/skeleton.dart';
import 'package:yuanying/core/theme/style.dart';

class VideoCardVSkeleton extends StatelessWidget {
  const VideoCardVSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Skeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: Style.aspectRatio,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: Style.mdRadius,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 5, 6, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 200,
                  height: 13,
                  margin: const EdgeInsets.only(bottom: 5),
                  color: color,
                ),
                Container(
                  width: 150,
                  height: 13,
                  margin: const EdgeInsets.only(bottom: 12),
                  color: color,
                ),
                Container(
                  width: 110,
                  height: 13,
                  margin: const EdgeInsets.only(bottom: 5),
                  color: color,
                ),
                Container(
                  width: 75,
                  height: 13,
                  color: color,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}