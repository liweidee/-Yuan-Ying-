import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver;
import 'package:yuanying/utils/platform_utils.dart';

void addObserverMobile(WidgetsBindingObserver observer) {
  if (PlatformUtils.isMobile) {
    WidgetsBinding.instance.addObserver(observer);
  }
}

void removeObserverMobile(WidgetsBindingObserver observer) {
  if (PlatformUtils.isMobile) {
    WidgetsBinding.instance.removeObserver(observer);
  }
}