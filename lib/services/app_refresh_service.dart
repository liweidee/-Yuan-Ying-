import 'package:flutter/material.dart';

class AppRefreshService {
  final VoidCallback refresh;
  AppRefreshService(this.refresh);

  void call() => refresh();
}