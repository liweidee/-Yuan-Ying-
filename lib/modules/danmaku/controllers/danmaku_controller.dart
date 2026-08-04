import 'package:get/get.dart';
import 'package:yuanying/modules/danmaku/models/danmaku_model.dart';

class DanmakuController extends GetxController {
  final Map<int, List<DanmakuItem>> _danmakuMap = {};
  final RxInt totalCount = 0.obs;
  final RxBool isLoading = false.obs;

  /// 配置版本号，每次保存设置时递增，用于通知 DanmakuView 更新选项
  final RxInt configVersion = 0.obs;

  void loadDanmaku(List<DanmakuItem> items) {
    print('DanmakuController.loadDanmaku: 接收 ${items.length} 条弹幕');
    _danmakuMap.clear();
    for (final item in items) {
      final key = item.progress;
      if (!_danmakuMap.containsKey(key)) {
        _danmakuMap[key] = [];
      }
      _danmakuMap[key]!.add(item);
    }
    totalCount.value = items.length;
    print('DanmakuController: 加载完成，共 ${totalCount.value} 条');
  }

  List<DanmakuItem>? getAt(int progress) {
    if (_danmakuMap.containsKey(progress)) {
      return _danmakuMap[progress];
    }
    final keys = _danmakuMap.keys.toList()..sort();
    for (final key in keys) {
      if ((key - progress).abs() <= 50) {
        return _danmakuMap[key];
      }
      if (key > progress + 50) break;
    }
    return null;
  }

  void clear() {
    _danmakuMap.clear();
    totalCount.value = 0;
  }

  int get count => totalCount.value;
}