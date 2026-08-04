import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<bool> showConfirmDialog({
  required BuildContext context,
  required Widget title,
  Widget? content,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: title,
          content: content,
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '取消',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
}