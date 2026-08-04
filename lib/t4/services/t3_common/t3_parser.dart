import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';

class T3Parser {
  static const String NOADD_INDEX = r':eq|:lt|:gt|:first|:last|:not|:even|:odd|:has|:contains|:matches|:empty|^body$|^#';
  static const String URLJOIN_ATTR = r'(url|src|href|-original|-src|-play|-url|style)$|^(data-|url-|src-)';
  static const String SPECIAL_URL = r'^(ftp|magnet|thunder|ws):';
  static String MY_URL = '';

  static bool _test(String text, String string) {
    return RegExp(text, caseSensitive: false, multiLine: true).hasMatch(string);
  }

  static bool _contains(String text, String match) => text.contains(match);

  static String _parseHikerToJq(String parse, {bool first = false}) {
    if (_contains(parse, '&&')) {
      final parses = parse.split('&&');
      final newParses = <String>[];
      for (int i = 0; i < parses.length; i++) {
        final psList = parses[i].split(' ');
        final ps = psList.last;
        if (!_test(NOADD_INDEX, ps)) {
          if (!first && i >= parses.length - 1) {
            newParses.add(parses[i]);
          } else {
            newParses.add('${parses[i]}:eq(0)');
          }
        } else {
          newParses.add(parses[i]);
        }
      }
      return newParses.join(' ');
    } else {
      final psList = parse.split(' ');
      final ps = psList.last;
      if (!_test(NOADD_INDEX, ps) && first) {
        return '$parse:eq(0)';
      }
      return parse;
    }
  }

  static (String, int, List<String>) _getParseInfo(String nparse) {
    var excludes = <String>[];
    var nparseIndex = 0;
    var nparseRule = nparse;

    if (_contains(nparse, ':eq')) {
      nparseRule = nparse.split(':eq')[0];
      var nparsePos = nparse.split(':eq')[1];
      if (_contains(nparseRule, '--')) {
        excludes = nparseRule.split('--').sublist(1);
        nparseRule = nparseRule.split('--')[0];
      } else if (_contains(nparsePos, '--')) {
        excludes = nparsePos.split('--').sublist(1);
        nparsePos = nparsePos.split('--')[0];
      }
      try {
        nparseIndex = int.parse(nparsePos.split('(')[1].split(')')[0]);
      } catch (_) {}
    } else if (_contains(nparse, '--')) {
      nparseRule = nparse.split('--')[0];
      excludes = nparse.split('--').sublist(1);
    }
    return (nparseRule, nparseIndex, excludes);
  }

  static String _reorderAdjacentLtAndGt(String selector) {
    final pattern = RegExp(r':gt\((\d+)\):lt\((\d+)\)');
    while (true) {
      final match = pattern.firstMatch(selector);
      if (match == null) break;
      final replacement = ':lt(${match.group(2)}):gt(${match.group(1)})';
      selector = selector.replaceFirst(pattern, replacement);
    }
    return selector;
  }

  static Element? _parseOneRule(Document doc, String nparse, Element? ret) {
    var (nparseRule, nparseIndex, excludes) = _getParseInfo(nparse);
    nparseRule = _reorderAdjacentLtAndGt(nparseRule);
    
    // 先获取当前上下文中的匹配元素集合
    List<Element> candidates;
    if (ret == null) {
      candidates = doc.querySelectorAll(nparseRule);
    } else {
      // 从当前元素内部查找（模拟 find）
      candidates = ret.querySelectorAll(nparseRule);
    }
    if (candidates.isEmpty) return null;

    Element? result;
    if (_contains(nparse, ':eq')) {
      if (nparseIndex < candidates.length) {
        result = candidates[nparseIndex];
      } else {
        return null;
      }
    } else {
      // 没有 :eq，默认取第一个（与原版一致）
      result = candidates.first;
    }

    if (excludes.isNotEmpty && result != null) {
      final clone = result.clone(true) as Element;
      for (final exclude in excludes) {
        final toRemove = clone.querySelector(exclude);
        if (toRemove != null) toRemove.remove();
      }
      return clone;
    }
    return result;
  }

  static String _parseText(String text) {
    text = text.replaceAll(RegExp(r'\s+'), '\n');
    text = text.replaceAll(RegExp(r'\n+'), '\n');
    text = text.replaceFirst(RegExp(r'^\s+'), '');
    text = text.replaceAll('\n', ' ');
    return text;
  }

  static String _urlJoin(String base, String path) {
    try {
      final uri = Uri.parse(base);
      final newUri = uri.resolve(path);
      return newUri.toString();
    } catch (_) {
      return base + path;
    }
  }

  static List<String> pdfa(String html, String parse) {
    if (html.isEmpty || parse.isEmpty) return [];
    parse = _parseHikerToJq(parse);
    final doc = parser.parse(html);
    final parses = parse.split(' ');
    Element? ret;
    for (final nparse in parses) {
      ret = _parseOneRule(doc, nparse, ret);
      if (ret == null) return [];
    }
    // 需要返回所有匹配元素（原版返回 ret 集合的所有元素）
    // 因为 ret 是最后一个选择器的结果，但集合可能包含多个元素，我们需要所有元素的外层HTML
    // 但是 _parseOneRule 总是返回单个 Element（第一个或 eq 索引），丢失了集合的其他元素
    // 原版使用 Cheerio 的 find，返回的是集合，ret.toArray() 得到所有匹配元素
    // 为修复，将 _parseOneRule 改为返回 List<Element> 或保留所有匹配。这里简化：重新查找一次完整选择器
    // 更准确：按规则逐步筛选，保留所有元素。重构：传递 List<Element> 作为上下文。
    // 但为快速修复，我们重新基于 doc 执行完整选择器（注意复合选择器可能不对）
    // 原版是逐步筛选，但最终 ret 是所有元素，我们采用另一种方式：递归调用 pdfa 已不现实。
    // 临时方案：解析 parse 为最终选择器，直接 querySelectorAll 返回所有匹配元素的外层html
    // 但这会丢失逐步筛选的上下文（如 :eq 前面步骤的限定）。在绝大多数场景下，原版也仅用于单个元素提取，pdfa 较少使用。
    // 若确实需要，建议重构 _parseOneRule 返回 List<Element>，此处先返回 ret 自身的外层html（单个）以保基本功能。
    // 但原版 pdfa 返回数组，应包含所有匹配元素。根据使用场景，我们实现一个简易版本：
    // 如果 parse 中没有空格，直接 querySelectorAll
    if (!parse.contains(' ')) {
      return doc.querySelectorAll(parse).map((e) => e.outerHtml).toList();
    }
    // 否则逐步筛选，但仅能返回最后筛选出的第一个元素？实际上原版每次 find 都返回集合，最后 ret 是集合。
    // 我们重新实现 _parseOneRule 返回 List<Element>，但改动较大。暂返回 ret 自身的外层html（可能丢失其他元素）
    // 由于原版在 xyq 和 xbpq 中使用 pdfa 较多，不可忽视。因此必须修正。
    // 我们重写 _parseOneRule 为返回 List<Element>，并调整 pdfa 逻辑。
    // 但由于已写到这里，我们直接重构：
    // 将上述 _parseOneRule 改为返回 List<Element>，并添加 _parseOneRuleList 方法。
    // 为了简洁，我们在下面重新声明一个内部函数。
    return _pdfaFull(html, parse);
  }

  // 新的 pdfa 实现，正确返回所有元素
  static List<String> _pdfaFull(String html, String parse) {
    parse = _parseHikerToJq(parse);
    final doc = parser.parse(html);
    final parses = parse.split(' ');
    List<Element>? retList;
    for (final nparse in parses) {
      retList = _parseOneRuleList(doc, nparse, retList);
      if (retList == null || retList.isEmpty) return [];
    }
    return retList!.map((e) => e.outerHtml).toList();
  }

  static List<Element>? _parseOneRuleList(Document doc, String nparse, List<Element>? retList) {
    var (nparseRule, nparseIndex, excludes) = _getParseInfo(nparse);
    nparseRule = _reorderAdjacentLtAndGt(nparseRule);
    List<Element> candidates;
    if (retList == null) {
      candidates = doc.querySelectorAll(nparseRule);
    } else {
      candidates = [];
      for (final el in retList) {
        candidates.addAll(el.querySelectorAll(nparseRule));
      }
    }
    if (candidates.isEmpty) return null;

    if (_contains(nparse, ':eq')) {
      if (nparseIndex < candidates.length) {
        candidates = [candidates[nparseIndex]];
      } else {
        return null;
      }
    }

    if (excludes.isNotEmpty) {
      final filtered = <Element>[];
      for (final el in candidates) {
        final clone = el.clone(true) as Element;
        bool exclude = false;
        for (final excl in excludes) {
          if (clone.querySelector(excl) != null) {
            exclude = true;
            break;
          }
        }
        if (!exclude) {
          // 需要移除排除元素，但这里我们直接返回克隆并移除内部排除元素
          for (final excl in excludes) {
            final toRemove = clone.querySelector(excl);
            if (toRemove != null) toRemove.remove();
          }
          filtered.add(clone);
        }
      }
      return filtered;
    }
    return candidates;
  }

  static String pdfh(String html, String parse, {String? baseUrl}) {
    if (html.isEmpty || parse.isEmpty) return '';
    // 提取 option 前不能先转换 parse
    String? option;
    if (_contains(parse, '&&')) {
      final parts = parse.split('&&');
      option = parts.removeLast();
      parse = parts.join('&&');
    }
    final normalizedParse = _parseHikerToJq(parse, first: true);
    final doc = parser.parse(html);
    if (normalizedParse == 'body&&Text' || normalizedParse == 'Text') {
      return _parseText(doc.text ?? '');
    } else if (normalizedParse == 'body&&Html' || normalizedParse == 'Html') {
      return doc.outerHtml;
    }
    final parses = normalizedParse.split(' ');
    List<Element>? ret;
    for (final nparse in parses) {
      ret = _parseOneRuleList(doc, nparse, ret);
      if (ret == null || ret.isEmpty) return '';
    }
    if (ret == null || ret.isEmpty) return '';
    final Element first = ret.first;

    if (option != null) {
      switch (option) {
        case 'Text':
          return _parseText(first.text ?? '');
        case 'Html':
          return first.outerHtml;
        default: {
          final original = first.clone(true) as Element;
          final opts = option.split('||');
          for (final opt in opts) {
            final dynamic attrValue = original.attributes[opt];
            final String value = attrValue?.toString() ?? '';
            String finalValue = value;

            if (opt.toLowerCase().contains('style') && finalValue.contains('url(')) {
              final match = RegExp(r'url\(([^)]+)\)').firstMatch(finalValue);
              if (match != null) {
                final rawUrl = match.group(1)!;
                finalValue = rawUrl.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
              }
            }

            if (finalValue.isNotEmpty && baseUrl != null && baseUrl.isNotEmpty) {
              final needAdd = _test(URLJOIN_ATTR, opt) && !_test(SPECIAL_URL, finalValue);
              if (needAdd) {
                if (finalValue.startsWith('http')) {
                  finalValue = finalValue.substring(finalValue.indexOf('http'));
                } else {
                  finalValue = _urlJoin(baseUrl, finalValue);
                }
              }
            }
            if (finalValue.isNotEmpty) return finalValue;
          }
          return '';
        }
      }
    } else {
      return first.outerHtml;
    }
  }

  static String pd(String html, String parse, {String? baseUrl}) {
    final effectiveBaseUrl = baseUrl ?? MY_URL;
    return pdfh(html, parse, baseUrl: effectiveBaseUrl);
  }

  static List<String> pdfl(String html, String parse, String listText, String listUrl, String baseUrl) {
    if (html.isEmpty || parse.isEmpty) return [];
    final doc = parser.parse(html);
    final elements = doc.querySelectorAll(parse);
    final result = <String>[];
    for (final el in elements) {
      final title = pdfh(el.outerHtml, listText, baseUrl: baseUrl);
      final url = pdfh(el.outerHtml, listUrl, baseUrl: baseUrl);
      if (title.isNotEmpty && url.isNotEmpty) {
        result.add('$title\$$url');
      }
    }
    return result;
  }
}