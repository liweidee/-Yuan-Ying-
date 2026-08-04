import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

class SetSwitchItem extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String setKey;
  final bool defaultVal;
  final ValueChanged<bool>? onChanged;
  final bool needReboot;
  final Widget? leading;
  final void Function(BuildContext context)? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;
  final bool isSplit;

  const SetSwitchItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.setKey,
    this.defaultVal = false,
    this.onChanged,
    this.needReboot = false,
    this.leading,
    this.onTap,
    this.contentPadding,
    this.titleStyle,
    this.isSplit = false,
  });

  @override
  State<SetSwitchItem> createState() => _SetSwitchItemState();
}

class _SetSwitchItemState extends State<SetSwitchItem> {
  late bool val;

  void setVal() {
    if (widget.setKey == SettingBoxKey.appFontWeight) {
      // appFontWeight: -1 表示关闭，非-1表示开启
      final value = StorageManager.getSetting<int>(widget.setKey) ?? -1;
      val = value != -1;
    } else {
      val = StorageManager.getSetting<bool>(widget.setKey) ?? widget.defaultVal;
    }
  }

  @override
  void initState() {
    super.initState();
    setVal();
  }

  @override
  void didUpdateWidget(SetSwitchItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setKey != widget.setKey) {
      setVal();
    }
  }

  Future<void> switchChange([bool? value]) async {
    val = value ?? !val;

    if (widget.setKey == SettingBoxKey.appFontWeight) {
      // appFontWeight: 开启时存储4（中等粗细），关闭时存储-1
      await StorageManager.setSetting(widget.setKey, val ? 4 : -1);
    } else {
      await StorageManager.setSetting(widget.setKey, val);
    }

    widget.onChanged?.call(val);
    if (widget.needReboot) {
      SmartDialog.showToast('重启生效');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle =
        widget.titleStyle ??
        theme.textTheme.titleMedium?.copyWith(
          color: widget.onTap != null && !val
              ? theme.colorScheme.outline
              : null,
        );
    final subTitleStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.outline,
    );

    final switchBtn = Transform.scale(
      scale: 0.8,
      alignment: Alignment.centerRight,
      child: Switch(
        value: val,
        onChanged: switchChange,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    Widget child(Widget? trailing) => ListTile(
      contentPadding: widget.contentPadding,
      enabled: widget.onTap == null ? true : val,
      onTap: widget.onTap == null ? switchChange : () => widget.onTap!(context),
      title: Text(widget.title, style: titleStyle),
      subtitle: widget.subtitle != null
          ? Text(widget.subtitle!, style: subTitleStyle)
          : null,
      leading: widget.leading,
      trailing: trailing,
    );

    if (widget.isSplit) {
      return Row(
        children: [
          Expanded(child: child(null)),
          SizedBox(
            height: 25,
            child: VerticalDivider(
              width: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 24),
            child: switchBtn,
          ),
        ],
      );
    }

    return child(switchBtn);
  }
}