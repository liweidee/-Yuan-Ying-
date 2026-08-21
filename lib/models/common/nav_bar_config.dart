import 'package:flutter/material.dart';
import 'package:yuanying/models/common/enum_with_label.dart';
import 'package:yuanying/modules/home/views/home_page.dart';
import 'package:yuanying/modules/local_file/views/local_file_page.dart';
import 'package:yuanying/modules/setting/views/setting_page.dart';

/// 导航栏类型枚举
enum NavigationBarType implements EnumWithLabel {
  home(
    '首页',
    Icon(Icons.home_outlined, size: 24),
    Icon(Icons.home, size: 24),
    HomePage(),
  ),
  localFile(
    '文件',
    Icon(Icons.folder_outlined, size: 24),
    Icon(Icons.folder, size: 24),
    LocalFilePage(),
  ),
  setting(
    '设置',
    Icon(Icons.settings_outlined, size: 24),
    Icon(Icons.settings, size: 24),
    SettingPage(),
  ),
  ;

  @override
  final String label;
  final Icon icon;
  final Icon selectIcon;
  final Widget page;

  const NavigationBarType(this.label, this.icon, this.selectIcon, this.page);
}

/// 导航栏样式（移动端）
enum NavigationBarStyle implements EnumWithLabel {
  /// 1. 默认风格：BottomNavigationBar 经典风格
  default_('默认风格'),

  /// 2. 默认（紧凑）：完全复刻 PiliPlus 关闭 MD3 底栏样式
  defaultCompact('默认（紧凑）'),

  /// 3. 胶囊高亮：Material3 NavigationBar 胶囊指示器
  capsule('胶囊高亮'),

  /// 4. 悬浮底栏：悬浮圆角卡片
  floating('悬浮底栏');

  const NavigationBarStyle(this.label);

  @override
  final String label;
}