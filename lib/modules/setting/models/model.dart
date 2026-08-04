import 'package:flutter/material.dart';
import 'package:yuanying/modules/setting/widgets/normal_item.dart';
import 'package:yuanying/modules/setting/widgets/switch_item.dart';

@immutable
sealed class SettingsModel {
  final String? subtitle;
  final Widget? leading;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;

  String? get title;
  Widget get widget;
  String get effectiveTitle;
  String? get effectiveSubtitle;

  const SettingsModel({
    this.subtitle,
    this.leading,
    this.contentPadding,
    this.titleStyle,
  });
}

class SplitModel extends SettingsModel {
  const SplitModel({
    super.contentPadding,
    super.titleStyle,
    required this.normalModel,
    required this.switchModel,
  });

  @override
  String? get effectiveSubtitle => normalModel.effectiveSubtitle;
  @override
  String get effectiveTitle => normalModel.effectiveTitle;
  @override
  String? get title => normalModel.title;

  final NormalModel normalModel;
  final SwitchModel switchModel;

  @override
  Widget get widget => SetSwitchItem(
    title: effectiveTitle,
    subtitle: effectiveSubtitle,
    setKey: switchModel.setKey,
    defaultVal: switchModel.defaultVal,
    onChanged: switchModel.onChanged,
    needReboot: switchModel.needReboot,
    leading: normalModel.leading,
    onTap: switchModel.onTap,
    contentPadding: contentPadding,
    titleStyle: titleStyle,
    isSplit: true,
  );
}

class NormalModel extends SettingsModel {
  @override
  final String? title;
  final ValueGetter<String>? getTitle;
  final ValueGetter<String>? getSubtitle;
  final Widget Function(ThemeData theme)? getTrailing;
  final void Function(BuildContext context, VoidCallback setState)? onTap;

  const NormalModel({
    super.subtitle,
    super.leading,
    super.contentPadding,
    super.titleStyle,
    this.title,
    this.getTitle,
    this.getSubtitle,
    this.getTrailing,
    this.onTap,
  }) : assert(title != null || getTitle != null);

  const NormalModel.split({
    super.subtitle,
    super.leading,
    super.contentPadding,
    super.titleStyle,
    this.title,
    this.getTitle,
    this.getSubtitle,
    this.getTrailing,
  }) : onTap = null,
       assert(title != null || getTitle != null);

  @override
  String get effectiveTitle => title ?? getTitle!();
  @override
  String? get effectiveSubtitle => subtitle ?? getSubtitle?.call();

  @override
  Widget get widget => NormalItem(
    title: title,
    getTitle: getTitle,
    subtitle: subtitle,
    getSubtitle: getSubtitle,
    leading: leading,
    getTrailing: getTrailing,
    onTap: onTap,
    contentPadding: contentPadding,
    titleStyle: titleStyle,
  );
}

class SwitchModel extends SettingsModel {
  @override
  final String? title;
  final String setKey;
  final bool defaultVal;
  final ValueChanged<bool>? onChanged;
  final bool needReboot;
  final void Function(BuildContext context)? onTap;

  const SwitchModel({
    super.subtitle,
    super.leading,
    super.contentPadding,
    super.titleStyle,
    required String this.title,
    required this.setKey,
    this.defaultVal = false,
    this.onChanged,
    this.needReboot = false,
    this.onTap,
  });

  const SwitchModel.split({
    required this.setKey,
    this.defaultVal = false,
    this.needReboot = false,
    this.onChanged,
    this.onTap,
  }) : title = null;

  @override
  String get effectiveTitle => title!;
  @override
  String? get effectiveSubtitle => subtitle;

  @override
  Widget get widget => SetSwitchItem(
    title: title!,
    subtitle: subtitle,
    setKey: setKey,
    defaultVal: defaultVal,
    onChanged: onChanged,
    needReboot: needReboot,
    leading: leading,
    onTap: onTap,
    contentPadding: contentPadding,
    titleStyle: titleStyle,
  );
}