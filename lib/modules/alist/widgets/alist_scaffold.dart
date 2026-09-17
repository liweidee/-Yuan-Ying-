import 'package:flutter/material.dart';

class AlistScaffold extends StatelessWidget {
  final Widget? appbarTitle;
  final Widget body;
  final GestureTapCallback? onLeadingDoubleTap;
  final List<Widget>? appbarActions;
  final bool showAppbar;
  final Widget? leading;
  final bool resizeToAvoidBottomInset;

  const AlistScaffold({
    super.key,
    this.appbarTitle,
    required this.body,
    this.onLeadingDoubleTap,
    this.appbarActions,
    this.showAppbar = true,
    this.leading,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final parentRoute = ModalRoute.of(context);
    final canPop = parentRoute != null && parentRoute.canPop;

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: colorScheme.surface,
      appBar: !showAppbar
          ? null
          : AppBar(
              leading: leading ??
                  (canPop
                      ? GestureDetector(
                          onDoubleTap: onLeadingDoubleTap,
                          child: const BackButton(),
                        )
                      : null),
              automaticallyImplyLeading: false,
              backgroundColor: colorScheme.surface,
              foregroundColor: colorScheme.onSurface,
              elevation: 0,
              title: appbarTitle,
              actions: appbarActions,
            ),
      body: SafeArea(child: body),
    );
  }
}