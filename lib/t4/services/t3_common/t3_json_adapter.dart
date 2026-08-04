import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:json5/json5.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:enough_convert/enough_convert.dart';
import 'package:brotli/brotli.dart';
import 'package:yuanying/http/init.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/t4/services/t3_common/t3_parser.dart';
import 'package:yuanying/t4/services/t3_common/t3_rule_parse.dart';
import 'package:yuanying/t4/services/t3_common/t3_utils.dart';
import 'package:yuanying/t4/services/t3_common/t3_jinja.dart';
import 'package:yuanying/t4/services/t3_common/t3_default_rules.dart';

abstract class T3JsonAdapter implements ISpiderService {
  final String id;
  final String api;
  final String extUrl;
  final List<String> categories;
  Map<String, dynamic> rule = {};
  Map<String, dynamic> config = {};
  String target = '';
  final Dio dio = HttpClientFactory.dio;

  T3JsonAdapter(this.id, this.api, this.extUrl, this.categories);

  @override
  String? get currentKey => id;

  @override
  void setBaseUrl(String url) {}

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    // 子类可重写
  }

  // ---------- 配置加载 ----------
  Future<void> loadConfig() async {
    try {
      final response = await dio.get(
        extUrl,
        options: Options(responseType: ResponseType.plain), // 强制获取原始字符串
      );
      if (response.statusCode == 200) {
        String rawData = response.data as String? ?? '';
        // 去除 UTF-8 BOM 头
        if (rawData.startsWith('\uFEFF')) {
          rawData = rawData.substring(1);
        }
        // 解析 JSON5（支持注释、尾随逗号等）
        final decoded = JSON5.parse(rawData);
        if (decoded is Map) {
          config = Map<String, dynamic>.from(decoded);
        } else {
          print('JSON5 解析结果不是 Map 类型，原始数据前100字符: ${rawData.substring(0, rawData.length > 100 ? 100 : rawData.length)}');
        }
      }
    } catch (e) {
      print('加载 T3 配置失败: $e');
      // 不抛出异常，避免影响整体流程，但 config 将为空
    }
  }

  String getRuleValue(List<String> keys, [String def = '']) {
    for (final key in keys) {
      if (config.containsKey(key)) {
        final value = config[key];
        if (value != null) return value.toString();
      }
    }
    return def;
  }

  // ---------- 网络请求（支持时间戳、md5、POST） ----------
  String _md5(String input) {
    final bytes = utf8.encode(input);
    final digest = crypto.md5.convert(bytes);
    return digest.toString();
  }

  Future<String> req(String url, {Map<String, String>? headers}) async {
    // ---- 替换时间戳 ----
    if (url.contains('时间戳')) {
      url = url.replaceAll('时间戳', DateTime.now().millisecondsSinceEpoch.toString());
    }
    // ---- 替换 md5(内容) ----
    if (url.contains('md5(')) {
      final regex = RegExp(r'md5\((.*?)\)');
      url = url.replaceAllMapped(regex, (m) {
        final content = m.group(1)!;
        return _md5(content);
      });
    }
    // ---- 补全协议 ----
    if (!url.startsWith('http')) {
      final host = rule['host'] as String? ?? '';
      if (host.isNotEmpty) {
        url = host + (url.startsWith('/') ? '' : '/') + url;
      }
    }
    // ---- 处理 POST ----
    bool isPost = false;
    String postData = '';
    if (url.contains(';post')) {
      final parts = url.split(';');
      url = parts[0];
      if (parts.length > 2) postData = parts[2];
      isPost = true;
    }

    print('========== T3 REQUEST ==========');
    print('URL: $url');
    print('Method: ${isPost ? 'POST' : 'GET'}');
    print('Headers: ${headers ?? rule['headers']}');
    if (isPost) print('Body: $postData');

    // ===== 根据 id 计算来源类型 =====
    String _getSourceType() {
      // id 是站点 key，如 'xbpq_xxx' 或 'xyq_xxx'
      if (id.startsWith('xbpq_')) return 'xbpq';
      if (id.startsWith('xyq_')) return 'xyq';
      return 't3';  // 普通 T3 爬虫（如有）
    }

    try {
      final response = await dio.request(
        url,
        options: Options(
          method: isPost ? 'POST' : 'GET',
          headers: headers ?? rule['headers'] as Map<String, String>?,
          responseType: ResponseType.bytes,
          extra: {'source': _getSourceType()},
        ),
        data: isPost ? postData : null,
      );

      if (response.statusCode == 200) {
        List<int> rawBytes = response.data as List<int>;

        // ---- 获取 Content-Encoding ----
        final encodingHeader = response.headers['content-encoding']?.first ?? '';

        // ---- 解压缩（gzip / brotli） ----
        List<int> decodedBytes;
        if (encodingHeader.contains('gzip')) {
          try {
            final codec = GZipCodec();
            decodedBytes = codec.decode(rawBytes);
            print('gzip decompressed, length: ${decodedBytes.length}');
          } catch (e) {
            print('gzip decompress failed, fallback to raw: $e');
            decodedBytes = rawBytes;
          }
        } else if (encodingHeader.contains('br')) {
          try {
            // brotli: ^0.6.0 使用 brotliDecode 顶层函数
            decodedBytes = brotliDecode(rawBytes);
            print('Brotli decompressed, length: ${decodedBytes.length}');
          } catch (e) {
            print('Brotli decompress failed, fallback to raw: $e');
            decodedBytes = rawBytes;
          }
        } else {
          decodedBytes = rawBytes;
        }

        // ---- 编码转换（GBK / UTF-8） ----
        String encoding = getRuleValue(['网页编码格式', '编码', 'Coding_format'], 'UTF-8').toUpperCase();
        String rawData;
        if (encoding == 'GBK' || encoding == 'GB2312') {
          try {
            final codec = const GbkCodec(allowInvalid: true);
            rawData = codec.decode(decodedBytes);
            print('GBK/GB2312 decoded, length: ${rawData.length}');
          } catch (e) {
            print('GBK decode failed, fallback to utf8: $e');
            rawData = utf8.decode(decodedBytes, allowMalformed: true);
          }
        } else {
          rawData = utf8.decode(decodedBytes, allowMalformed: true);
        }

        print('========== T3 RESPONSE ==========');
        print('Status: ${response.statusCode}');
        print('Headers: ${response.headers}');
        print('Body length: ${rawData.length}');
        print('Body (first 500 chars): ${rawData.substring(0, rawData.length > 500 ? 500 : rawData.length)}');

        // ---- 清理 JSONP 包裹 ----
        final jsonpRegex = RegExp(r'^\s*[a-zA-Z_$][\w$]*\s*\(([\s\S]*)\)\s*;?\s*$');
        final match = jsonpRegex.firstMatch(rawData);
        if (match != null) {
          rawData = match.group(1)!;
          print('JSONP cleaned, new length: ${rawData.length}');
        }

        // ---- 统一替换 JSON 中转义的斜杠 ----
        rawData = rawData.replaceAll(r'\/', '/');

        return rawData;
      }
      print('Request failed with status: ${response.statusCode}');
      return '';
    } catch (e) {
      print('========== T3 REQUEST ERROR ==========');
      print('Error: $e');
      print('URL: $url');
      return '';
    }
  }

  // ---------- 一级列表解析 ----------
  Future<List<Map<String, dynamic>>> parseLevelOne(String url, String ctype) async {
    if (url.isEmpty) {
      print('parseLevelOne: url 为空，跳过');
      return [];
    }
    if (url.startsWith('://')) {
      final host = rule['host'] ?? '';
      if (host.isNotEmpty && Uri.tryParse(host)?.scheme != null) {
        final scheme = Uri.parse(host).scheme;
        url = '$scheme:$url';
      } else {
        url = 'https:$url';
      }
    }
    print('parseLevelOne url: $url');
    final html = await req(url);
    if (html.isEmpty) return [];

    if (ctype == '首页' && getRuleValue(['搜索url']).isEmpty) {
      final s = loopTest(html, '文本', '搜索');
      if (s != null && searchmap.containsKey(s)) {
        config['搜索url'] = searchmap[s];
        print('搜索url设置: ${searchmap[s]}');
      }
    }

    final host = _getHome(url);
    final autoContent = this.autoContent;
    var ehtml = html;
    if (autoContent.isEmpty(['二次截取', '数组二次截取'])) {
      ehtml = autoContent.splitStr(html, ['二次截取', '数组二次截取'],
          params: {'twice': true, 'ctype': ctype}) ?? html;
    }

    final (ihost, getUrl) = _prefixORsuffix(html, '', host);
    final htmlList = autoContent.splitArray(ehtml, ['数组'],
        params: {'key': '数组', 'ctype': ctype});
    print('parseLevelOne: htmlList 长度 = ${htmlList.length}');
    if (htmlList.isNotEmpty) {
      print('parseLevelOne: 第一个元素前200字符 = ${htmlList[0].substring(0, htmlList[0].length > 200 ? 200 : htmlList[0].length)}');
    }

    final list = <Map<String, dynamic>>[];
    int hasPic = 0;

    const int detailLimit = 3; // 只详细打印前3条

    for (int idx = 0; idx < htmlList.length; idx++) {
      final item = htmlList[idx];
      final bool verbose = (idx < detailLimit);

      if (verbose) {
        print('========== 处理第 $idx 个 item ==========');
        print('item 完整内容（前500字符）: ${item.substring(0, item.length > 500 ? 500 : item.length)}');
      }

      // ----- 标题 -----
      final vodName = autoContent.splitStr(item, ['标题'],
          params: {'type': '文本', 'key': '标题', 'ctype': ctype});
      if (verbose) print('标题规则结果: "$vodName"');
      if (vodName == null || vodName.isEmpty) {
        if (verbose) print('标题为空，跳过此item');
        continue;
      }

      // ----- 副标题 -----
      final vodRemarks = autoContent.splitStr(item, ['副标题'],
          params: {'type': '文本', 'key': '副标题'});
      if (verbose) print('副标题结果: "$vodRemarks"');

      // ----- 链接 -----
      var vodId = autoContent.splitStr(item, ['链接'],
          def: 'href="&&"',
          params: {'host': ihost, 'type': '链接', 'key': '链接', 'ctype': ctype});
      if (verbose) print('链接原始结果: "$vodId"');
      if (vodId != null) vodId = getUrl(vodId);
      if (verbose) print('链接处理后: "$vodId"');
      if (vodId != null && _judgeUrl(vodId, vodName, host, '一级')) {
        if (verbose) print('链接被 _judgeUrl 过滤');
        continue;
      }

      // ----- 图片 -----
      var vodPic = autoContent.splitStr(item, ['图片'],
          params: {'type': '图片', 'key': '图片', 'host': host, 'ctype': ctype});
      if (verbose) print('图片结果: "$vodPic"');
      if (vodPic != null && vodPic.isNotEmpty) {
        // 不添加 @Referer=
        hasPic++;
      }

      final vodData = {
        'vod_ids': '$ctype\$$vodId@@$vodName@@$vodPic',
        'vod_id': vodId,
        'vod_name': vodName,
        'vod_pic': vodPic,
        'vod_remarks': vodRemarks,
      };
      if (verbose) {
        print('添加到列表: vod_id="$vodId", vod_name="$vodName"');
        print('完整 vodData: $vodData');
      }
      list.add(vodData);
    }

    print('========== 循环结束 ==========');
    print('list 原始长度: ${list.length}');
    print('hasPic = $hasPic');

    if (hasPic > 4) {
      final beforeRemove = list.length;
      list.removeWhere((v) => (v['vod_pic'] as String?)?.isEmpty ?? true);
      print('移除无图项后: ${list.length} (移除了 ${beforeRemove - list.length} 项)');
    }

    final dedupList = removeDuplicatesByValue(list, 'vod_id');
    print('去重后长度: ${dedupList.length}');
    var finalList = dedupList;

    if (finalList.isNotEmpty && finalList.every((item) => (item['vod_id'] as String).contains('http'))) {
      final topUrls = finalList.map((e) => e['vod_id'] as String).toList();
      final commonPath = _findMostCommonBaseStructure(topUrls);
      print('commonPath = "$commonPath"');
      final filtered = finalList.where((item) => (item['vod_id'] as String).contains(commonPath)).toList();
      if (filtered.length > 10) {
        finalList = filtered;
        print('过滤后长度: ${finalList.length} (保留包含 "$commonPath" 的项)');
      } else {
        print('过滤后长度 ${filtered.length} <= 10，保留原列表');
      }
    }

    if (finalList.isEmpty) {
      print('finalList 为空，添加占位数据');
      finalList.add({
        'vod_id': '没有数据',
        'vod_name': '无数据,防止无限请求',
        'vod_pic': 'https://ghproxy.net/https://raw.githubusercontent.com/hjdhnx/dr_py/main/404.jpg',
        'vod_remarks': '不要点，会崩的',
      });
    }

    if (finalList.isNotEmpty && finalList[0]['vod_id'] != '没有数据') {
      for (final item in finalList) {
        item['vod_id'] = item['vod_ids'];
      }
    }

    print('========== 最终返回 ==========');
    print('finalList 最终长度: ${finalList.length}');
    if (finalList.isNotEmpty) {
      print('第一条数据: vod_id="${finalList[0]['vod_id']}", vod_name="${finalList[0]['vod_name']}"');
    }

    return finalList;
  }

  AutoContent get autoContent => AutoContent(this);

  // ---------- 辅助方法 ----------
  String _getHome(String url) {
    try {
      if (url.startsWith('://')) {
        final host = rule['host'] ?? '';
        if (host.isNotEmpty) {
          final scheme = Uri.parse(host).scheme;
          return scheme + '://' + url.substring(3).split('/')[0];
        }
        return '';
      }
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return '';
    }
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

  bool _judgeUrl(String? url, String name, String host, String type) {
    if (type == '一级') {
      if (url == null) return true;
      if (name.contains('会员中心')) return true;
      if (RegExp(r'vod/type/id/\d+\.html|/label/(?:hot|down|live|web|top)\.html|user/login').hasMatch(url)) {
        return true;
      }
      if (RegExp(r'index\.php/vod/show/').hasMatch(url) &&
          RegExp(r'/id/\d+\.html').hasMatch(url)) return true;
      if (RegExp(r'detail/id/\d+\.html|voddetail', caseSensitive: false).hasMatch(url)) return false;
      if (RegExp(r'javascript:|/vod/?type/|/vod/?show/').hasMatch(url)) return true;
      if (url.replaceAll(RegExp(r'/$'), '') == host) return true;
    }
    return false;
  }

  String normalizeUrl(String url) {
    // 如果是 push:// 协议，不做任何处理，直接返回
    if (url.startsWith('push://')) {
      return url;
    }

    url = url.replaceAll(r'\/', '/').replaceAll('&#038;', '&');
    if (url.startsWith('//')) {
      final protocol = Uri.tryParse(rule['host'] ?? '')?.scheme ?? 'https';
      url = '$protocol:$url';
    }
    if (url.startsWith('/')) {
      final host = rule['host'] ?? '';
      url = host + url;
    }
    final match = RegExp(r'^((?:[a-z]+://)?[^\s/]+\.[^\s/]+)(\S*)', caseSensitive: false).firstMatch(url);
    if (match != null) {
      final protocolHost = match.group(1)!;
      final path = match.group(2) ?? '';
      return protocolHost + path.replaceAll(RegExp(r'/+'), '/');
    }
    return url;
  }

  List<String> byType(List<String> values, String ctype) {
    if (values.every((x) => x.contains('--'))) {
      final types = values.map((x) => x.split('--')[0]).toList();
      final filterType = types.contains(ctype) ? ctype : '默认';
      return values.where((x) => x.split('--')[0] == filterType).toList();
    }
    return values;
  }

  String? loopTest(String html, String type, String key, [String host = '']) {
    var content = autoRule[key];
    if (target == 'ext') {
      content = extRule[key];
      target = '';
    }
    if (content == null) return null;
    
    // 确保 content 是 List<String>
    List<String> contents;
    if (content is List) {
      contents = content.cast<String>();
    } else if (content is String) {
      contents = [content];
    } else {
      return null;
    }
    
    for (final rule in contents) {
      if (type == '数组') {
        final result = XBPQParse.getSplitArray(html, rule);
        if (result.isNotEmpty) {
          print('目标[$key]: $rule');
          return result.join('||');
        }
      } else if (type == '文本') {
        final strict = key == '播放标题';
        final result = XBPQParse.getHasRuleSplitStr(html, rule, host: host, complete: strict);
        if (result != null) {
          return collapseSpacesAndTrim(result);
        }
      } else if (type == '图片') {
        final result = XBPQParse.getHasRuleSplitStr(html, rule, host: host);
        if (result != null && !RegExp(r'logo\.gif').hasMatch(result)) {
          return collapseSpacesAndTrim(result);
        }
      } else if (type == '链接') {
        final result = XBPQParse.getHasRuleSplitStr(html, rule, host: host);
        if (result != null && !RegExp(r'javascript:;').hasMatch(result)) {
          return collapseSpacesAndTrim(result);
        }
      }
    }
    return null;
  }

  List<String> splitTextWithSingleBracket(String text) {
    final regex = RegExp(r'^([^[]*)\[(.*?)\]$');
    final match = regex.firstMatch(text);
    if (match != null) {
      return [match.group(1)! + (match.group(3) ?? ''), match.group(2)!];
    }
    return [text, ''];
  }

  void setSwitchs(String switchs) {
    final swMap = {
      'z': (_) => rule['二级'] = '*',
      'd': (str) {
        final digit = _checkDigit(str, 'd');
        if (digit != null) rule['倒序'] = digit;
      },
      'v': (_) => rule['playParse'] = 0,
    };
    for (final entry in swMap.entries) {
      if (switchs.contains(entry.key)) {
        entry.value(switchs);
      }
    }
  }

  int? _checkDigit(String str, String key) {
    final match = RegExp('$key(\\d+)').firstMatch(str);
    return match != null ? int.parse(match.group(1)!) : null;
  }

  String _findMostCommonBaseStructure(List<String> urls) {
    final pathCount = <String, int>{};
    for (final url in urls) {
      final parts = url.split('?')[0].split('/');
      if (parts.length >= 4) {
        var base = parts.sublist(3, parts.length - 1).join('/');
        if (base.contains('-')) {
          final temp = base.split('-');
          final idx = temp.indexWhere((e) => RegExp(r'\d').hasMatch(e));
          if (idx != -1) base = temp[idx];
        }
        pathCount[base] = (pathCount[base] ?? 0) + 1;
      }
    }
    if (pathCount.isEmpty) return '';
    return pathCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  // ---------- 抽象接口 ----------
  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async => {};

  @override
  Future<Map<String, dynamic>> fetchCate(String cateId, int page, {String? ext}) async => {};

  @override
  Future<Map<String, dynamic>> search(String wd, int page, {int quick = 0}) async => {};

  @override
  Future<VideoDetail?> getDetail({required String vodId, required String pwd}) async => null;

  @override
  Future<PlayUrl?> getPlayUrl({required String playParams, required String flag, required String pwd}) async => null;

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async => {};

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) async => {};

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) {
    return search(wd, page, quick: quick);
  }
}

// ---------- AutoContent 辅助类 ----------
class AutoContent {
  final T3JsonAdapter adapter;

  AutoContent(this.adapter);

  bool isEmpty(List<String> keys, [String def = '']) {
    final value = adapter.getRuleValue(keys, def);
    return value.isEmpty || value == 'null' || value == '';
  }

  String? splitStr(String html, List<String> keys, {dynamic def, Map<String, dynamic>? params}) {
    params ??= {};
    final host = params['host'] as String? ?? '';
    final type = params['type'] as String? ?? '';
    final key = params['key'] as String? ?? '';
    final twice = params['twice'] as bool? ?? false;
    final ctype = params['ctype'] as String? ?? '';
    final skey = params['skey'] as String? ?? type;

    String? value = adapter.getRuleValue(keys, '');
    if (value.isEmpty && def is String) value = def;

    // 移除所有 print 日志
    // print('splitStr: key=$key, 规则值="$value"');
    if (value.isEmpty) {
      // print('splitStr: 规则为空，返回 null');
      return null;
    }

    // 处理 || 多规则
    if (value.contains('||')) {
      final options = value.split('||');
      for (final opt in options) {
        final result = _splitStrSingle(html, opt, host, type, key, twice, ctype, skey);
        if (result != null) {
          // print('splitStr: 使用多规则 "$opt" 成功，结果="$result"');
          return result;
        }
      }
      // print('splitStr: 所有多规则均失败，返回 null');
      return null;
    }
    final result = _splitStrSingle(html, value, host, type, key, twice, ctype, skey);
    // print('splitStr: 最终结果="$result"');
    return result;
  }

  String? _splitStrSingle(String html, String rule, String host, String type, String key,
      bool twice, String? ctype, String skey) {
    // 按 -- 分类过滤
    if (rule.contains('--')) {
      final parts = rule.split('--');
      if (parts.length == 2) {
        final typePart = parts[0];
        final rulePart = parts[1];
        if (ctype != null && ctype.isNotEmpty) {
          if (typePart == ctype || typePart == '默认') {
            return _splitStrByRule(html, rulePart, host, type, key, twice, ctype, skey);
          }
          return null;
        }
        return _splitStrByRule(html, rulePart, host, type, key, twice, ctype, skey);
      }
    }
    return _splitStrByRule(html, rule, host, type, key, twice, ctype, skey);
  }

  String? _splitStrByRule(String html, String rule, String host, String type, String key,
    bool twice, String? ctype, String skey) {
    String? temp;
    // 优先处理 j: 路径
    if (rule.startsWith('j:')) {
      temp = XBPQParse.getHasRuleSplitStr(html, rule, host: host, complete: twice);
      if (temp == null && twice) temp = html;
    } else if (rule.contains('&&')) {
      temp = XBPQParse.getHasRuleSplitStr(html, rule, host: host, complete: twice);
      if (temp == null && twice) temp = html;
    } else if (rule.contains('含序号:')) {
      var prefix = '';
      var rulePart = rule;
      if (rule.contains('+')) {
        final parts = rule.split('+');
        prefix = parts[0];
        rulePart = parts[1];
      }
      final arr = XBPQParse.getSplitArray(html, rulePart);
      if (arr.isNotEmpty) {
        temp = prefix + arr[0];
      }
    } else {
      temp = XBPQParse.getJsonStr(html, rule);
    }

    if (temp != null) {
      if (skey == '文本') {
        temp = removeTagsExceptList(temp, []);
        temp = collapseSpacesAndTrim(temp);
      } else if (skey == '图片') {
        temp = adapter.normalizeUrl(temp);
      } else if (skey == '链接') {
        if (temp.startsWith('http')) {
          final uhost = adapter._getHome(temp);
          if (temp.replaceAll(RegExp(r'/$'), '') == uhost || temp.replaceAll(RegExp(r'/$'), '') == host) {
            return '';
          }
          temp = adapter.normalizeUrl(temp);
        }
      }
      return temp;
    }

    if (autoRule.containsKey(key)) {
      return adapter.loopTest(html, type, key, host);
    }
    return null;
  }

  List<String> splitArray(String html, List<String> keys, {dynamic def, Map<String, dynamic>? params}) {
    params ??= {};
    final key = params['key'] as String? ?? '';
    final ctype = params['ctype'] as String? ?? '';

    String? value = adapter.getRuleValue(keys, '');
    if (value.isEmpty && def is String) value = def;

    if (value.isEmpty) return [];
    if (value.contains('||')) {
      final options = value.split('||');
      for (final opt in options) {
        final list = _splitArrayInternal(html, opt, ctype);
        if (list.isNotEmpty) return list;
      }
    }
    return _splitArrayInternal(html, value, ctype);
  }

  List<String> _splitArrayInternal(String html, String rule, String? ctype) {
    if (rule.contains('--')) {
      final parts = rule.split('--');
      if (parts.length == 2) {
        final typePart = parts[0];
        final rulePart = parts[1];
        if (ctype != null && ctype.isNotEmpty) {
          if (typePart == ctype || typePart == '默认') {
            return XBPQParse.getSplitArray(html, rulePart);
          }
          return [];
        }
        return XBPQParse.getSplitArray(html, rulePart);
      }
    }
    return XBPQParse.getSplitArray(html, rule);
  }
}