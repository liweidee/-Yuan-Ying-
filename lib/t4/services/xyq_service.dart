import 'package:dio/dio.dart';
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

class XyqService extends T3JsonAdapter {
  XyqService(String id, String api, String extUrl, List<String> categories)
      : super(id, api, extUrl, categories);

  @override
  Future<void> init() async {
    await loadConfig();
    final host = _getHome(getRuleValue(['分类链接']) ?? getRuleValue(['首页推荐链接']) ?? '');
    rule['host'] = host;
    if (getRuleValue(['链接是否直接播放']) == '1') {
      rule['二级'] = '*';
    }

    // 处理请求头参数
    final headerStr = getRuleValue(['请求头参数'], '电脑');
    Map<String, String> headers = {};
    // 如果包含 # 或 $，则按键值对解析
    if (headerStr.contains('#') || headerStr.contains('\$')) {
      headers = _parseStringToObject(headerStr);
    } else {
      // 否则视为单纯的 UA 字符串
      headers['User-Agent'] = headerStr;
    }

    // 处理 UA 值，替换为完整 UA
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

    // 存入 rule
    rule['headers'] = headers;
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

  // ---------- 筛选生成（仅当筛选数据为 ext） ----------
  List<Map<String, dynamic>> _generateFilters(String cateId, String typeId) {
    final filters = <Map<String, dynamic>>[];
    final types = ['子分类', '类型', '地区', '年份', '语言', '排序'];
    final keys = ['cateId', 'class', 'area', 'year', 'lang', 'by'];
    for (int i = 0; i < types.length; i++) {
      final nameKey = '筛选${types[i]}名称';
      final idKey = '筛选${types[i]}替换词';
      String names = getRuleValue([nameKey]);
      String ids = getRuleValue([idKey]);
      if (names.isEmpty || ids.isEmpty) continue;
      // 支持按分类分离
      final nameList = names.split('||');
      final idList = ids.split('||');
      String targetNames = '';
      String targetIds = '';
      // 尝试匹配当前分类
      for (int j = 0; j < nameList.length; j++) {
        if (j < idList.length) {
          // 若该分类有独立筛选，且分类ID匹配
          // 这里简化：若只有一个，则通用
          if (nameList.length == 1) {
            targetNames = nameList[0];
            targetIds = idList[0];
          } else {
            // 复杂情况需映射，简化为全部
            targetNames = nameList[0];
            targetIds = idList[0];
          }
        }
      }
      if (targetNames.isEmpty) continue;
      final nameParts = targetNames.split('&');
      final idParts = targetIds.split('&');
      final items = <Map<String, String>>[];
      for (int k = 0; k < nameParts.length; k++) {
        items.add({
          'n': nameParts[k],
          'v': idParts.length > k ? idParts[k] : '',
        });
      }
      if (items.isNotEmpty && items[0]['n'] != '全部' && keys[i] != 'by') {
        items.insert(0, {'n': '全部', 'v': ''});
      }
      filters.add({
        'key': keys[i],
        'name': types[i],
        'value': items,
      });
    }
    return filters;
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    final typenames = getRuleValue(['分类名称']).split('&');
    final typeids = getRuleValue(['分类名称替换词']).split('&');
    final classes = <Map<String, dynamic>>[];
    for (int i = 0; i < typenames.length && i < typeids.length; i++) {
      classes.add({'type_id': typeids[i], 'type_name': typenames[i]});
    }
    final filtered = classes.where((c) => !categories.contains(c['type_name'])).toList();
    final seen = <String>{};
    final unique = filtered.where((c) {
      final id = c['type_id'].toString();
      if (seen.contains(id)) return false;
      seen.add(id);
      return true;
    }).toList();

    final filters = <String, dynamic>{};
    if (getRuleValue(['筛选数据']) == 'ext') {
      for (final c in unique) {
        final tid = c['type_id'].toString();
        final fl = _generateFilters(c['type_name'], tid);
        if (fl.isNotEmpty) filters[tid] = fl;
      }
    }

    // --- 新增：获取首页推荐列表 ---
    final homeUrl = getRuleValue(['首页推荐链接']);
    List<Map<String, dynamic>> homeList = [];
    if (homeUrl.isNotEmpty) {
      final html = await req(homeUrl);
      final listArr = T3Parser.pdfa(html, getRuleValue(['首页列表数组规则']));
      for (final item in listArr) {
        final subItems = T3Parser.pdfa(item, getRuleValue(['首页片单列表数组规则']));
        for (final sub in subItems) {
          final name = T3Parser.pdfh(sub, getRuleValue(['首页片单标题']));
          final id = T3Parser.pd(sub, getRuleValue(['首页片单链接']), baseUrl: _getHome(homeUrl));
          final pic = T3Parser.pdfh(sub, getRuleValue(['首页片单图片']));
          final remarks = T3Parser.pdfh(sub, getRuleValue(['首页片单副标题']));
          if (id.isNotEmpty && name.isNotEmpty) {
            homeList.add({
              'vod_id': id,
              'vod_name': name,
              'vod_pic': pic,
              'vod_remarks': remarks,
            });
          }
        }
      }
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
    var url = getRuleValue(['分类链接']);
    final host = _getHome(url);
    final Map<String, dynamic> extend =
        ext != null ? jsonDecode(ext) as Map<String, dynamic> : <String, dynamic>{};
    extend['cateId'] = cateId;
    extend['catePg'] = page.toString();
    extend['class'] = extend['class'] ?? '';
    extend['area'] = extend['area'] ?? '';
    extend['year'] = extend['year'] ?? '';
    extend['by'] = extend['by'] ?? '';
    extend['lang'] = extend['lang'] ?? '';
    extend['letter'] = extend['letter'] ?? '';

    if (url.contains('firstPage=') && page == 1) {
      final match = RegExp(r'firstPage=([^\]]*)\]').firstMatch(url);
      if (match != null) {
        url = match.group(1)!;
      }
    } else {
      url = url.split('[')[0];
    }
    url = Jinja.render(
      url.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) => '{{${match.group(1)}}}'),
      extend,
    );
    if (url.isEmpty) {
      print('fetchCate: URL 为空，返回空列表');
      return {'list': [], 'page': page, 'pagecount': 0, 'total': 0};
    }
    if (!url.startsWith('http')) {
      if (host.isNotEmpty) url = host + (url.startsWith('/') ? '' : '/') + url;
    }
    // 获取 HTML
    String html = await req(url);
    final list = <Map<String, dynamic>>[];
    final isJsoup = getRuleValue(['分类片单是否Jsoup写法']) == '1' || getRuleValue(['分类片单是否Jsoup写法']) == '是';
    if (isJsoup) {
      final listArr = T3Parser.pdfa(html, getRuleValue(['分类列表数组规则']));
      for (final item in listArr) {
        final name = T3Parser.pdfh(item, getRuleValue(['分类片单标题']));
        final id = T3Parser.pd(item, getRuleValue(['分类片单链接']), baseUrl: host);
        final pic = T3Parser.pdfh(item, getRuleValue(['分类片单图片']));
        final remarks = T3Parser.pdfh(item, getRuleValue(['分类片单副标题']));
        if (id.isNotEmpty && name.isNotEmpty) {
          list.add({
            'vod_id': id,
            'vod_name': name,
            'vod_pic': pic,
            'vod_remarks': remarks,
          });
        }
      }
    } else {
      // JSON 模式
      final mode = getRuleValue(['分类截取模式']);
      if (mode == '0') {
        String jsonStr = html;
        final secondCut = getRuleValue(['分类Json数据二次截取']);
        if (secondCut.isNotEmpty) {
          jsonStr = XBPQParse.getHasRuleSplitStr(html, secondCut, complete: true) ?? html;
        }
        try {
          final jsonData = JSON5.parse(jsonStr);
          final path = getRuleValue(['分类列表数组规则']);
          final dataList = XBPQParse.getJson(jsonData, path);
          if (dataList is List) {
            for (final item in dataList) {
              String id = item[getRuleValue(['分类片单链接'])]?.toString() ?? '';
              final name = item[getRuleValue(['分类片单标题'])]?.toString() ?? '';
              final pic = item[getRuleValue(['分类片单图片'])]?.toString() ?? '';
              final remarks = item[getRuleValue(['分类片单副标题'])]?.toString() ?? '';
              final prefix = getRuleValue(['分类片单链接加前缀']);
              final suffix = getRuleValue(['分类片单链接加后缀']);
              if (suffix.contains("'input'")) {
                id = prefix + id + suffix.replaceAll("'input'", id);
              } else {
                id = prefix + id + suffix;
              }
              if (id.isNotEmpty && name.isNotEmpty) {
                list.add({
                  'vod_id': id,
                  'vod_name': name,
                  'vod_pic': pic,
                  'vod_remarks': remarks,
                });
              }
            }
          }
        } catch (e) {
          print('JSON 解析错误: $e');
        }
      }
    }

    // 改为返回 Map 列表（与 T4/drpy2 一致）
    final videos = list.map((v) {
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
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    if (rule['二级'] == '*') {
      return {
        'list': [
          {
            'vod_id': ids,
            'vod_name': '',
            'vod_play_url': ids.contains('\$') ? ids : '直接播放\$$ids',
            'vod_play_from': '嗅探',
          }
        ]
      };
    }
    final html = await req(ids);
    final isJsoup = getRuleValue(['详情是否Jsoup写法']) == '1' || getRuleValue(['详情是否Jsoup写法']) == '是';
    Map<String, dynamic> video = {};
    if (isJsoup) {
      video = {
        'vod_remarks': T3Parser.pdfh(html, getRuleValue(['类型详情'])),
        'vod_content': T3Parser.pdfh(html, getRuleValue(['简介详情'])),
        'vod_actor': T3Parser.pdfh(html, getRuleValue(['演员详情'])),
        'vod_year': T3Parser.pdfh(html, getRuleValue(['年代详情'])),
        'vod_area': T3Parser.pdfh(html, getRuleValue(['地区详情'])),
      };
    } else {
      final actor = XBPQParse.getHasRuleSplitStr(html, getRuleValue(['演员详情']));
      final director = XBPQParse.getHasRuleSplitStr(html, getRuleValue(['导演详情']));
      video = {
        'vod_remarks': T3Parser.pdfh(XBPQParse.getHasRuleSplitStr(html, getRuleValue(['类型详情'])) ?? '', 'Text'),
        'vod_content': T3Parser.pdfh(XBPQParse.getHasRuleSplitStr(html, getRuleValue(['简介详情'])) ?? '', 'Text'),
        'vod_actor': actor != null ? T3Parser.pdfh(actor, 'Text') : '',
        'vod_director': director != null ? T3Parser.pdfh(director, 'Text') : '',
        'vod_year': XBPQParse.getHasRuleSplitStr(html, getRuleValue(['年代详情'])) ?? '',
        'vod_area': XBPQParse.getHasRuleSplitStr(html, getRuleValue(['地区详情'])) ?? '',
      };
    }

    // 线路
    List<String> tabs = [];
    final lineRule = getRuleValue(['线路列表数组规则']);
    if (lineRule.isNotEmpty) {
      final lineItems = T3Parser.pdfa(html, lineRule);
      for (final item in lineItems) {
        String lineName = '';
        final titleRules = getRuleValue(['线路标题']).split('+');
        for (final rule in titleRules) {
          if (rule == '_') lineName += '_';
          else lineName += T3Parser.pdfh(item, rule);
        }
        if (lineName.isNotEmpty) tabs.add(lineName);
      }
    }
    if (tabs.isEmpty) tabs = ['线路1'];

    // 播放列表
    final playListArr = T3Parser.pdfa(html, getRuleValue(['播放列表数组规则']));
    final allPlays = <String>[];
    for (int i = 0; i < playListArr.length; i++) {
      final cont = playListArr[i];
      var bfline = T3Parser.pdfa(cont, 'body&&${getRuleValue(['选集列表数组规则'])}');
      if (bfline.isEmpty) bfline = [cont];
      var plays = <String>[];
      for (int j = 0; j < bfline.length; j++) {
        String title = T3Parser.pdfh(bfline[j], getRuleValue(['选集标题']) ?? 'a&&Text');
        if (title.isEmpty) title = (j + 1).toString();
        String url = getRuleValue(['选集链接加前缀']) + T3Parser.pdfh(bfline[j], getRuleValue(['选集链接']) ?? 'a&&href') + getRuleValue(['选集链接加后缀']);
        plays.add('$title\$$url');
      }
      if (getRuleValue(['是否反转选集序列']) == '1') plays = plays.reversed.toList();
      if (plays.isNotEmpty) allPlays.add(plays.join('#'));
    }

    video['vod_play_from'] = tabs.join(r'$$$');
    video['vod_play_url'] = allPlays.join(r'$$$');
    return {'list': [video]};
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) async {
    int parse = RegExp(r'\.(?:m3u8|mp4|mpd|flv|mkv)').hasMatch(play) ? 0 : 1;
    return {'url': play, 'parse': parse};
  }

  @override
  Future<Map<String, dynamic>> search(String wd, int page, {int quick = 0}) async {
    String url = getRuleValue(['搜索链接']).replaceAll('{wd}', wd).replaceAll('{pg}', page.toString()).replaceAll('{SearchPg}', page.toString());
    String host = rule['host'] ?? '';
    if (host.isEmpty) host = _getHome(url);
    Map<String, String> headers = {};
    final extraHeaders = getRuleValue(['搜索请求头参数']);
    if (extraHeaders.isNotEmpty && extraHeaders.contains('#')) {
      final parsed = _parseStringToObject(extraHeaders);
      if (parsed.isNotEmpty) headers.addAll(parsed);
    }
    headers['User-Agent'] = rule['headers']['User-Agent'] ?? '';

    String html = '';
    final postData = getRuleValue(['POST请求数据']);
    if (postData.isNotEmpty) {
      final data = postData.replaceAll('{wd}', wd).replaceAll('{pg}', page.toString());
      final resp = await dio.post(url, data: data, options: Options(headers: headers));
      html = resp.data is String ? resp.data : jsonEncode(resp.data);
    } else {
      html = await req(url, headers: headers);
    }

    final list = <Map<String, dynamic>>[];
    final isJsoup = getRuleValue(['搜索片单是否Jsoup写法']) == '1' || getRuleValue(['搜索片单是否Jsoup写法']) == '是';
    final items = T3Parser.pdfa(html, getRuleValue(['搜索列表数组规则']));
    for (final item in items) {
      String title = '';
      String href = '';
      String pic = '';
      String desc = '';
      if (isJsoup) {
        title = T3Parser.pdfh(item, getRuleValue(['搜索片单标题']));
        href = getRuleValue(['搜索片单链接加前缀']) + T3Parser.pdfh(item, getRuleValue(['搜索片单链接'])) + getRuleValue(['搜索片单链接加后缀']);
        pic = T3Parser.pdfh(item, getRuleValue(['搜索片单图片']));
        desc = T3Parser.pdfh(item, getRuleValue(['搜索片单副标题']));
      } else {
        title = XBPQParse.getHasRuleSplitStr(item, getRuleValue(['搜索片单标题'])) ?? '';
        href = XBPQParse.getHasRuleSplitStr(item, getRuleValue(['搜索片单链接'])) ?? '';
        pic = XBPQParse.getHasRuleSplitStr(item, getRuleValue(['搜索片单图片'])) ?? '';
        if (pic.startsWith('/')) pic = host + pic;
      }
      if (href.isNotEmpty && title.isNotEmpty) {
        list.add({
          'vod_id': href,
          'vod_name': title,
          'vod_pic': pic,
          'vod_remarks': desc,
        });
      }
    }

    // 改为返回 Map 列表（与 T4/drpy2 一致）
    final videos = list.map((v) {
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
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {}
}