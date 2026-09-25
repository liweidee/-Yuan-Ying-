import 'dart:convert';

import '../utils/lx_logger.dart';
import '../utils/lx_sign_utils.dart';
import 'lx_http.dart';

/// 热搜词服务
class LxHotSearchService {
  LxHotSearchService._();
  static final LxHotSearchService instance = LxHotSearchService._();

  final Map<String, List<String>> _cache = {};
  final Map<String, DateTime> _cacheTime = {};
  static const _cacheTtl = Duration(minutes: 10);

  Future<List<String>> getHotSearch(String source) async {
    final cached = _getCached(source);
    if (cached != null) return cached;

    List<String> list;
    switch (source) {
      case 'kw':
        list = await _kwHotSearch();
        break;
      case 'kg':
        list = await _kgHotSearch();
        break;
      case 'tx':
      case 'wy':
        return const [];
      default:
        list = await _kwHotSearch();
        break;
    }
    if (list.isEmpty) return const [];
    _cache[source] = list;
    _cacheTime[source] = DateTime.now();
    return list;
  }

  List<String>? _getCached(String source) {
    final time = _cacheTime[source];
    if (time == null) return null;
    if (DateTime.now().difference(time) > _cacheTtl) {
      _cache.remove(source);
      _cacheTime.remove(source);
      return null;
    }
    return _cache[source];
  }

  Future<List<String>> _kwHotSearch() async {
    try {
      final resp = await LxHttp.dio.get<String>(
        'http://hotword.kuwo.cn/hotword.s?prod=kwplayer_ar_9.3.0.1&corp=kuwo&newver=2&vipver=9.3.0.1&source=kwplayer_ar_9.3.0.1_40.apk&p2p=1&notrace=0&uid=0&plat=kwplayer_ar&rformat=json&encoding=utf8&tabid=1',
        options: LxHttp.options(
          timeout: const Duration(seconds: 8),
          headers: {'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 9;)'},
        ),
      );

      if (resp.statusCode != 200) {
        throw Exception('获取热搜词失败');
      }
      final body = jsonDecode(resp.data ?? '{}');
      if (body['status'] != 'ok') {
        throw Exception('获取热搜词失败');
      }
      final tags = body['tagvalue'] as List? ?? [];
      return tags
          .map((t) => t['key']?.toString() ?? '')
          .where((k) => k.isNotEmpty)
          .toList();
    } catch (e) {
      LxLogger.warn('酷我热搜失败: $e');
      return const [];
    }
  }

  Future<List<String>> _kgHotSearch() async {
    try {
      final resp = await LxHttp.dio.get<String>(
        'http://gateway.kugou.com/api/v3/search/hot_tab?signature=ee44edb9d7155821412d220bcaf509dd&appid=1005&clientver=10026&plat=0',
        options: LxHttp.options(
          timeout: const Duration(seconds: 8),
          headers: {
            'dfid': '1ssiv93oVqMp27cirf2CvoF1',
            'mid': '156798703528610303473757548878786007104',
            'clienttime': '1584257267',
            'x-router': 'msearch.kugou.com',
            'user-agent':
                'Android9-AndroidPhone-10020-130-0-searchrecommendprotocol-wifi',
            'kg-rc': '1',
          },
        ),
      );

      if (resp.statusCode != 200) {
        throw Exception('获取热搜词失败');
      }
      final body = jsonDecode(resp.data ?? '{}');
      if (body['errcode'] != 0) {
        throw Exception('获取热搜词失败');
      }
      final list = body['data']?['list'] as List? ?? [];
      final result = <String>[];
      for (final item in list) {
        final keywords = item['keywords'] as List? ?? [];
        for (final k in keywords) {
          final word =
              LxSignUtils.decodeHtml(k['keyword']?.toString() ?? '');
          if (word.isNotEmpty) result.add(word);
        }
      }
      return result;
    } catch (e) {
      LxLogger.warn('酷狗热搜失败: $e');
      return const [];
    }
  }
}