import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BackDetector extends StatelessWidget {
  const BackDetector({
    super.key,
    required this.onBack,
    required this.child,
  });

  final Widget child;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onKeyEvent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        child: child,
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      onBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons == kBackMouseButton) {
      onBack();
    }
  }
}