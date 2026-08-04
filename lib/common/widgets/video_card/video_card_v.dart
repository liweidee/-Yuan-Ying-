import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/badge.dart';
import 'package:yuanying/common/widgets/image/network_img_layer.dart';
import 'package:yuanying/common/types/badge_type.dart';
import 'package:yuanying/common/types/image_type.dart';
import 'package:yuanying/t4/models/video_item.dart';

class VideoCardV extends StatelessWidget {
  final VideoItem videoItem;
  final VoidCallback? onTap;  // 点击回调

  const VideoCardV({
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Card(
            clipBehavior: Clip.hardEdge,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: AspectRatio(
              aspectRatio: 0.75,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth;
                  final maxHeight = constraints.maxHeight;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      NetworkImgLayer(
                        src: videoItem.vodPic,
                        width: maxWidth.isFinite && maxWidth > 0 ? maxWidth : 100.0,
                        height: maxHeight.isFinite && maxHeight > 0 ? maxHeight : 100.0,
                        type: ImageType.cover,
                      ),
                      // 文件夹标识（右下角圆角正方形文件夹图标）
                      if (isFolder)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.folder_outlined,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      // 右下角角标
                      if (!isFolder && videoItem.vodRemarks != null && videoItem.vodRemarks!.isNotEmpty)
                        PBadge(
                          text: videoItem.vodRemarks!,
                          bottom: 6,
                          right: 7,
                          size: BadgeSize.small,
                          type: BadgeType.gray,
                          maxWidth: 100,   // 限制最大宽度 100 dp，超出显示省略号
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(
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
          ),
        ],
      ),
    );
  }
}