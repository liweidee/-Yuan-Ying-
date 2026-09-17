import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

typedef AlistDirectorPasswordCallback = void Function(String pwd, bool remember);

class AlistDirectorPasswordDialog extends StatefulWidget {
  final FocusNode focusNode;
  final AlistDirectorPasswordCallback directorPasswordCallback;

  const AlistDirectorPasswordDialog({
    super.key,
    required this.focusNode,
    required this.directorPasswordCallback,
  });

  @override
  State<AlistDirectorPasswordDialog> createState() =>
      _AlistDirectorPasswordDialogState();
}

class _AlistDirectorPasswordDialogState
    extends State<AlistDirectorPasswordDialog> {
  final _controller = TextEditingController();
  var _remember = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('请输入目录密码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            obscureText: true,
            focusNode: widget.focusNode,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isCollapsed: true,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 12),
            ),
          ),
          Row(
            children: [
              Checkbox(
                value: _remember,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => setState(() => _remember = v ?? false),
              ),
              GestureDetector(
                onTap: () => setState(() => _remember = !_remember),
                child: const Text('记住密码？'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => SmartDialog.dismiss(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final pwd = _controller.text;
            if (pwd.isEmpty) {
              SmartDialog.showToast('密码不能为空');
              return;
            }
            widget.directorPasswordCallback(pwd, _remember);
            SmartDialog.dismiss();
          },
          child: const Text('确认'),
        ),
      ],
    );
  }
}