// lib/modules/agent_llm/utils/keyword_matcher.dart

/// 关键词意图匹配。
///
/// 仅供「模型不支持 tools 时的兜底」使用，不应作为主路径。
/// 对齐 DsPlayer 的做法：模型靠好描述 + 好状态自主路由，
/// 这里只是少数高频工具的保险。
abstract final class KeywordMatcher {
  /// 反问 / 功能咨询，命中则不做任何兜底触发
  static const _questionPatterns = <String>[
    '怎么用',
    '如何使用',
    '是什么功能',
    '你能做什么',
    '支持什么',
  ];

  /// 状态查询关键词（get_player_state）
  static const _statePatterns = <String>[
    '我在看什么',
    '当前播放',
    '正在播放',
    '第几集',
    '这是什么剧',
    '什么电视',
    '播放进度',
    '现在播的',
  ];

  /// 搜索前缀（search_video）。长的在前，避免被短前缀吃掉。
  static const _searchPrefixes = <String>[
    '帮我搜索一下',
    '帮我搜一下',
    '帮我找一下',
    '搜索一下',
    '搜索',
    '搜一下',
    '搜搜',
    '找一下',
    '找找',
    '帮我搜索',
    '帮我搜',
    '帮我找',
    '看看有没有',
    '有没有',
    '能不能搜',
    '能搜',
    '能不能找',
    '能找',
  ];

  /// 关键词尾部常见语气词 / 后缀
  static const _searchSuffixes = <String>[
    '的视频',
    '的影视',
    '的剧',
    '的电影',
    '的电影资源',
    '资源',
    '有没有',
    '吧',
    '啊',
    '呢',
    '呗',
    '一下',
  ];

  /// 匹配搜索意图。命中返回 {keyword: ...}，否则 null
  static Map<String, dynamic>? matchSearch(String text) {
    if (text.isEmpty || text.length > 60) return null;
    if (_questionPatterns.any(text.contains)) return null;
    final kw = _extractSearchKeyword(text);
    if (kw == null || kw.isEmpty) return null;
    return {'keyword': kw};
  }

  /// 匹配播放状态查询意图。命中返回 {}，否则 null
  static Map<String, dynamic>? matchPlayerState(String text) {
    if (text.isEmpty) return null;
    if (_questionPatterns.any(text.contains)) return null;
    if (_statePatterns.any(text.contains)) return <String, dynamic>{};
    return null;
  }

  static String? _extractSearchKeyword(String text) {
    for (final p in _searchPrefixes) {
      final idx = text.indexOf(p);
      if (idx < 0) continue;
      var kw = text.substring(idx + p.length).trim();
      if (kw.isEmpty) continue;
      kw = _cleanKeyword(kw);
      if (kw.isEmpty) continue;
      return kw;
    }
    return null;
  }

  static String _cleanKeyword(String s) {
    var r = s;
    r = r.replaceAll(RegExp(r'[，。！？,.!?\s]+$'), '');
    for (final suf in _searchSuffixes) {
      if (r.endsWith(suf) && r.length > suf.length) {
        r = r.substring(0, r.length - suf.length);
      }
    }
    return r.trim();
  }
}