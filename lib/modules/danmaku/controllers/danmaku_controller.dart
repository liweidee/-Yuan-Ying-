import 'package:get/get.dart';
import 'package:yuanying/modules/danmaku/models/danmaku_model.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

class DanmakuController extends GetxController {
  final Map<int, List<DanmakuItem>> _danmakuMap = {};
  final RxInt totalCount = 0.obs;
  final RxBool isLoading = false.obs;

  /// 配置版本号，每次保存设置时递增，用于通知 DanmakuView 更新选项
  final RxInt configVersion = 0.obs;

  // ===== 屏蔽规则（内存缓存）=====
  List<String> _keywords = const [];
  List<RegExp> _regexps = const [];

  /// 从 PlayerPref 重新加载屏蔽规则并编译正则
  void reloadFilter() {
    _keywords = PlayerPref.danmakuFilterKeywords
        .where((e) => e.isNotEmpty)
        .toList();

    final compiled = <RegExp>[];
    for (final raw in PlayerPref.danmakuFilterRegexes) {
      if (raw.isEmpty) continue;
      try {
        compiled.add(RegExp(raw, caseSensitive: false));
      } catch (_) {
        // 无效正则直接忽略，不抛异常，避免影响弹幕渲染
      }
    }
    _regexps = compiled;
  }

  bool _shouldBlock(String content) {
    if (_keywords.isEmpty && _regexps.isEmpty) return false;
    for (final k in _keywords) {
      if (content.contains(k)) return true;
    }
    for (final r in _regexps) {
      if (r.hasMatch(content)) return true;
    }
    return false;
  }

  void loadDanmaku(List<DanmakuItem> items) {
    // 每次加载新弹幕时同步一次规则（防止用户在其他页面改了规则）
    reloadFilter();

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
    List<DanmakuItem>? raw;
    if (_danmakuMap.containsKey(progress)) {
      raw = _danmakuMap[progress];
    } else {
      final keys = _danmakuMap.keys.toList()..sort();
      for (final key in keys) {
        if ((key - progress).abs() <= 50) {
          raw = _danmakuMap[key];
          break;
        }
        if (key > progress + 50) break;
      }
    }
    if (raw == null || raw.isEmpty) return null;

    // 无规则时直接返回原列表，避免额外分配
    if (_keywords.isEmpty && _regexps.isEmpty) return raw;

    final filtered = <DanmakuItem>[];
    for (final item in raw) {
      if (!_shouldBlock(item.content)) {
        filtered.add(item);
      }
    }
    return filtered.isEmpty ? null : filtered;
  }

  void clear() {
    _danmakuMap.clear();
    totalCount.value = 0;
  }

  int get count => totalCount.value;
}