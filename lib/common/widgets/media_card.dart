import 'package:flutter/material.dart';
import 'package:yuanying/common/widgets/image/network_img_layer.dart';
import 'package:yuanying/common/types/image_type.dart';
import 'package:yuanying/t4/models/video_item.dart';

class MediaCard extends StatelessWidget {
  final VideoItem videoItem;
  final VoidCallback? onTap;
  final bool showSourceLabel;
  final String? sourceLabel;
  final bool showProgress;
  final String? progressText;
  final bool showDeleteButton;
  final VoidCallback? onDelete;
  final String? bottomSubText;
  final Color? bottomSubColor;
  final String? timeAgo;

  const MediaCard({
    super.key,
    required this.videoItem,
    this.onTap,
    this.showSourceLabel = false,
    this.sourceLabel,
    this.showProgress = false,
    this.progressText,
    this.showDeleteButton = false,
    this.onDelete,
    this.bottomSubText,
    this.bottomSubColor,
    this.timeAgo,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          // 封面卡片
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.75,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return NetworkImgLayer(
                          src: videoItem.vodPic,
                          width: constraints.maxWidth > 0 ? constraints.maxWidth : 100,
                          height: constraints.maxHeight > 0 ? constraints.maxHeight : 100,
                          type: ImageType.cover,
                        );
                      },
                    ),
                    // 来源标签
                    if (showSourceLabel && sourceLabel != null && sourceLabel!.isNotEmpty)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            sourceLabel!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    // 删除按钮
                    if (showDeleteButton)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: onDelete,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    // 进度 + 时间
                    Positioned(
                      bottom: 6,
                      left: 6,
                      right: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showProgress && progressText != null && progressText!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                progressText!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(height: 2),
                          if (timeAgo != null && timeAgo!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                timeAgo!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ===== 底部文字：固定高度 40，防止溢出 =====
          SizedBox(
            height: 40,  // 从 36 改为 40
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    videoItem.vodName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (bottomSubText != null && bottomSubText!.isNotEmpty)
                    Text(
                      bottomSubText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: bottomSubColor ?? colorScheme.primary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}