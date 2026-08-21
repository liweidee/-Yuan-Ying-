import 'package:flutter/material.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';

SpringDescription _customSpringDescription() {
  final List<double> springDescription = SettingPref.springDescription;
  return SpringDescription(
    mass: springDescription[0],
    stiffness: springDescription[1],
    damping: springDescription[2],
  );
}

const clampingScrollPhysics = CustomTabBarViewScrollPhysics(
  parent: ClampingScrollPhysics(),
);

class CustomTabBarViewScrollPhysics extends ScrollPhysics {
  const CustomTabBarViewScrollPhysics({super.parent});

  @override
  CustomTabBarViewScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CustomTabBarViewScrollPhysics(parent: buildParent(ancestor));
  }

  static final _springDescription = _customSpringDescription();

  @override
  SpringDescription get spring => _springDescription;
}