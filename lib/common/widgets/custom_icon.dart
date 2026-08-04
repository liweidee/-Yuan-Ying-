import 'package:flutter/widgets.dart' show IconData;

abstract final class CustomIcons {
  static const _kFontFam = 'custom_icon';

  // 播放器需要的图标（保留）
  static const IconData dm_off = IconData(0xe802, fontFamily: _kFontFam);
  static const IconData dm_on = IconData(0xe803, fontFamily: _kFontFam);
  static const IconData dm_settings = IconData(0xe804, fontFamily: _kFontFam);
  static const IconData view_headline_rotate_90 = IconData(0xe823, fontFamily: _kFontFam);
  static const IconData open_in_full_rotate_45 = IconData(0xe80a, fontFamily: _kFontFam);
  static const IconData repeat_rounded_rotate_90 = IconData(0xe810, fontFamily: _kFontFam);

  // 以下已删除（B站专属，播放器不需要）：
  // ai_circle, coin, dyn, fav, flip_rotate_90, identifier_circle,
  // live_reserve, player_dm_tip_*, share*, shield*, shopping_bag_not_interested,
  // splitscreen_rotate_90, star_favorite_*, thumbs_*, topic_tag,
  // touch_app_rotate_270, watch_later
}