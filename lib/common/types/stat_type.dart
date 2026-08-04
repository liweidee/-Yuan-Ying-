import 'package:flutter/material.dart';

enum StatType {
  play(Icons.play_arrow, '播放'),
  danmaku(Icons.chat_bubble_outline, '弹幕'),
  like(Icons.thumb_up_alt_outlined, '点赞'),
  coin(Icons.monetization_on_outlined, '硬币'),
  share(Icons.share_outlined, '分享'),
  favorite(Icons.star_outline, '收藏');

  const StatType(this.iconData, this.label);
  final IconData iconData;
  final String label;
}