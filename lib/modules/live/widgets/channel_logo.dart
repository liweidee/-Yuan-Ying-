// lib/modules/live/widgets/channel_logo.dart

import 'package:flutter/material.dart';

/// 频道 Logo 显示组件
///
/// 设计要点：
///   - 强制正方形外框，所有 logo 统一在 size × size 区域内等比缩放，不变形
///   - 图片用 BoxFit.contain，配合内边距，避免贴边
///   - 背景用 onSurface 半透明，浅色模式深灰底、深色模式浅灰底，
///     保证央视等白色 logo 在浅色模式下也能看清
///   - 加载中显示占位块，加载失败降级为电视图标
class ChannelLogo extends StatelessWidget {
  final String? url;
  final double size;

  const ChannelLogo({
    super.key,
    required this.url,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          // 背景：浅色模式深灰底，深色模式浅灰底，衬托白色 logo
          color: colorScheme.onSurface.withOpacity(0.08),
          padding: EdgeInsets.all(size * 0.12), // 内边距，避免 logo 贴边
          child: _buildContent(context, colorScheme),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    if (url == null || url!.isEmpty) {
      return _buildFallback(colorScheme);
    }

    // 按设备像素比计算解码尺寸，避免非等比解码
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeSize = (size * dpr).toInt();

    return Image.network(
      url!,
      fit: BoxFit.contain,
      // 强制图片在容器内居中
      alignment: Alignment.center,
      // 按正方形解码，保持宽高比
      cacheWidth: decodeSize,
      cacheHeight: decodeSize,
      // 关键：让图片在正方形内等比缩放，不撑破容器
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _buildPlaceholder(colorScheme);
      },
      errorBuilder: (context, error, stack) {
        return _buildFallback(colorScheme);
      },
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    // 加载中：显示一个淡淡的圆角块
    return Center(
      child: SizedBox(
        width: size * 0.3,
        height: size * 0.3,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.primary.withOpacity(0.4),
        ),
      ),
    );
  }

  Widget _buildFallback(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.live_tv,
        size: size * 0.45,
        color: colorScheme.onSurface.withOpacity(0.4),
      ),
    );
  }
}