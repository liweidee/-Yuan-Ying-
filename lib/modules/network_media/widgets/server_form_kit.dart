import 'package:flutter/material.dart';

/// 网络源服务器弹窗和表单组件的共享包。
///
/// 视觉与 DreamPlayer 完全一致：圆角 16 的 AlertDialog、
/// 图标徽章标题、圆角 12 的图标前缀字段、淡色结果横幅、
/// 密码可见切换。颜色全部走 [Theme.of(context).colorScheme]，
/// 明暗主题自动适配。

AlertDialog serverDialog({
  required Widget title,
  required Widget content,
  required List<Widget> actions,
}) {
  return AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
    contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
    actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    actionsAlignment: MainAxisAlignment.spaceBetween,
    title: title,
    content: content,
    actions: actions,
  );
}

/// 图标徽章 + 标题（+ 可选副标题）
class ServerDialogTitle extends StatelessWidget {
  const ServerDialogTitle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 22, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 圆角 12、图标前缀、filled 的字段样式
InputDecoration serverFieldDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  required IconData icon,
  bool optional = false,
  Widget? suffix,
}) {
  final theme = Theme.of(context);
  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color),
      );
  return InputDecoration(
    labelText: optional ? '$label (可选)' : label,
    hintText: hint,
    prefixIcon: Icon(icon, size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(theme.colorScheme.outline.withOpacity(0.4)),
    enabledBorder: border(theme.colorScheme.outline.withOpacity(0.4)),
    focusedBorder: border(theme.colorScheme.primary),
    labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
  );
}

/// 服务器表单文本字段（普通版）
class ServerTextField extends StatelessWidget {
  const ServerTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textInputAction,
    this.autofillHints,
    this.autocorrect = true,
    this.enableSuggestions = true,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool autocorrect;
  final bool enableSuggestions;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: decoration,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
    );
  }
}

/// 结果横幅：成功绿色，失败红色（明暗主题都适配）
class ServerResultBanner extends StatelessWidget {
  const ServerResultBanner({
    super.key,
    required this.success,
    required this.message,
    this.margin,
  });

  final bool success;
  final String message;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = success ? const Color(0xFF4CAF50) : theme.colorScheme.error;
    return Container(
      margin: margin ?? const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.check_circle : Icons.error_outline,
            size: 18,
            color: success ? const Color(0xFF66BB6A) : color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: success ? const Color(0xFF66BB6A) : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 带可见切换的密码字段
class ServerPasswordField extends StatefulWidget {
  const ServerPasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<ServerPasswordField> createState() => _ServerPasswordFieldState();
}

class _ServerPasswordFieldState extends State<ServerPasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return ServerTextField(
      controller: widget.controller,
      obscureText: !_visible,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction ?? TextInputAction.next,
      autofillHints: const [AutofillHints.password],
      decoration: serverFieldDecoration(
        context,
        label: widget.label,
        hint: widget.hint,
        icon: widget.icon,
        suffix: IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            _visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 20,
          ),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}