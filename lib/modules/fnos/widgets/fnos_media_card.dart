import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/fnos_media_item.dart';

/// 飞牛条目卡片（海报 + 标题 + 集数徽标 + 进度条）
///
/// 与 Emby 的 VideoCardV 区别：飞牛图片需要 Authx + Authorization，
/// 必须通过 httpHeaders 传给 CachedNetworkImage。
class FnosMediaCard extends StatelessWidget {
  final FnosPlayListItem item;
  final String imageUrl;
  final Map<String, String> headers;
  final VoidCallback onTap;
  final bool showTitle;

  const FnosMediaCard({
    super.key,
    required this.item,
    required this.imageUrl,
    required this.headers,
    required this.onTap,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final displayName =
        (item.tvTitle?.isNotEmpty == true) ? item.tvTitle! : (item.title ?? '');

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== 海报 =====
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      httpHeaders: headers,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      placeholder: (_, __) =>
                          Container(color: colorScheme.surfaceVariant),
                      errorWidget: (_, __, ___) => _posterFallback(colorScheme),
                    )
                  else
                    _posterFallback(colorScheme),

                  // 集数徽标
                  if (item.isEpisode && item.episodeNumber > 0)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '第${item.episodeNumber}集',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  // 类型徽标
                  if (item.isFolder || item.isTv)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          item.isFolder
                              ? Icons.folder_rounded
                              : Icons.tv_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),

                  // 观看进度条
                  if (item.duration > 0 && item.ts > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: (item.ts / item.duration).clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: Colors.black45,
                        valueColor:
                            AlwaysStoppedAnimation(colorScheme.primary),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ===== 标题 =====
          if (showTitle) ...[
            const SizedBox(height: 6),
            Text(
              displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _posterFallback(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(
        item.isFolder ? Icons.folder : Icons.movie_outlined,
        color: colorScheme.outline,
        size: 28,
      ),
    );
  }
}