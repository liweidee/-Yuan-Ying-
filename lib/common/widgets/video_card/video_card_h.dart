import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/image/network_img_layer.dart';
import 'package:yuanying/common/types/image_type.dart';
import 'package:yuanying/t4/models/video_item.dart';

/// 水平图文列表卡片（优化版：圆角背景、无边框、无箭头）
class VideoCardH extends StatelessWidget {
  final VideoItem videoItem;
  final VoidCallback? onTap;  // 点击回调

  const VideoCardH({
    super.key,
    required this.videoItem,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isFolder = videoItem.vodTag == 'folder';

    return GestureDetector(
      onTap: onTap,  // 使用外部回调
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面图（带文件夹标识）
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: NetworkImgLayer(
                      src: videoItem.vodPic,
                      width: 120,
                      height: 70,
                      type: ImageType.cover,
                    ),
                  ),
                  // 文件夹标识（右下角圆角正方形文件夹图标）
                  if (isFolder)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Icon(
                          Icons.folder_outlined,
                          size: 14,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // 文字信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      videoItem.vodName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (videoItem.vodRemarks != null && videoItem.vodRemarks!.isNotEmpty)
                      Text(
                        videoItem.vodRemarks!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}