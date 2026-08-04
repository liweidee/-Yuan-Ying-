import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

final routeObserver = RouteObserver<GetPageRoute>();

mixin RouteAwareMixin<T extends StatefulWidget> on State<T>, RouteAware {
  @override
  void initState() {
    super.initState();
    routeObserver.subscribe(this, Get.routing.route as GetPageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }
}