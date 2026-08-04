import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/common/types/image_type.dart';
import 'package:yuanying/common/extensions/num_ext.dart';
import 'package:yuanying/utils/image_utils.dart';

class NetworkImgLayer extends StatelessWidget {
  const NetworkImgLayer({
    super.key,
    required this.src,
    required this.width,
    required this.height,
    this.type = ImageType.def,
    this.fadeOutDuration = const Duration(milliseconds: 120),
    this.fadeInDuration = const Duration(milliseconds: 120),
    this.quality = 80,
    this.borderRadius = Style.mdRadius,
    this.getPlaceHolder,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth,
  });

  final String? src;
  final double width;
  final double height;
  final ImageType type;
  final Duration fadeOutDuration;
  final Duration fadeInDuration;
  final int quality;
  final BorderRadius borderRadius;
  final Widget Function()? getPlaceHolder;
  final BoxFit fit;
  final Alignment alignment;
  final bool? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final isEmote = type == ImageType.emote;
    final isAvatar = type == ImageType.avatar;

    if (src?.isNotEmpty == true) {
      final child = _buildImage(context);
      if (isEmote) return child;
      if (isAvatar) return ClipOval(child: child);
      return ClipRRect(borderRadius: borderRadius, child: child);
    }
    return getPlaceHolder?.call() ?? _placeholder(context);
  }

  Widget _buildImage(BuildContext context) {
    int? memCacheWidth, memCacheHeight;
    if (cacheWidth ?? width <= height) {
      memCacheWidth = width.cacheSize(context);
    } else {
      memCacheHeight = height.cacheSize(context);
    }

    // ===== 针对豆瓣图片添加请求头 =====
    Map<String, String>? headers;
    final imageUrl = ImageUtils.thumbnailUrl(src, quality);
    if (src != null && src!.contains('doubanio.com')) {
      headers = {
        'Referer': 'https://movie.douban.com/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36',
        // 注意：不要设置 Host 头，让网络库自动从 URL 中提取
      };
      // 可选：打印日志以便调试
      // print('豆瓣图片请求头: $headers, URL: $imageUrl');
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fit: fit,
      alignment: alignment,
      fadeOutDuration: fadeOutDuration,
      fadeInDuration: fadeInDuration,
      filterQuality: FilterQuality.low,
      httpHeaders: headers, // 只有豆瓣图片才有头，其他为 null
      placeholder: (_, __) => getPlaceHolder?.call() ?? _placeholder(context),
      errorWidget: (_, __, ___) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: type == ImageType.avatar ? null : borderRadius,
        shape: type == ImageType.avatar ? BoxShape.circle : BoxShape.rectangle,
      ),
      child: Center(
        child: Icon(
          Icons.image,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}