import 'dart:convert';

import '../utils/lx_logger.dart';
import '../utils/lx_sign_utils.dart';
import 'lx_http.dart';

/// 搜索联想服务
class LxSearchSuggestService {
  LxSearchSuggestService._();
  static final LxSearchSuggestService instance = LxSearchSuggestService._();

  static const Set<String> _supportedSources = {'kw', 'kg', 'tx', 'wy'};

  bool supports(String source) => _supportedSources.contains(source);

  Future<List<String>> getSuggestions(String source, String keyword) async {
    if (keyword.trim().isEmpty) return const [];
    try {
      switch (source) {
        case 'all':
          return await _allSuggest(keyword);
        case 'kw':
          return await _kwSuggest(keyword);
        case 'kg':
          return await _kgSuggest(keyword);
        case 'tx':
          return await _txSuggest(keyword);
        case 'wy':
          return await _wySuggest(keyword);
        default:
          return const [];
      }
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _allSuggest(String keyword) async {
    final results = await Future.wait([
      _kwSuggest(keyword).catchError((_) => const <String>[]),
      _kgSuggest(keyword).catchError((_) => const <String>[]),
      _txSuggest(keyword).catchError((_) => const <String>[]),
      _wySuggest(keyword).catchError((_) => const <String>[]),
    ]);
    final seen = <String>{};
    final merged = <String>[];
    for (final list in results) {
      for (final w in list) {
        if (w.isNotEmpty && seen.add(w)) merged.add(w);
      }
    }
    return merged.take(15).toList();
  }

  Future<List<String>> _kwSuggest(String keyword) async {
    final resp = await LxHttp.dio.get<String>(
      'https://tips.kuwo.cn/t.s?corp=kuwo&newver=3&p2p=1&notrace=0&c=mbox&w=${Uri.encodeComponent(keyword)}&encoding=utf8&rformat=json',
      options: LxHttp.options(
        timeout: const Duration(seconds: 5),
        headers: {'Referer': 'http://www.kuwo.cn/'},
      ),
    );

    if (resp.statusCode != 200) return const [];
    final body = jsonDecode(resp.data ?? '{}');
    final wordItems = body['WORDITEMS'] as List? ?? [];
    return wordItems
        .map((item) => item['RELWORD']?.toString() ?? '')
        .where((w) => w.isNotEmpty)
        .toList();
  }

  Future<List<String>> _kgSuggest(String keyword) async {
    final resp = await LxHttp.dio.get<String>(
      'https://searchtip.kugou.com/getSearchTip?MusicTipCount=10&keyword=${Uri.encodeComponent(keyword)}',
      options: LxHttp.options(
        timeout: const Duration(seconds: 5),
        headers: {'Referer': 'https://www.kugou.com/'},
      ),
    );

    if (resp.statusCode != 200) return const [];
    final body = jsonDecode(resp.data ?? '{}');
    if (body['status'] != 1 && body['error_code'] != 0) return const [];
    final data = body['data'] as List? ?? [];
    final result = <String>[];
    for (final d in data) {
      final records = d['RecordDatas'] as List? ?? [];
      for (final record in records) {
        final hint =
            LxSignUtils.decodeHtml(record['HintInfo']?.toString() ?? '');
        if (hint.isNotEmpty) result.add(hint);
      }
    }
    return result;
  }

  Future<List<String>> _txSuggest(String keyword) async {
    final resp = await LxHttp.dio.get<String>(
      'https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg?is_xml=0&format=json&key=${Uri.encodeComponent(keyword)}&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq&needNewCode=0',
      options: LxHttp.options(
        timeout: const Duration(seconds: 5),
        headers: {'Referer': 'https://y.qq.com/portal/player.html'},
      ),
    );

    if (resp.statusCode != 200) return const [];
    final body = jsonDecode(resp.data ?? '{}');
    if (body['code'] != 0) return const [];
    final song = body['data']?['song'] as Map? ?? {};
    final itemlist = song['itemlist'] as List? ?? [];
    return itemlist
        .map((info) {
          final name = info['name']?.toString() ?? '';
          final singer = info['singer']?.toString() ?? '';
          return singer.isNotEmpty ? '$name - $singer' : name;
        })
        .where((w) => w.isNotEmpty)
        .toList();
  }

  Future<List<String>> _wySuggest(String keyword) async {
    final resp = await LxHttp.dio.get<String>(
      'https://music.163.com/api/search/suggest/web?s=${Uri.encodeComponent(keyword)}',
      options: LxHttp.options(
        timeout: const Duration(seconds: 5),
        headers: {
          'Referer': 'https://music.163.com/',
          'Cookie': 'appver=8.7.01',
        },
      ),
    );

    if (resp.statusCode != 200) return const [];
    final body = jsonDecode(resp.data ?? '{}');
    final songs = body['result']?['songs'] as List? ?? [];
    return songs
        .map((info) {
          final name = info['name']?.toString() ?? '';
          final singers = (info['artists'] as List? ?? [])
              .map((a) => a['name']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .join('、');
          return singers.isNotEmpty ? '$name - $singers' : name;
        })
        .where((w) => w.isNotEmpty)
        .toList();
  }
}