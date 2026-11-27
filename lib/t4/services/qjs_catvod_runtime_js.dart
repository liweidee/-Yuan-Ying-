/// CatVod 源常用的 HTML 解析宿主垫片。
///
/// 这些函数依赖 QuickJS 内置 cheerio（或 CatLib 加载的 cheerio），
/// 用于兼容 pdfh/pdfa/pd/pdfl、jsp 等 TVBox/CatVod 公共函数。
const qjsCatVodHtmlParserJs = r'''
(function() {
  var cheerio = globalThis.cheerio || globalThis.__full_cheerio__;
  if (!cheerio || typeof cheerio.load !== 'function') {
    console.error('[QjsCatVod] cheerio 不可用，无法注入 pdfh/pdfa/pd/pdfl');
    return;
  }

  var NOADD_INDEX = ':eq|:lt|:gt|:first|:last|:not|:even|:odd|:has|:contains|:matches|:empty|^body$|^#';
  var URLJOIN_ATTR = '(url|src|href|-original|-src|-play|-url|style)$|^(data-|url-|src-)';
  var SPECIAL_URL = '^(ftp|magnet|thunder|ws):';

  function test(text, string) {
    try { return new RegExp(text, 'mi').test(string); } catch (e) { return false; }
  }
  function contains(text, match) { return String(text).indexOf(match) !== -1; }

  function urljoin(from, to) {
    try {
      var resolvedUrl = new URL(to, new URL(from, 'resolve://'));
      if (resolvedUrl.protocol === 'resolve:') {
        return resolvedUrl.pathname + resolvedUrl.search + resolvedUrl.hash;
      }
      return resolvedUrl.href;
    } catch (e) { return (from || '') + (to || ''); }
  }

  function parseHikerToJq(parse, first) {
    if (contains(parse, '&&')) {
      var parses = parse.split('&&');
      var newParses = [];
      for (var i = 0; i < parses.length; i++) {
        var psList = parses[i].split(' ');
        var ps = psList[psList.length - 1];
        if (!test(NOADD_INDEX, ps)) {
          newParses.push(
            !first && i >= parses.length - 1
              ? parses[i]
              : parses[i] + ':eq(0)'
          );
        } else {
          newParses.push(parses[i]);
        }
      }
      parse = newParses.join(' ');
    } else {
      var list = parse.split(' ');
      var last = list[list.length - 1];
      if (!test(NOADD_INDEX, last) && first) parse = parse + ':eq(0)';
    }
    return parse;
  }

  function getParseInfo(parse) {
    var excludes = [];
    var index = 0;
    var rule = parse;
    if (contains(parse, ':eq')) {
      rule = parse.split(':eq')[0];
      var pos = parse.split(':eq')[1];
      if (contains(rule, '--')) {
        excludes = rule.split('--').slice(1);
        rule = rule.split('--')[0];
      } else if (contains(pos, '--')) {
        excludes = pos.split('--').slice(1);
        pos = pos.split('--')[0];
      }
      try { index = parseInt(pos.split('(')[1].split(')')[0], 10); } catch (e) {}
    } else if (contains(parse, '--')) {
      rule = parse.split('--')[0];
      excludes = parse.split('--').slice(1);
    }
    return { rule: rule, index: index, excludes: excludes };
  }

  function reorderLtGt(selector) {
    var pattern = /:gt\((\d+)\):lt\((\d+)\)/;
    var match;
    while ((match = pattern.exec(selector)) !== null) {
      var replacement = ':lt(' + match[2] + '):gt(' + match[1] + ')';
      selector = selector.substring(0, match.index) + replacement +
        selector.substring(match.index + match[0].length);
      pattern.lastIndex = match.index;
    }
    return selector;
  }

  function parseOneRule(doc, parse, ret) {
    var info = getParseInfo(parse);
    var rule = reorderLtGt(info.rule);
    ret = ret ? ret.find(rule) : doc(rule);
    if (contains(parse, ':eq')) ret = ret.eq(info.index);
    if (info.excludes.length > 0 && ret) {
      try {
        ret = ret.clone();
        for (var i = 0; i < info.excludes.length; i++) {
          ret.find(info.excludes[i]).remove();
        }
      } catch (e) {}
    }
    return ret;
  }

  function parseText(text) {
    if (text == null) return '';
    return String(text)
      .replace(/[\s]+/gm, '\n')
      .replace(/\n+/g, '\n')
      .replace(/^\s+/, '')
      .replace(/\n/g, ' ');
  }

  globalThis.pdfa = function(html, parse) {
    if (!html || !parse) return [];
    parse = parseHikerToJq(parse, false);
    var doc = cheerio.load(html);
    var parses = parse.split(' ');
    var ret = null;
    for (var i = 0; i < parses.length; i++) {
      ret = parseOneRule(doc, parses[i], ret);
      if (!ret) return [];
    }
    var result = [];
    var items = [];
    try { items = ret && ret.toArray ? ret.toArray() : []; } catch (e) {}
    for (var j = 0; j < items.length; j++) {
      try {
        var itemHtml = doc.html(items[j]);
        if (itemHtml) result.push(itemHtml);
      } catch (e) {}
    }
    return result;
  };

  globalThis.pdfh = function(html, parse, baseUrl) {
    if (!html || !parse) return '';
    var doc = cheerio.load(html);
    if (parse === 'body&&Text' || parse === 'Text') {
      return parseText(doc.text());
    }
    if (parse === 'body&&Html' || parse === 'Html') return doc.html();

    var option;
    if (contains(parse, '&&')) {
      var parts = parse.split('&&');
      option = parts.pop();
      parse = parts.join('&&');
    }
    parse = parseHikerToJq(parse, true);
    var parses = parse.split(' ');
    var ret = null;
    for (var i = 0; i < parses.length; i++) {
      ret = parseOneRule(doc, parses[i], ret);
      if (!ret) return '';
    }
    if (!option) return String(ret);
    if (option === 'Text') return ret ? parseText(ret.text()) : '';
    if (option === 'Html') return ret ? ret.html() : '';

    var original = ret.clone();
    var options = option.split('||');
    for (var k = 0; k < options.length; k++) {
      var attr = options[k];
      ret = original.attr(attr) || '';
      if (contains(attr.toLowerCase(), 'style') && contains(ret, 'url(')) {
        try {
          ret = ret.match(/url\((.*?)\)/)[1].replace(/^['"]|['"]$/g, '');
        } catch (e) {}
      }
      if (ret && baseUrl) {
        var needAdd = test(URLJOIN_ATTR, attr) && !test(SPECIAL_URL, ret);
        if (needAdd) {
          ret = ret.indexOf('http') >= 0
            ? ret.slice(ret.indexOf('http'))
            : urljoin(baseUrl, ret);
        }
      }
      if (ret) return ret;
    }
    return '';
  };

  globalThis.pd = function(html, parse, baseUrl) {
    return globalThis.pdfh(html, parse, baseUrl || '');
  };

  globalThis.pdfl = function(html, parse, listText, listUrl, myUrl) {
    if (!html || !parse) return [];
    parse = parseHikerToJq(parse, false);
    var doc = cheerio.load(html);
    var parses = parse.split(' ');
    var ret = null;
    for (var i = 0; i < parses.length; i++) {
      ret = parseOneRule(doc, parses[i], ret);
      if (!ret) return [];
    }
    var result = [];
    var count = 0;
    try { count = ret && ret.length ? ret.length : 0; } catch (e) {}
    for (var i = 0; i < count; i++) {
      try {
        var itemHtml = ret.eq(i).toString();
        result.push(
          globalThis.pdfh(itemHtml, listText) + '$' +
          globalThis.pd(itemHtml, listUrl, myUrl)
        );
      } catch (e) {}
    }
    return result;
  };

  globalThis.jsp = {
    pdfh: globalThis.pdfh,
    pdfa: globalThis.pdfa,
    pd: globalThis.pd,
    pdfl: globalThis.pdfl,
  };
  globalThis.jq = globalThis.jsp;
  globalThis.pq = function(html) { return cheerio.load(html); };
})();
''';
