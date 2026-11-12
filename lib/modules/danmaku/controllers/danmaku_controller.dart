import 'package:get/get.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yuanying/modules/danmaku/models/danmaku_model.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

class DanmakuController extends GetxController {
  final Map<int, List<DanmakuItem>> _danmakuMap = {};
  final RxInt totalCount = 0.obs;
  final RxBool isLoading = false.obs;

  /// 配置版本号，每次保存设置时递增，用于通知 DanmakuView 更新选项
  final RxInt configVersion = 0.obs;

  /// 数据版本号：每次 loadDanmaku / clear 递增。
  ///
  /// DanmakuView 监听此字段变化，回调里调用 canvas 渲染层 clear()，
  /// 用于解决"手动应用新弹幕后旧弹幕残留、交叉输出"的问题。
  ///
  /// 只在数据真正被替换/清空时递增；`reloadFilter()`（屏蔽规则变化）
  /// 刻意不递增，避免"改屏蔽规则就把屏幕上已发射的弹幕清光"的意外行为。
  final RxInt dataVersion = 0.obs;

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
      //                                    ↑ 这里是 Regexes，不是 Regexps
      if (raw.isEmpty) continue;
      try {
        compiled.add(RegExp(raw, caseSensitive: false));
      } catch (_) {
        // 无效正则直接忽略，不抛异常，避免影响弹幕渲染
      }
    }
    _regexps = compiled;
    // 注意：这里不递增 dataVersion（不主动清屏）
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

    debugPrint('DanmakuController.loadDanmaku: 接收 ${items.length} 条弹幕');
    _danmakuMap.clear();
    for (final item in items) {
      final key = item.progress;
      if (!_danmakuMap.containsKey(key)) {
        _danmakuMap[key] = [];
      }
      _danmakuMap[key]!.add(item);
    }
    totalCount.value = items.length;
    // ← 通知渲染层清空 canvas，避免旧弹幕与新弹幕交叉输出
    dataVersion.value++;
    debugPrint('DanmakuController: 加载完成，共 ${totalCount.value} 条');
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
    // 通知渲染层清空 canvas
    dataVersion.value++;
  }

  int get count => totalCount.value;
}