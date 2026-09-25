import 'dart:convert';

import '../models/lx_music_model.dart';
import '../utils/lx_logger.dart';
import '../utils/lx_sign_utils.dart';
import 'lx_http.dart';

/// 洛雪音乐搜索服务（4 源）
class LxMusicSearchService {
  LxMusicSearchService._();
  static final LxMusicSearchService instance = LxMusicSearchService._();

  final Map<String, _LxSearchSource> _sources = {
    'kw': _KwSearchSource(),
    'kg': _KgSearchSource(),
    'tx': _TxSearchSource(),
    'wy': _WySearchSource(),
  };

  final Map<String, LxSearchResult> _resultCache = {};
  final Map<String, DateTime> _resultCacheTime = {};
  static const _resultCacheTtl = Duration(minutes: 2);

  static const List<String> availableSources = ['kw', 'kg', 'tx', 'wy', 'all'];

  static const Map<String, String> sourceNames = {
    'kw': '小蜗音乐',
    'kg': '小枸音乐',
    'tx': '小秋音乐',
    'wy': '小芸音乐',
    'all': '全部',
  };

  Future<LxSearchResult> search({
    required String keyword,
    required String source,
    int page = 1,
    int pageSize = 30,
  }) async {
    final cacheKey = '$source|$keyword|$page|$pageSize';
    final cachedTime = _resultCacheTime[cacheKey];
    if (cachedTime != null &&
        DateTime.now().difference(cachedTime) < _resultCacheTtl) {
      return _resultCache[cacheKey]!;
    }

    LxSearchResult result;
    if (source == 'all') {
      result = await _searchAll(
          keyword: keyword, page: page, pageSize: pageSize);
    } else {
      final searchSource = _sources[source];
      if (searchSource == null) {
        throw Exception('不支持的音源: $source');
      }
      result = await searchSource.search(
          keyword: keyword, page: page, pageSize: pageSize);
    }

    _resultCache[cacheKey] = result;
    _resultCacheTime[cacheKey] = DateTime.now();
    if (_resultCache.length > 100) {
      final expired = _resultCacheTime.entries
          .where((e) =>
              DateTime.now().difference(e.value) >= _resultCacheTtl)
          .map((e) => e.key)
          .toList();
      for (final k in expired) {
        _resultCache.remove(k);
        _resultCacheTime.remove(k);
      }
    }

    return result;
  }

  Future<LxSearchResult> _searchAll({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    final results = await Future.wait(
      _sources.entries.map((entry) async {
        try {
          return await entry.value.search(
              keyword: keyword, page: page, pageSize: pageSize);
        } catch (e) {
          LxLogger.warn('源 ${entry.key} 搜索失败: $e');
          return LxSearchResult(
              list: [],
              total: 0,
              page: page,
              pageSize: pageSize,
              source: entry.key);
        }
      }),
    );

    final allList = <LxMusic>[];
    final seenIds = <String>{};
    var total = 0;
    var anyHasMore = false;
    for (final r in results) {
      for (final item in r.list) {
        if (seenIds.add(item.id)) allList.add(item);
      }
      total += r.total;
      if (r.hasMore) anyHasMore = true;
    }

    return LxSearchResult(
      list: allList,
      total: total,
      page: page,
      pageSize: pageSize,
      source: 'all',
      hasMoreOverride: anyHasMore,
    );
  }
}

// ==================== 源基类 ====================

abstract class _LxSearchSource {
  Future<LxSearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  });
}

// ==================== 酷我 ====================

class _KwSearchSource extends _LxSearchSource {
  @override
  Future<LxSearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    for (var retry = 0; retry < 3; retry++) {
      try {
        final result = await _searchOnce(
            keyword: keyword, page: page, pageSize: pageSize);
        final show = result['SHOW']?.toString();
        final total = result['TOTAL']?.toString() ?? '0';
        if (total != '0' && show == '0' && retry < 2) continue;
        return result['result'] as LxSearchResult;
      } catch (e) {
        if (retry >= 2) rethrow;
      }
    }
    throw Exception('酷我搜索失败');
  }

  Future<Map<String, dynamic>> _searchOnce({
    required String keyword,
    required int page,
    required int pageSize,
  }) async {
    final url =
        'http://search.kuwo.cn/r.s?client=kt&all=${Uri.encodeComponent(keyword)}&pn=${page - 1}&rn=$pageSize&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1&ft=music&cluster=0&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1';

    final resp = await LxHttp.dio.get<String>(
      url,
      options: LxHttp.options(timeout: const Duration(seconds: 15)),
    );
    if (resp.statusCode != 200) {
      throw Exception('搜索请求失败');
    }
    final data = jsonDecode(resp.data ?? '{}');
    final absList = data['abslist'] as List? ?? [];
    final total = int.tryParse(data['TOTAL']?.toString() ?? '0') ?? 0;

    final results = absList.map((item) => _parseItem(item)).toList();

    return {
      'SHOW': data['SHOW']?.toString(),
      'TOTAL': data['TOTAL']?.toString(),
      'result': LxSearchResult(
        list: results,
        total: total,
        page: page,
        pageSize: pageSize,
        source: 'kw',
      ),
    };
  }

  LxMusic _parseItem(Map<String, dynamic> item) {
    final songId =
        (item['MUSICRID']?.toString() ?? '').replaceFirst('MUSIC_', '');
    final name = LxSignUtils.decodeHtml(item['SONGNAME']?.toString() ?? '');
    final artist = LxSignUtils.decodeHtml(item['ARTIST']?.toString() ?? '');
    final album = LxSignUtils.decodeHtml(item['ALBUM']?.toString() ?? '');
    final duration = int.tryParse(item['DURATION']?.toString() ?? '0') ?? 0;
    final imgUrl = item['WEB_ALBUM_PIC']?.toString();

    final types = _parseKwTypes(item['N_MINFO']?.toString() ?? '');

    return LxMusic(
      id: 'kw_$songId',
      name: name,
      singer: artist,
      album: album,
      source: 'kw',
      songId: songId,
      songmid: songId,
      duration: duration,
      imgUrl: imgUrl,
      types: types.isNotEmpty ? types : null,
    );
  }

  List<LxQualityType> _parseKwTypes(String minfo) {
    final types = <LxQualityType>[];
    final regExp =
        RegExp(r'level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)');

    for (final match in regExp.allMatches(minfo)) {
      final bitrate = match.group(2);
      final size = match.group(4);

      String type;
      switch (bitrate) {
        case '4000':
          type = 'flac24bit';
          break;
        case '2000':
          type = 'flac';
          break;
        case '320':
          type = '320k';
          break;
        case '128':
          type = '128k';
          break;
        default:
          continue;
      }
      types.add(LxQualityType(type: type, size: size ?? ''));
    }

    return types;
  }
}

// ==================== 酷狗 ====================

class _KgSearchSource extends _LxSearchSource {
  @override
  Future<LxSearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final url =
          'https://songsearch.kugou.com/song_search_v2?keyword=${Uri.encodeComponent(keyword)}&page=$page&pagesize=$pageSize&userid=0&clientver=&platform=WebFilter&filter=2&iscorrection=1&privilege_filter=0&area_code=1';

      final resp = await LxHttp.dio.get<String>(
        url,
        options: LxHttp.options(timeout: const Duration(seconds: 15)),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.data ?? '{}');
        if (data['error_code'] != 0) {
          throw Exception('搜索错误: ${data['error_code']}');
        }

        final lists = data['data']['lists'] as List? ?? [];
        final total = data['data']['total'] ?? 0;

        final results = <LxMusic>[];
        final ids = <String>{};

        for (final item in lists) {
          final music = _parseItem(item);
          final key = '${music.songId}_${music.name}';
          if (!ids.contains(key)) {
            ids.add(key);
            results.add(music);
          }
        }

        return LxSearchResult(
          list: results,
          total: total,
          page: page,
          pageSize: pageSize,
          source: 'kg',
        );
      }
      throw Exception('搜索请求失败');
    } catch (e) {
      throw Exception('酷狗搜索失败: $e');
    }
  }

  LxMusic _parseItem(Map<String, dynamic> item) {
    final songId = item['Audioid']?.toString() ?? '';
    final name = LxSignUtils.decodeHtml(item['SongName']?.toString() ?? '');
    final singers = item['Singers'] as List? ?? [];
    final artist =
        singers.map((s) => s['name']?.toString() ?? '').join('、');
    final album = LxSignUtils.decodeHtml(item['AlbumName']?.toString() ?? '');
    final duration = item['Duration'] ?? 0;

    final types = <LxQualityType>[];
    if ((item['FileSize'] ?? 0) != 0) {
      types.add(LxQualityType(
          type: '128k', size: LxSignUtils.formatSize(item['FileSize'])));
    }
    if ((item['HQFileSize'] ?? 0) != 0) {
      types.add(LxQualityType(
          type: '320k', size: LxSignUtils.formatSize(item['HQFileSize'])));
    }
    if ((item['SQFileSize'] ?? 0) != 0) {
      types.add(LxQualityType(
          type: 'flac', size: LxSignUtils.formatSize(item['SQFileSize'])));
    }
    if ((item['ResFileSize'] ?? 0) != 0) {
      types.add(LxQualityType(
          type: 'flac24bit',
          size: LxSignUtils.formatSize(item['ResFileSize'])));
    }

    return LxMusic(
      id: 'kg_$songId',
      name: name,
      singer: artist,
      album: album,
      source: 'kg',
      songId: songId,
      hash: songId,
      duration: duration,
      types: types.isNotEmpty ? types : null,
    );
  }
}

// ==================== QQ 音乐 ====================

class _TxSearchSource extends _LxSearchSource {
  @override
  Future<LxSearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final data = {
        'comm': {
          'ct': '11',
          'cv': '14090508',
          'v': '14090508',
          'tmeAppID': 'qqmusic',
          'phonetype': 'EBG-AN10',
          'deviceScore': '553.47',
          'devicelevel': '50',
          'newdevicelevel': '20',
          'rom': 'HuaWei/EMOTION/EmotionUI_14.2.0',
          'os_ver': '12',
          'OpenUDID': '0',
          'OpenUDID2': '0',
          'QIMEI36': '0',
          'udid': '0',
          'chid': '0',
          'aid': '0',
          'oaid': '0',
          'taid': '0',
          'tid': '0',
          'wid': '0',
          'uid': '0',
          'sid': '0',
          'modeSwitch': '6',
          'teenMode': '0',
          'ui_mode': '2',
          'nettype': '1020',
          'v4ip': '',
        },
        'req': {
          'module': 'music.search.SearchCgiService',
          'method': 'DoSearchForQQMusicMobile',
          'param': {
            'search_type': 0,
            'searchid': DateTime.now().millisecondsSinceEpoch.toString(),
            'query': keyword,
            'page_num': page,
            'num_per_page': pageSize,
            'highlight': 0,
            'nqc_flag': 0,
            'multi_zhida': 0,
            'cat': 2,
            'grp': 1,
            'sin': 0,
            'sem': 0,
          },
        },
      };

      final sign = LxSignUtils.zzcSign(jsonEncode(data));
      final url = 'https://u.y.qq.com/cgi-bin/musics.fcg?sign=$sign';

      final resp = await LxHttp.dio.post<String>(
        url,
        data: jsonEncode(data),
        options: LxHttp.options(
          timeout: const Duration(seconds: 15),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'QQMusic 14090508(android 12)',
          },
        ),
      );

      if (resp.statusCode == 200) {
        final responseData = jsonDecode(resp.data ?? '{}');
        if (responseData['code'] != 0) {
          throw Exception('搜索错误');
        }

        final body = responseData['req']['data']['body'];
        final songList = body?['item_song'] as List? ?? [];
        final total =
            responseData['req']['data']['meta']?['estimate_sum'] ?? 0;

        final results = songList.map((item) => _parseItem(item)).toList();

        return LxSearchResult(
          list: results,
          total: total,
          page: page,
          pageSize: pageSize,
          source: 'tx',
        );
      }
      throw Exception('搜索请求失败');
    } catch (e) {
      throw Exception('QQ音乐搜索失败: $e');
    }
  }

  LxMusic _parseItem(Map<String, dynamic> item) {
    final songId = item['id']?.toString() ?? '';
    final songmid = item['mid']?.toString() ?? '';
    final name = item['title']?.toString() ?? '';
    final singers = item['singer'] as List? ?? [];
    final artist =
        singers.map((s) => s['name']?.toString() ?? '').join('、');
    final album = item['album']?['name']?.toString() ?? '';
    final albumMid = item['album']?['mid']?.toString() ?? '';
    final duration = item['interval'] ?? 0;
    final file = item['file'] as Map? ?? {};
    final strMediaMid = file['media_mid']?.toString() ?? '';

    final types = <LxQualityType>[];
    if ((file['size_128mp3'] ?? 0) != 0) {
      types.add(LxQualityType(
          type: '128k', size: LxSignUtils.formatSize(file['size_128mp3'])));
    }
    if ((file['size_320mp3'] ?? 0) != 0) {
      types.add(LxQualityType(
          type: '320k', size: LxSignUtils.formatSize(file['size_320mp3'])));
    }
    if ((file['size_flac'] ?? 0) != 0) {
      types.add(LxQualityType(
          type: 'flac', size: LxSignUtils.formatSize(file['size_flac'])));
    }
    if ((file['size_hires'] ?? 0) != 0) {
      types.add(LxQualityType(
          type: 'flac24bit',
          size: LxSignUtils.formatSize(file['size_hires'])));
    }

    final img = albumMid.isNotEmpty
        ? 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg'
        : null;

    return LxMusic(
      id: 'tx_$songmid',
      name: name,
      singer: artist,
      album: album,
      source: 'tx',
      songId: songId,
      songmid: songmid,
      strMediaMid: strMediaMid,
      duration: duration,
      imgUrl: img,
      types: types.isNotEmpty ? types : null,
    );
  }
}

// ==================== 网易云 ====================

class _WySearchSource extends _LxSearchSource {
  @override
  Future<LxSearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final requestData = {
        'keyword': keyword,
        'needCorrect': '1',
        'channel': 'typing',
        'offset': pageSize * (page - 1),
        'scene': 'normal',
        'total': page == 1,
        'limit': pageSize,
      };

      final params = LxSignUtils.eapi(
          '/api/search/song/list/page', jsonEncode(requestData));

      final resp = await LxHttp.dio.post<String>(
        'http://interface.music.163.com/eapi/batch',
        data: {'params': params},
        options: LxHttp.options(
          timeout: const Duration(seconds: 15),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent':
                'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
            'origin': 'https://music.163.com',
          },
        ),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.data ?? '{}');
        if (data['code'] != 200) {
          throw Exception('搜索错误');
        }

        final resources = data['data']['resources'] as List? ?? [];
        final totalCount = data['data']['totalCount'] ?? 0;

        final results = resources.map((item) => _parseItem(item)).toList();

        return LxSearchResult(
          list: results,
          total: totalCount,
          page: page,
          pageSize: pageSize,
          source: 'wy',
        );
      }
      throw Exception('搜索请求失败');
    } catch (e) {
      throw Exception('网易云搜索失败: $e');
    }
  }

  LxMusic _parseItem(Map<String, dynamic> item) {
    final baseInfo = item['baseInfo'] as Map? ?? {};
    final songData = baseInfo['simpleSongData'] as Map? ?? {};
    final songId = songData['id']?.toString() ?? '';
    final name = songData['name']?.toString() ?? '';
    final singers = songData['ar'] as List? ?? [];
    final artist =
        singers.map((s) => s['name']?.toString() ?? '').join('、');
    final albumData = songData['al'] as Map? ?? {};
    final album = albumData['name']?.toString() ?? '';
    final duration = (songData['dt'] ?? 0) ~/ 1000;
    final img = albumData['picUrl']?.toString();

    final privilege = songData['privilege'] as Map? ?? {};
    final maxbr = privilege['maxbr'] ?? 0;
    final maxBrLevel = privilege['maxBrLevel']?.toString() ?? '';

    final types = <LxQualityType>[];
    if (maxBrLevel == 'hires') {
      final hrSize = songData['hr']?['size'] ?? 0;
      types.add(LxQualityType(
          type: 'flac24bit', size: LxSignUtils.formatSize(hrSize)));
    }
    if (maxbr >= 999000) {
      final sqSize = songData['sq']?['size'] ?? 0;
      types.add(
          LxQualityType(type: 'flac', size: LxSignUtils.formatSize(sqSize)));
    }
    if (maxbr >= 320000) {
      final hSize = songData['h']?['size'] ?? 0;
      types.add(
          LxQualityType(type: '320k', size: LxSignUtils.formatSize(hSize)));
    }
    if (maxbr >= 128000) {
      final lSize = songData['l']?['size'] ?? 0;
      types.add(
          LxQualityType(type: '128k', size: LxSignUtils.formatSize(lSize)));
    }

    return LxMusic(
      id: 'wy_$songId',
      name: name,
      singer: artist,
      album: album,
      source: 'wy',
      songId: songId,
      songmid: songId,
      duration: duration,
      imgUrl: img,
      types: types.isNotEmpty ? types : null,
    );
  }
}

// ==================== 结果模型 ====================

class LxSearchResult {
  final List<LxMusic> list;
  final int total;
  final int page;
  final int pageSize;
  final String source;
  final bool? hasMoreOverride;

  LxSearchResult({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.source,
    this.hasMoreOverride,
  });

  bool get hasMore => hasMoreOverride ?? (list.length < total);
}