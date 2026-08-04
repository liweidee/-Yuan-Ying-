import 'package:get/get.dart';
import 'package:json5/json5.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/t3_common/t3_json_adapter.dart';
import 'package:yuanying/t4/services/t3_common/t3_parser.dart';
import 'package:yuanying/t4/services/t3_common/t3_rule_parse.dart';
import 'package:yuanying/t4/services/t3_common/t3_utils.dart';
import 'package:yuanying/t4/services/t3_common/t3_jinja.dart';
import 'package:yuanying/t4/services/t3_common/t3_default_rules.dart';
import 'dart:convert';

class XbpqService extends T3JsonAdapter {
  XbpqService(String id, String api, String extUrl, List<String> categories)
      : super(id, api, extUrl, categories);

  @override
  Future<void> init() async {
    await loadConfig();
    final homeUrl = getRuleValue(['主页url'], '');
    final classUrl = _getHome(getRuleValue(['分类url']));
    var url = homeUrl.isNotEmpty ? homeUrl : classUrl;
    rule['host'] = _getHome(url);
    rule['homeUrl'] = rule['host'];

    // 处理分类url中的 switch
    var turl = getRuleValue(['分类url']);
    final splitResult = splitTextWithSingleBracket(turl);
    turl = splitResult.firstWhere((e) => e.isNotEmpty, orElse: () => '');
    if (turl.contains(';;')) {
      final parts = turl.split(';;');
      turl = parts[0];
      rule['switchs'] = parts[1];
      setSwitchs(parts[1]);
    }

    // 首页分类
    var home = getRuleValue(['首页']);
    final classData = getRuleValue(['分类']);
    final mainClasses = _parseClassList(classData);
    if (home.isNotEmpty) {
      if (home.contains('\$')) home = home.split('\$')[0];
      final idx = mainClasses.indexWhere((c) => c['type_name'] == home);
      if (idx != -1) {
        final tid = mainClasses[idx]['type_id'];
        rule['主页surl'] = turl.replaceAll('{cateId}', tid).replaceAll('{catePg}', '1');
      }
    }

    // 自动补全筛选占位符
    if (turl.contains('{class}') && getRuleValue(['剧情']).isEmpty) {
      config['剧情'] = autoRule['剧情'];
    }
    if (turl.contains('{year}') && getRuleValue(['年份']).isEmpty) {
      config['年份'] = autoRule['年份'];
    }
    if (turl.contains('{area}') && getRuleValue(['地区']).isEmpty) {
      config['地区'] = autoRule['地区'];
    }
    if (turl.contains('{by}') && getRuleValue(['排序']).isEmpty) {
      config['排序'] = autoRule['排序'];
    }

    // ===== 请求头处理（与 XYQ 对齐） =====
    final headerStr = getRuleValue(['请求头', 'ua', 'UserAgent'], '电脑');
    Map<String, String> headers = {};
    if (headerStr.contains('#') || headerStr.contains('\$')) {
      headers = _parseStringToObject(headerStr);
    } else {
      headers['User-Agent'] = headerStr;
    }

    // 替换 UA 占位符为完整 UA
    String ua = headers['User-Agent'] ?? '电脑';
    if (ua == '电脑') {
      ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    } else if (ua == '手机') {
      ua = 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    } else if (ua == 'PC_UA') {
      ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    } else if (ua == 'MOBILE_UA') {
      ua = 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    }
    headers['User-Agent'] = ua;

    // 合并 Cookie、Referer、自定义头部
    if (getRuleValue(['Cookie']).isNotEmpty) {
      headers['Cookie'] = getRuleValue(['Cookie']);
    }
    if (getRuleValue(['Referer']).isNotEmpty) {
      headers['Referer'] = getRuleValue(['Referer']);
    }
    final heads = getRuleValue(['头部集合', 'User']);
    if (heads.isNotEmpty) {
      for (final h in heads.split('#')) {
        final kv = h.split('\$');
        if (kv.length == 2) {
          headers[kv[0]] = kv[1];
        }
      }
    }
    rule['headers'] = headers;

    // ===== 播放相关配置 =====
    final playheads = getRuleValue(['播放请求头']);
    if (playheads.isNotEmpty) {
      final parsed = _parseStringToObject(playheads);
      if (parsed.isNotEmpty) rule['playheads'] = parsed;
    }
    final lazy = getRuleValue(['lazy']);
    if (lazy.isNotEmpty) rule['lazy'] = lazy;
    final click = getRuleValue(['click']);
    if (click.isNotEmpty) rule['js'] = click;
    final snifferw = getRuleValue(['嗅探词']);
    if (snifferw.isNotEmpty) rule['snifferw'] = snifferw.replaceAll('#', '|');
    final exsnifferw = getRuleValue(['过滤词']);
    if (exsnifferw.isNotEmpty) rule['exsnifferw'] = exsnifferw.replaceAll('#', '|');
    final jx = getRuleValue(['解析']);
    if (jx.isNotEmpty) {
      final parsed = _parseStringToObject(jx);
      if (parsed.isNotEmpty) rule['解析'] = parsed;
    }
    if (getRuleValue(['直接播放']) == '1') {
      rule['二级'] = '*';
      if (!rule.containsKey('playheads')) rule['playheads'] = rule['headers'];
      if (!(rule['playheads'] as Map).containsKey('Referer')) {
        (rule['playheads'] as Map)['Referer'] = rule['host'];
      }
    }

    // ===== 自动提取分类（如果未配置） =====
    if (mainClasses.isEmpty) {
      final autoContent = this.autoContent;
      final mainurl = getRuleValue(['主页url']).isEmpty ? rule['host'] : getRuleValue(['主页url']);
      String html = await req(mainurl);
      html = autoContent.splitStr(html, ['分类二次截取'], params: {'twice': true}) ?? html;
      final classArray = getRuleValue(['分类数组']);
      if (classArray.isNotEmpty) {
        final list = XBPQParse.getSplitArray(html, classArray);
        final newClasses = <String>[];
        for (final item in list) {
          final title = autoContent.splitStr(item, ['分类标题'], def: '>&&</a');
          final id = autoContent.splitStr(item, ['分类ID']);
          if (id != null && id.isNotEmpty) {
            newClasses.add('$title\$$id');
          }
        }
        if (newClasses.isNotEmpty) {
          config['分类'] = newClasses.join('#');
        }
      }
    }

    // ===== 筛选生成 =====
    if (getRuleValue(['筛选']) == '1' || getRuleValue(['筛选']).isEmpty) {
      final filters = <String, dynamic>{};
      for (int i = 0; i < mainClasses.length; i++) {
        final c = mainClasses[i];
        final tid = c['type_id'];
        final name = c['type_name'];
        final filterItems = _getFilter(i, name);
        if (filterItems.isNotEmpty) {
          filters[tid] = filterItems;
        }
      }
      config['筛选'] = filters;
    }
  }

  // ---------- 分类解析辅助 ----------
  List<Map<String, dynamic>> _parseClassList(String data) {
    final list = <Map<String, dynamic>>[];
    if (data.contains('\$')) {
      for (final c in data.split('#')) {
        final parts = c.split('\$');
        if (parts.length == 2) {
          list.add({'type_id': parts[1], 'type_name': parts[0]});
        }
      }
    } else if (data.contains('&') && getRuleValue(['分类值']).isNotEmpty) {
      final names = data.split('&');
      final ids = getRuleValue(['分类值']).split('&');
      for (int i = 0; i < ids.length && i < names.length; i++) {
        list.add({'type_id': ids[i], 'type_name': names[i]});
      }
    }
    return list;
  }

  Map<String, String> _parseStringToObject(String input) {
    final obj = <String, String>{};
    for (final pair in input.split('#')) {
      final parts = pair.split('\$');
      if (parts.length == 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
        obj[parts[0].trim()] = parts[1].trim();
      }
    }
    return obj;
  }

  String _getHome(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return '';
    }
  }

  // 生成筛选（简化版，完整逻辑参考 TS 的 getFilter）
  List<Map<String, dynamic>> _getFilter(int index, String typeName) {
    final aliasMap = {
      '电影': ['电影', '電影'],
      '连续剧': ['连续剧', '連續劇'],
      '综艺': ['综艺', '綜藝'],
      '动漫': ['动漫', '動漫'],
      '纪录片': ['纪录片'],
    };
    String originalType = typeName;
    for (final entry in aliasMap.entries) {
      for (final alias in entry.value) {
        if (typeName.contains(alias)) {
          originalType = entry.key;
          break;
        }
      }
    }
    final filters = <Map<String, dynamic>>[];
    final mapping = {
      '类型': 'cateId',
      '剧情': 'class',
      '地区': 'area',
      '年份': 'year',
      '语言': 'lang',
      '字母': 'letter',
      '排序': 'by',
    };
    for (final entry in mapping.entries) {
      final key = entry.key;
      final field = entry.value;
      String item = getRuleValue([key]);
      String value = getRuleValue(['${key}值']);
      if (item.isEmpty || item == '*') continue;
      if (item.contains('||')) {
        final options = item.split('||');
        // 按 index 取，但一般只有一条
        if (options.length > index) item = options[index];
        else item = options[0];
      }
      if (item == '空') continue;
      if (item.contains('#')) {
        final parts = item.split('#').map((e) {
          if (e.contains('\$')) {
            final kv = e.split('\$');
            return {'n': kv[0], 'v': kv[1]};
          } else {
            return {'n': e, 'v': e};
          }
        }).toList();
        if (parts.isNotEmpty && parts[0]['n'] != '全部' && field != 'by') {
          parts.insert(0, {'n': '全部', 'v': ''});
        }
        final valueList = value.isNotEmpty ? value.split('#') : [];
        for (int i = 0; i < parts.length; i++) {
          if (i < valueList.length && valueList[i].isNotEmpty) {
            parts[i]['v'] = valueList[i];
          }
        }
        filters.add({
          'key': field,
          'name': key,
          'value': parts,
        });
      } else if (item.contains('&')) {
        final names = item.split('&');
        final ids = value.isNotEmpty ? value.split('&') : List.filled(names.length, '');
        final valueList = <Map<String, String>>[];
        for (int i = 0; i < names.length; i++) {
          valueList.add({'n': names[i], 'v': ids.length > i ? ids[i] : ''});
        }
        if (valueList.isNotEmpty && valueList[0]['n'] != '全部' && field != 'by') {
          valueList.insert(0, {'n': '全部', 'v': ''});
        }
        filters.add({
          'key': field,
          'name': key,
          'value': valueList,
        });
      }
    }
    return filters;
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    final classData = getRuleValue(['分类']);
    final rawClasses = _parseClassList(classData);
    final classes = rawClasses
        .where((c) => c['type_id'] != null && c['type_name'] != null && !categories.contains(c['type_name']))
        .toList();
    final seen = <String>{};
    final unique = classes.where((c) {
      final id = c['type_id'].toString();
      if (seen.contains(id)) return false;
      seen.add(id);
      return true;
    }).toList();
    final filters = <String, dynamic>{};
    final filterData = getRuleValue(['筛选']);
    if (filterData == '1' || filterData.isEmpty) {
      final rawFilters = getRuleValue(['筛选'], '{}');
      try {
        final parsed = JSON5.parse(rawFilters);
        if (parsed is Map) {
          final classIds = unique.map((c) => c['type_id'].toString()).toList();
          for (final key in parsed.keys) {
            if (classIds.contains(key.toString())) {
              filters[key.toString()] = parsed[key];
            }
          }
        }
      } catch (_) {}
    }

    // --- 获取首页推荐列表 ---
    final homeUrl = getRuleValue(['主页url'], '');
    final classUrl = _getHome(getRuleValue(['分类url']));
    var url = homeUrl.isNotEmpty ? homeUrl : classUrl;
    final homeSurl = rule['主页surl'] as String? ?? '';
    if (homeSurl.isNotEmpty) {
      url = homeSurl;
    }
    List<Map<String, dynamic>> homeList = [];
    if (url.isNotEmpty) {
      final list = await parseLevelOne(url, '首页');
      homeList = list.map((item) {
        return {
          'vod_id': item['vod_id']?.toString() ?? '',
          'vod_name': item['vod_name']?.toString() ?? '',
          'vod_pic': item['vod_pic']?.toString() ?? '',
          'vod_remarks': item['vod_remarks']?.toString() ?? '',
          'vod_blurb': item['vod_blurb']?.toString() ?? '',
          'vod_tag': item['vod_tag']?.toString() ?? 'file',
        };
      }).toList();
    }

    return {
      'class': unique,
      'filters': filters,
      'list': homeList,
      'page': 1,
      'pagecount': homeList.isNotEmpty ? 1 : 0,
      'total': homeList.length,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchCate(String cateId, int page, {String? ext}) async {
    var url = getRuleValue(['分类url']);
    final firstPage = getRuleValue(['起始页', '分类起始页码', 'qishiye', 'firstpage'], '1');
    if (url.contains('[') && (url.contains('];') || url.endsWith(']'))) {
      if (page.toString() == firstPage) {
        url = url.replaceAll(RegExp(r'[^\n\r[|\u2028\u2029]*[[|].*(http[^\]]*).*'), r'\$1');
      } else {
        url = url.replaceAll(RegExp(r'\|\|'), r'\\|').replaceAll(RegExp(r'(.*)[[|].*'), r'\$1');
      }
    }
    if (url.contains(';;')) url = url.split(';;')[0];
    final host = _getHome(getRuleValue(['分类url']));
    final extend = ext != null ? jsonDecode(ext) as Map<String, dynamic> : {};
    url = url
        .replaceAll('{cateId}', cateId)
        .replaceAll('{catePg}', page.toString())
        .replaceAll('{class}', extend['class'] ?? '')
        .replaceAll('{area}', extend['area'] ?? '')
        .replaceAll('{year}', extend['year'] ?? '')
        .replaceAll('{by}', extend['by'] ?? '')
        .replaceAll('{lang}', extend['lang'] ?? '')
        .replaceAll('{letter}', extend['letter'] ?? '');
    if (url.isEmpty) {
      print('fetchCate: URL 为空，返回空列表');
      return {'list': [], 'page': page, 'pagecount': 0, 'total': 0};
    }
    if (!url.startsWith('http')) {
      if (host.isNotEmpty) url = host + (url.startsWith('/') ? '' : '/') + url;
    }

    print('fetchCate: 准备调用 parseLevelOne');
    final list = await parseLevelOne(url, '分类');
    print('fetchCate: parseLevelOne 返回列表长度 = ${list.length}');
    if (list.isNotEmpty) {
      print('fetchCate: 第一条数据 = ${list[0]}');
    }

    // 改为返回 Map 列表（与 T4/drpy2 一致）
    final videos = list.map((item) {
      return {
        'vod_id': item['vod_id']?.toString() ?? '',
        'vod_name': item['vod_name']?.toString() ?? '',
        'vod_pic': item['vod_pic']?.toString() ?? '',
        'vod_remarks': item['vod_remarks']?.toString() ?? '',
        'vod_blurb': item['vod_blurb']?.toString() ?? '',
        'vod_tag': item['vod_tag']?.toString() ?? 'file',
      };
    }).toList();

    print('fetchCate: videos 长度 = ${videos.length}');
    if (videos.isNotEmpty) {
      print('fetchCate: 第一条视频 = ${videos[0]['vod_id']}, ${videos[0]['vod_name']}');
    }

    return {
      'list': videos,
      'page': page,
      'pagecount': videos.isNotEmpty ? 999 : 0,
      'total': videos.isNotEmpty ? 999 : 0,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    // 解析 ids 可能包含 $ 或 @@
    String vodUrl = ids;
    String vodName = '';
    String vodPic = '';
    if (vodUrl.contains('\$')) {
      final tmp = vodUrl.split('\$');
      if (tmp.length > 1) vodUrl = tmp[1];
    }
    if (vodUrl.contains('@@')) {
      final tmp = vodUrl.split('@@');
      vodUrl = tmp[0];
      if (tmp.length > 1) vodName = tmp[1];
      if (tmp.length > 2) vodPic = tmp[2];
    }

    if (rule['二级'] == '*') {
      return {
        'list': [
          {
            'vod_id': vodUrl,
            'vod_name': vodName,
            'vod_pic': vodPic,
            'vod_remarks': '',
            'vod_play_url': '播放视频\$$vodUrl',
            'vod_play_from': '嗅探',
          }
        ]
      };
    }

    final host = _getHome(vodUrl);
    final html = await req(vodUrl);
    final autoContent = this.autoContent;

    // 线路提取
    final lienHtml = autoContent.splitStr(html, ['线路二次截取'], params: {'twice': true}) ?? html;
    final fromle = autoContent.splitArray(lienHtml, ['线路数组'], params: {'key': '线路数组'});
    List<String> from = [];
    for (final v in fromle) {
      String lineTitle = autoContent.splitStr(v, ['线路标题'], def: '">&&<', params: {'type': '文本', 'key': '线路标题'}) ?? '';
      if (lineTitle.isEmpty) {
        lineTitle = removeTagsExceptList(v as String, <String>[]).replaceAll(RegExp(r'[<>]'), '').trim();
      }
      if (lineTitle.isNotEmpty) from.add(lineTitle);
    }
    if (from.isEmpty) from = ['默认线路'];

    // 简介
    String desc = autoContent.splitStr(html, ['简介'], params: {'type': '文本', 'key': '简介'}) ?? '';
    desc = desc.replaceAll(r'\\r\\n', '<br>').replaceAll(r'\n', '<br>');
    desc = removeSingleAngleBrackets(desc);
    desc = convertMultipleUnicodeEscapedWords(desc);
    desc = replaceTagsWithMapping(desc, {'br': ['span', 'p']});
    desc = removeTagsExceptList(desc, ['br']);
    desc = desc.replaceAll(RegExp(r'<br>\s*<br>'), '<br>').trim();

    // 其他字段
    final status = autoContent.splitStr(html, ['影片状态'], def: autoRule['影片状态'] as String?, params: {'type': '文本'}) ?? '';
    final type = autoContent.splitStr(html, ['影片类型'], def: autoRule['影片类型'] as String?, params: {'type': '文本'}) ?? '';
    final actor = autoContent.splitStr(html, ['主演'], def: (autoRule['主演'] as List<String>)[0], params: {'type': '文本'}) ?? '';
    final director = autoContent.splitStr(html, ['导演'], def: (autoRule['导演'] as List<String>)[0], params: {'type': '文本'}) ?? '';
    final year = autoContent.splitStr(html, ['影片年代'], def: autoRule['影片年代'] as String?, params: {'type': '文本'}) ?? '';
    final area = autoContent.splitStr(html, ['影片地区'], def: autoRule['影片地区'] as String?, params: {'type': '文本'}) ?? '';

    // 多线并发
    final duoxian = autoContent.splitStr(lienHtml, ['多线二次截取'], params: {'twice': true}) ?? lienHtml;
    final duoxianArray = XBPQParse.getSplitArray(duoxian, getRuleValue(['多线数组']));
    List<String> duoxianUrls = [];
    for (final v in duoxianArray) {
      final (ihost, getUrl) = _prefixORsuffix(html, '多线', host);
      String url = XBPQParse.getSplitStr(v, getRuleValue(['多线链接'], 'href="&&"'), ihost);
      url = getUrl(url);
      if (url.isNotEmpty) duoxianUrls.add(url);
    }

    List<String> htmls = [html];
    if (duoxianUrls.isNotEmpty) {
      final futures = duoxianUrls.map((u) => req(u)).toList();
      final results = await Future.wait(futures);
      htmls.addAll(results);
    }

    final surls = <String>{};
    final allPlaylists = <String>[];
    for (final ithml in htmls) {
      final playHtml = autoContent.splitStr(ithml, ['播放二次截取'], params: {'twice': true}) ?? ithml;
      final playHtmlArr = autoContent.splitArray(playHtml, ['播放数组'], params: {'key': '播放数组'});
      for (int i = 0; i < playHtmlArr.length; i++) {
        final v = playHtmlArr[i];
        final (phost, pgetUrl) = _prefixORsuffix(ithml, '播放', host);
        final tplaylist = autoContent.splitArray(v, ['播放列表'], def: autoRule['播放列表'] as String?);
        var playlist = <String>[];
        for (final item in tplaylist) {
          String title = autoContent.splitStr(item, ['播放标题'], def: 'title="&&"', params: {'type': '文本', 'key': '播放标题'}) ?? '';
          if (title.isEmpty) {
            title = item.replaceAll(RegExp(r'.*>'), '').replaceAll('\n', '').trim();
          }
          String url = autoContent.splitStr(item, ['播放链接'], def: autoRule['播放链接'] as String?, params: {'host': phost, 'type': '链接', 'key': '播放链接'}) ?? '';
          url = pgetUrl(url);
          if (url.isEmpty || url.contains('javascript')) continue;
          if (surls.contains(url)) continue;
          surls.add(url);
          playlist.add('$title\$$url');
        }
        if (rule['倒序'] == '1') playlist = playlist.reversed.toList();
        if (playlist.isNotEmpty) allPlaylists.add(playlist.join('#'));
      }
    }

    // 截断线路名数量
    from = from.sublist(0, allPlaylists.length > from.length ? from.length : allPlaylists.length);
    final playFrom = from.join(r'$$$');   // 修复：使用原始字符串
    final playUrl = allPlaylists.join(r'$$$'); // 修复

    final video = {
      'vod_id': vodUrl,
      'vod_name': vodName,
      'vod_pic': vodPic,
      'vod_year': year,
      'vod_area': area,
      'vod_actor': actor,
      'vod_director': director,
      'vod_content': desc,
      'vod_remarks': status,
      'vod_play_from': playFrom,
      'vod_play_url': playUrl,
    };
    return {'list': [video]};
  }

  String removeSingleAngleBrackets(String input) {
    return input.replaceAllMapped(RegExp(r'<([^>]+)>|<([^>])|([^<])>'), (m) {
      if (m.group(1) != null) return m.group(0)!;
      if (m.group(3) != null && RegExp(r'[。，]').hasMatch(m.group(3)!)) return m.group(3)!;
      return '';
    });
  }

  (String, String Function(String)) _prefixORsuffix(String html, String input, String host) {
    final prefix = XBPQParse.getHasRuleSplitStr(html, getRuleValue(['${input}链接前缀']));
    final suffix = XBPQParse.getHasRuleSplitStr(html, getRuleValue(['${input}链接后缀']));
    String ihost = host;
    if (prefix == null && suffix == null) ihost = host;
    return (
      ihost,
      (url) {
        if (prefix != null && url.contains(prefix)) url = url.replaceFirst(prefix, '');
        return (prefix ?? '') + url + (suffix ?? '');
      }
    );
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) async {
    // 如果是 push:// 链接，直接返回，不进行任何处理
    if (play.startsWith('push://')) {
      return {'url': play, 'parse': 0};
    }

    String input = play;
    final jxs = rule['解析'] as Map<String, String>?;
    if (jxs != null && input.isNotEmpty) {
      if (!input.startsWith('http')) {
        if (jxs.containsKey(flag)) {
          input = jxs[flag]! + input;
        } else if (jxs.containsKey('默认')) {
          input = jxs['默认']! + input;
        }
      }
    }

    // 跳转播放链接
    final jumpRule = getRuleValue(['跳转播放链接']);
    if (jumpRule.isNotEmpty) {
      final h = await req(input, headers: {'Referer': _getHome(input)});
      String temp = autoContent.splitStr(h, ['跳转播放链接'], params: {'type': '链接'}) ?? '';
      if (temp.startsWith('http')) {
        if (temp.contains('punish?x5sec')) temp = input;
        else input = normalizeUrl(temp);
        final sniffer = rule['snifferw'] as String?;
        if (sniffer != null && RegExp(sniffer).hasMatch(input)) {
          return {'url': input, 'parse': 0};
        }
      }
    }

    int parse = 1;
    if (RegExp(r'\.(?:m3u8|mp4|mpd|flv|mkv)').hasMatch(input)) parse = 0;
    final headers = rule['playheads'] ?? rule['headers'];
    return {'url': input, 'parse': parse, 'headers': headers};
  }

  @override
  Future<Map<String, dynamic>> search(String wd, int page, {int quick = 0}) async {
    String url = getRuleValue(['搜索url'], '/index.php/ajax/suggest?mid=1&wd={wd}&limit=500');
    url = url.replaceAll('{wd}', wd).replaceAll('{pg}', page.toString()).replaceAll('{catePg}', page.toString());
    final host = rule['host'] as String? ?? '';
    if (!url.startsWith('http')) url = host + url;
    String html = await req(url);
    final autoContent = this.autoContent;
    html = autoContent.splitStr(html, ['搜索二次截取'], params: {'twice': true}) ?? html;
    final htmlList = autoContent.splitArray(html, ['搜索数组', '数组'], params: {'key': '数组', 'ctype': '搜索'});
    final list = <Map<String, dynamic>>[];
    for (final item in htmlList) {
      final name = autoContent.splitStr(item, ['搜索标题', '标题'], def: 'title="&&"', params: {'type': '文本', 'key': '标题', 'ctype': '搜索'});
      if (name == null) continue;
      String remarks = autoContent.splitStr(item, ['搜索副标题', '副标题'], params: {'type': '文本', 'key': '标题', 'ctype': '搜索'}) ?? '';
      if (remarks.isNotEmpty) remarks = remarks.replaceAll(RegExp(r'[<>]'), '');
      var pic = autoContent.splitStr(item, ['搜索图片', '图片'], params: {'type': '图片', 'key': '图片', 'host': host, 'ctype': '搜索'}) ?? '';
      var id = autoContent.splitStr(item, ['搜索链接', '链接'], def: 'href="&&"', params: {'host': host, 'ctype': '搜索'});
      if (id != null) {
        final (ihost, getUrl) = _prefixORsuffix(item, '搜索', host);
        id = getUrl(id);
      }
      if (id != null && id.isNotEmpty) {
        list.add({
          'vod_id': '搜索\$$id@@$name@@$pic',
          'vod_name': name,
          'vod_pic': pic,
          'vod_remarks': remarks,
        });
      }
    }
    final dedup = removeDuplicatesByValue(list, 'vod_id');
    final filtered = dedup.where((v) => !(v['vod_name'] as String).contains('首页') && !(v['vod_id'] as String).contains(';')).toList();

    // 改为返回 Map 列表（与 T4/drpy2 一致）
    final videos = filtered.map((v) {
      return {
        'vod_id': v['vod_id']?.toString() ?? '',
        'vod_name': v['vod_name']?.toString() ?? '',
        'vod_pic': v['vod_pic']?.toString() ?? '',
        'vod_remarks': v['vod_remarks']?.toString() ?? '',
        'vod_blurb': v['vod_blurb']?.toString() ?? '',
        'vod_tag': v['vod_tag']?.toString() ?? 'file',
      };
    }).toList();

    return {
      'list': videos,
      'page': page,
      'pagecount': videos.isNotEmpty ? 999 : 0,
      'total': videos.isNotEmpty ? 999 : 0,
    };
  }

  @override
  Future<VideoDetail?> getDetail({required String vodId, required String pwd}) async {
    final result = await fetchDetail(vodId);
    final list = result['list'] as List?;
    if (list != null && list.isNotEmpty) {
      final v = list[0] as Map<String, dynamic>;
      
      // ===== 添加日志 =====
      print('========== getDetail 调试 ==========');
      print('v keys: ${v.keys}');
      print('vod_play_from 类型: ${v['vod_play_from'].runtimeType}');
      print('vod_play_from 值: ${v['vod_play_from']}');
      print('vod_play_url 类型: ${v['vod_play_url'].runtimeType}');
      print('vod_play_url 值: ${v['vod_play_url']}');
      print('=======================================');
      
      // 防御性修复：确保 vod_play_from 和 vod_play_url 是 String
      if (v['vod_play_from'] is List) {
        v['vod_play_from'] = (v['vod_play_from'] as List).join(r'$$$');
      }
      if (v['vod_play_url'] is List) {
        v['vod_play_url'] = (v['vod_play_url'] as List).join(r'$$$');
      }
      return VideoDetail.fromJson(v);
    }
    return null;
  }

  @override
  Future<PlayUrl?> getPlayUrl({required String playParams, required String flag, required String pwd}) async {
    final result = await fetchPlayUrl(playParams, flag: flag);
    return PlayUrl.fromJson(result);
  }

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    // 用于外部切换时重置状态
  }
}