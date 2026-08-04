import 'package:flutter/material.dart';
import 'package:yuanying/models/common/enum_with_label.dart';

/// 文件排序类型
enum FileSortType implements EnumWithLabel {
  name('名称'),
  size('大小'),
  modified('修改时间');

  const FileSortType(this.label);

  @override
  final String label;
}

/// 排序顺序
enum SortOrder implements EnumWithLabel {
  ascending('正序'),
  descending('倒序');

  const SortOrder(this.label);

  @override
  final String label;
}

/// 视图模式
enum ViewMode {
  list('列表', Icons.view_list),
  grid('卡片', Icons.grid_view);

  const ViewMode(this.label, this.icon);

  final String label;
  final IconData icon;
}