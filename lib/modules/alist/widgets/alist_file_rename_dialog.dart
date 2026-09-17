import 'package:flutter/material.dart';

class AlistFileRenameDialog extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const AlistFileRenameDialog({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onConfirm,
    this.onCancel,
  });

  @override
  State<AlistFileRenameDialog> createState() => _AlistFileRenameDialogState();
}

class _AlistFileRenameDialogState extends State<AlistFileRenameDialog> {
  var _hasContent = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      final hasContent = widget.controller.text.trim().isNotEmpty;
      if (_hasContent != hasContent) {
        setState(() => _hasContent = hasContent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        focusNode: widget.focusNode,
        autofocus: true,
        controller: widget.controller,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: '输入新的文件名',
          isCollapsed: true,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 12),
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('取消')),
        TextButton(
          onPressed: _hasContent ? widget.onConfirm : null,
          child: const Text('确认'),
        ),
      ],
    );
  }
}