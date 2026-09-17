import 'package:flutter/material.dart';

class AlistMkdirDialog extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const AlistMkdirDialog({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onConfirm,
    this.onCancel,
  });

  @override
  State<AlistMkdirDialog> createState() => _AlistMkdirDialogState();
}

class _AlistMkdirDialogState extends State<AlistMkdirDialog> {
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
      title: const Text('新建文件夹'),
      content: TextField(
        focusNode: widget.focusNode,
        autofocus: true,
        controller: widget.controller,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: '新文件夹名称',
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