import 'package:hive_ce/hive.dart';

class GlobalData {
  static final GlobalData _instance = GlobalData._internal();
  factory GlobalData() => _instance;
  GlobalData._internal();

  int imgQuality = 10;
  
  Box? get userInfo => Hive.box('userInfo');
  
  // B站相关的都删除或注释掉
  // Set<int> blackMids = {};
}