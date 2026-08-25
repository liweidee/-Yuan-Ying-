// lib/modules/live/widgets/full_screen_live_player.dart
import 'package:flutter/material.dart';
import 'package:yuanying/modules/live/widgets/live_player_view.dart';

class FullScreenLivePlayer extends StatelessWidget {
  final VoidCallback onExit;

  const FullScreenLivePlayer({super.key, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            const LivePlayerView(showFullscreenBtn: true, isFullScreen: true),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 28),
                onPressed: onExit,
                tooltip: '退出全屏',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}