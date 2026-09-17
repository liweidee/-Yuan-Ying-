import 'package:flutter/material.dart';

class AlistLoadingStatusWidget extends StatelessWidget {
  final bool loading;
  final String? errorMsg;
  final Widget child;
  final VoidCallback retryCallback;

  const AlistLoadingStatusWidget({
    super.key,
    required this.loading,
    this.errorMsg,
    required this.child,
    required this.retryCallback,
  });

  @override
  Widget build(BuildContext context) {
    if (errorMsg != null && errorMsg!.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              child: Text(errorMsg!, textAlign: TextAlign.center),
            ),
            FilledButton(onPressed: retryCallback, child: const Text('重试')),
          ],
        ),
      );
    }
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return child;
  }
}