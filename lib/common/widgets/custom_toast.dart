import 'package:flutter/material.dart';
import 'package:yuanying/utils/storage_manager.dart';

class CustomToast extends StatelessWidget {
  const CustomToast(this.msg, {super.key});

  final String msg;

  static double toastOpacity =
      StorageManager.getSetting<double>('toastOpacity') ?? 0.85;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 30,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(toastOpacity),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      child: Text(
        msg,
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget(this.msg, {super.key});

  final String msg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      decoration: BoxDecoration(
        color: theme.dialogTheme.backgroundColor,
        borderRadius: const BorderRadius.all(Radius.circular(15)),
      ),
      child: Column(
        spacing: 20,
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation(onSurfaceVariant),
          ),
          Text(msg, style: TextStyle(color: onSurfaceVariant)),
        ],
      ),
    );
  }
}

class NotifyWarning extends StatelessWidget {
  const NotifyWarning(this.msg, {super.key});

  final String msg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        color: theme.dialogTheme.backgroundColor,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        spacing: 5,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 22,
            color: onSurfaceVariant,
          ),
          Text(msg, style: TextStyle(color: onSurfaceVariant)),
        ],
      ),
    );
  }
}