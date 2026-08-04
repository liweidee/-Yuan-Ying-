import 'package:flutter/services.dart' show HapticFeedback;
import 'package:yuanying/plugin/pl_player/player_pref.dart';

bool enableFeedback = PlayerPref.feedBackEnable;

void feedBack() {
  if (enableFeedback) {
    HapticFeedback.lightImpact();
  }
}