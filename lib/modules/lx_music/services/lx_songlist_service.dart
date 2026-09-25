import 'dart:convert';

import '../models/lx_music_model.dart';
import '../models/lx_songlist_model.dart';
import '../utils/lx_logger.dart';
import '../utils/lx_sign_utils.dart';
import 'lx_http.dart';

/// 洛雪音乐歌单服务
class LxSonglistService {
  LxSonglistService._();
  static final LxSonglistService instance = LxSonglistService._();

  static const String _kwDetailUrl =
      'https://nplserver.kuwo.cn/pl.svc?op=getlistinfo&pid={id}&pn={page}&rn=1000&encode=utf8&keyset=pl2012&identity=kuwo&pcmp4=1&vipver=MUSIC_9.0.5.0_W1&newver=1';

  // ==================== 推荐歌单（酷我） ====================

  Future<List<LxSonglistInfo>> getRecommendSonglists({
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final url =
          'https://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList?loginUid=0&loginSid=0&appUid=76039576&pn=$page&rn=$pageSize&order=hot';
      final resp = await LxHttp.dio.get<String>(
        url,
        options: LxHttp.options(timeout: const Duration(seconds: 15)),
      );

      if (resp.statusCode != 200) return [];

      final data = jsonDecode(resp.data ?? '{}');
      if (data['code'] != 200) return [];

      final list = data['data']?['data'] as List? ?? [];
      return list.map((item) {
        final img = item['img']?.toString() ?? '';
        return LxSonglistInfo(
          id: item['id']?.toString() ?? '',
          name: item['name']?.toString() ?? '',
          author: item['uname']?.toString() ?? '',
          imgUrl: _normalizeKwImg(img),
          playCount: _parseInt(item['listencnt']),
          songCount: _parseInt(item['total']),
          desc: item['desc']?.toString() ?? '',
          source: 'kw',
        );
      }).toList();
    } catch (e) {
      LxLogger.error('获取推荐歌单失败: $e');
      return [];
    }
  }

  // ==================== QQ 推荐歌单 ====================

  Future<List<LxSonglistInfo>> getQQRecommendSonglists({
    int page = 0,
    int pageSize = 30,
    int categoryId = 10000000,
    int sortId = 5,
  }) async {
    try {
      final rnd = DateTime.now().millisecondsSinceEpoch % 100000;
      final url =
          'https://c.y.qq.com/splcloud/fcgi-bin/fcg_get_diss_by_tag.fcg'
          '?picmid=1&rnd=$rnd&g_tk=5381&loginUin=0&hostUin=0&format=json'
          '&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json'
          '&needNewCode=0&categoryId=$categoryId&sortId=$sortId'
          '&sin=${page * pageSize}&ein=${page * pageSize + pageSize - 1}';

      final resp = await LxHttp.dio.get<String>(
        url,
        options: LxHttp.options(
          timeout: const Duration(seconds: 15),
          headers: {'Referer': 'https://c.y.qq.com/'},
        ),
      );

      if (resp.statusCode != 200) return [];

      final data = jsonDecode(resp.data ?? '{}');
      if (data['code'] != 0) return [];

      final list = data['data']?['list'] as List? ?? [];
      return list.map((item) {
        return LxSonglistInfo(
          id: item['dissid']?.toString() ?? '',
          name: item['dissname']?.toString() ?? '',
          author: item['creator']?['name']?.toString() ?? '',
          imgUrl: item['imgurl']?.toString() ?? '',
          playCount: _parseInt(item['listennum']),
          songCount: 0,
          desc: item['introduction']?.toString() ?? '',
          source: 'tx',
        );
      }).toList();
    } catch (e) {
      LxLogger.error('QQ推荐歌单获取失败: $e');
      return [];
    }
  }

  // ==================== 歌单搜索 ====================

  Future<List<LxSonglistInfo>> searchSonglists(
    String keyword, {
    required String source,
    int page = 1,
    int pageSize = 20,
  }) async {
    switch (source) {
      case 'tx':
        return searchQQSonglists(keyword, page: page, pageSize: pageSize);
      case 'kw':
        return searchKwSonglists(keyword, page: page, pageSize: pageSize);
      case 'wy':
        return searchWySonglists(keyword, page: page, pageSize: pageSize);
      case 'all':
        final results = await Future.wait([
          searchQQSonglists(keyword, page: page, pageSize: pageSize),
          searchKwSonglists(keyword, page: page, pageSize: pageSize),
          searchWySonglists(keyword, page: page, pageSize: pageSize),
        ]);
        final merged = <LxSonglistInfo>[];
        final seen = <String>{};
        final maxLen =
            results.map((r) => r.length).fold(0, (a, b) => a > b ? a : b);
        for (var i = 0; i < maxLen; i++) {
          for (final r in results) {
            if (i >= r.length) continue;
            final s = r[i];
            final key = '${s.name}_${s.author}';
            if (seen.contains(key)) continue;
            seen.add(key);
            merged.add(s);
          }
        }
        return merged;
      default:
        return searchQQSonglists(keyword, page: page, pageSize: pageSize);
    }
  }

  Future<List<LxSonglistInfo>> searchQQSonglists(
    String keyword, {
    int page = 1,
    int pageSize = 20,
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
            'search_type': 3,
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

      if (resp.statusCode != 200) return [];

      final responseData = jsonDecode(resp.data ?? '{}');
      final reqData = responseData['req']?['data'];
      final body = reqData?['body'];
      final songList = body?['item_songlist'] as List? ?? [];

      return songList.map((item) {
        return LxSonglistInfo(
          id: item['dissid']?.toString() ?? '',
          name: (item['dissname']?.toString() ?? '')
              .replaceAll(RegExp(r'</?em>'), ''),
          author: item['nickname']?.toString() ?? '',
          imgUrl: item['logo']?.toString() ?? '',
          playCount: _parseInt(item['listennum']),
          songCount: 0,
          desc: item['description']?.toString() ?? '',
          source: 'tx',
        );
      }).toList();
    } catch (e) {
      LxLogger.error('QQ歌单搜索失败: $e');
      return [];
    }
  }

  Future<List<LxSonglistInfo>> searchKwSonglists(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final url =
          'http://search.kuwo.cn/r.s?all=${Uri.encodeComponent(keyword)}&pn=${page - 1}&rn=$pageSize&rformat=json&encoding=utf8&ver=mbox&vipver=MUSIC_8.7.7.0_BCS37&plat=pc&devid=28156413&ft=playlist&pay=0&needliveshow=0';
      final resp = await LxHttp.dio.get<String>(
        url,
        options: LxHttp.options(timeout: const Duration(seconds: 12)),
      );
      if (resp.statusCode != 200) return [];
      final body = jsonDecode(resp.data ?? '{}');
      final absList = body['abslist'] as List? ?? [];
      return absList.map((item) {
        return LxSonglistInfo(
          id: item['playlistid']?.toString() ?? '',
          name: LxSignUtils.decodeHtml(item['name']?.toString() ?? ''),
          author: LxSignUtils.decodeHtml(item['nickname']?.toString() ?? ''),
          imgUrl: item['pic']?.toString() ?? '',
          playCount: _parseInt(item['playcnt']),
          songCount: _parseInt(item['songnum']),
          desc: LxSignUtils.decodeHtml(item['intro']?.toString() ?? ''),
          source: 'kw',
        );
      }).toList();
    } catch (e) {
      LxLogger.error('酷我歌单搜索失败: $e');
      return [];
    }
  }

  Future<List<LxSonglistInfo>> searchWySonglists(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final requestData = {
        's': keyword,
        'type': 1000,
        'limit': pageSize,
        'total': page == 1,
        'offset': pageSize * (page - 1),
      };
      final params =
          LxSignUtils.eapi('/api/cloudsearch/pc', jsonEncode(requestData));
      final resp = await LxHttp.dio.post<String>(
        'http://interface.music.163.com/eapi/batch',
        data: {'params': params},
        options: LxHttp.options(
          timeout: const Duration(seconds: 12),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent':
                'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
            'origin': 'https://music.163.com',
          },
        ),
      );
      if (resp.statusCode != 200) return [];
      final body = jsonDecode(resp.data ?? '{}');
      if (body['code'] != 200) return [];
      final playlists = body['result']?['playlists'] as List? ?? [];
      return playlists.map((item) {
        final creator = item['creator'] as Map? ?? {};
        return LxSonglistInfo(
          id: item['id']?.toString() ?? '',
          name: item['name']?.toString() ?? '',
          author: creator['nickname']?.toString() ?? '',
          imgUrl: item['coverImgUrl']?.toString() ?? '',
          playCount: _parseInt(item['playCount']),
          songCount: _parseInt(item['trackCount']),
          desc: item['description']?.toString() ?? '',
          source: 'wy',
        );
      }).toList();
    } catch (e) {
      LxLogger.error('网易歌单搜索失败: $e');
      return [];
    }
  }

  // ==================== 歌单详情 ====================

  Future<({String name, String imgUrl, List<LxMusic> songs})?> getSonglistDetail({
    required String songlistId,
    int page = 0,
    String source = 'kw',
  }) async {
    switch (source) {
      case 'tx':
        return getQQPlaylistDetail(songlistId);
      case 'wy':
        final wyDetail = await getWYPlaylistDetail(songlistId);
        return wyDetail;
    }
    final kwDetail = await _getKwSonglistDetail(songlistId, page);
    if (kwDetail != null && kwDetail.songs.isNotEmpty) return kwDetail;
    return getQQPlaylistDetail(songlistId);
  }

  Future<({String name, String imgUrl, List<LxMusic> songs})?>
      _getKwSonglistDetail(String songlistId, int page) async {
    try {
      final url = Uri.parse(_kwDetailUrl
          .replaceAll('{id}', songlistId)
          .replaceAll('{page}', page.toString()));
      final resp = await LxHttp.dio.get<String>(
        url.toString(),
        options: LxHttp.options(timeout: const Duration(seconds: 15)),
      );

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.data ?? '{}');
      if (data['result'] != 'ok') return null;

      final musicList = data['musiclist'] as List? ?? [];
      final songs = musicList.map((item) => _parseKwSong(item)).toList();

      return (
        name: data['title']?.toString() ?? '',
        imgUrl: data['pic']?.toString() ?? '',
        songs: songs,
      );
    } catch (e) {
      LxLogger.error('获取歌单详情失败: $e');
      return null;
    }
  }

  LxMusic _parseKwSong(Map<String, dynamic> item) {
    final songId = item['id']?.toString() ?? '';
    final pic = item['pic']?.toString() ?? item['pic120']?.toString() ?? '';
    return LxMusic(
      id: 'kw_$songId',
      name: LxSignUtils.decodeHtml(item['name']?.toString() ?? ''),
      singer: LxSignUtils.decodeHtml(item['artist']?.toString() ?? ''),
      album: LxSignUtils.decodeHtml(item['album']?.toString() ?? ''),
      duration: 0,
      source: 'kw',
      songId: songId,
      songmid: songId,
      imgUrl: pic.isNotEmpty ? _normalizeKwImg(pic) : null,
    );
  }

  // ==================== QQ 歌单详情 ====================

  Future<({String name, String imgUrl, List<LxMusic> songs})?>
      getQQPlaylistDetail(String disstid) async {
    try {
      final data = {
        'comm': {'uin': 0, 'format': 'json', 'ct': 24, 'cv': 0},
        'req': {
          'module': 'music.srfDissInfo.DissInfo',
          'method': 'CgiGetDiss',
          'param': {
            'disstid': int.tryParse(disstid) ?? 0,
            'onlysong': 0,
            'song_begin': 0,
            'song_num': 500,
          },
        },
      };

      final resp = await LxHttp.dio.post<String>(
        'https://u.y.qq.com/cgi-bin/musicu.fcg?format=json',
        data: jsonEncode(data),
        options: LxHttp.options(
          timeout: const Duration(seconds: 15),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
            'Referer':
                'https://y.qq.com/n3/other/pages/details/playlist.html',
            'Origin': 'https://y.qq.com',
          },
        ),
      );

      if (resp.statusCode != 200) {
        LxLogger.warn('QQ歌单: HTTP ${resp.statusCode}');
        return null;
      }

      final respData = jsonDecode(resp.data ?? '{}');
      final reqData = respData['req']?['data'];
      if (reqData == null) {
        LxLogger.warn(
            'QQ歌单: req.data 为空, code=${respData['req']?['code']}');
        return null;
      }

      final dirInfo = (reqData['dirinfo'] ?? reqData['dirInfo']) as Map? ?? {};
      final songList =
          (reqData['songlist'] ?? reqData['songList']) as List? ?? [];
      LxLogger.info(
          'QQ歌单: title=${dirInfo['title']}, 原始歌曲数=${songList.length}');

      final songs = <LxMusic>[];
      for (final item in songList) {
        final si = (item['songInfo'] ?? item) as Map?;
        if (si == null) continue;
        final songmid = si['mid']?.toString() ?? '';
        if (songmid.isEmpty) continue;
        final singers = si['singer'] as List? ?? [];
        final artist =
            singers.map((s) => s['name']?.toString() ?? '').join('、');
        final album = si['album'] as Map? ?? {};
        final albumMid = album['mid']?.toString() ?? '';

        final file = si['file'] as Map? ?? {};
        final types = <LxQualityType>[];
        if (((file['size_128mp3'] ?? 0) != 0)) {
          types.add(LxQualityType(
              type: '128k',
              size: LxSignUtils.formatSize(file['size_128mp3'])));
        }
        if (((file['size_320mp3'] ?? 0) != 0)) {
          types.add(LxQualityType(
              type: '320k',
              size: LxSignUtils.formatSize(file['size_320mp3'])));
        }
        if (((file['size_flac'] ?? 0) != 0)) {
          types.add(LxQualityType(
              type: 'flac',
              size: LxSignUtils.formatSize(file['size_flac'])));
        }
        if (((file['size_hires'] ?? 0) != 0)) {
          types.add(LxQualityType(
              type: 'flac24bit',
              size: LxSignUtils.formatSize(file['size_hires'])));
        }

        songs.add(LxMusic(
          id: 'tx_$songmid',
          name: (si['title'] ?? si['name'])?.toString() ?? '',
          singer: artist,
          album: album['name']?.toString() ?? '',
          duration: _parseInt(si['interval']),
          source: 'tx',
          songId: si['id']?.toString() ?? '',
          songmid: songmid,
          strMediaMid: file['media_mid']?.toString() ?? songmid,
          imgUrl: albumMid.isNotEmpty
              ? 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg'
              : null,
          types: types.isNotEmpty ? types : null,
        ));
      }

      return (
        name: dirInfo['title']?.toString() ?? '',
        imgUrl:
            dirInfo['picurl']?.toString() ?? dirInfo['pic']?.toString() ?? '',
        songs: songs,
      );
    } catch (e) {
      LxLogger.error('QQ歌单获取失败: $e');
      return null;
    }
  }

  // ==================== 网易歌单详情 ====================

  Future<({String name, String imgUrl, List<LxMusic> songs})?>
      getWYPlaylistDetail(String playlistId) async {
    try {
      final params = LxSignUtils.eapi(
          '/api/v3/playlist/detail',
          jsonEncode({
            'id': playlistId,
            'n': 1000,
            's': 8,
          }));
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

      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.data ?? '{}');
      if (data['code'] != 200) return null;

      final playlist = data['playlist'] as Map? ?? {};
      final name = playlist['name']?.toString() ?? '';
      final imgUrl = playlist['coverImgUrl']?.toString() ?? '';
      final tracks = playlist['tracks'] as List? ?? [];
      final trackIds = playlist['trackIds'] as List? ?? [];
      final privileges = playlist['privileges'] as List? ?? [];

      final privilegeById = <String, Map>{};
      for (final p in privileges) {
        final pid = p['id']?.toString();
        if (pid != null) privilegeById[pid] = p;
      }

      if (tracks.length < trackIds.length) {
        final allIds = trackIds
            .map((t) => t['id']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        final fetchedSongs = <Map>[];
        final fetchedPrivs = <Map>[];
        for (var i = 0; i < allIds.length; i += 500) {
          final batch = allIds.skip(i).take(500).toList();
          final detailData = await _eapiRequest('/api/v3/song/detail', {
            'c': '[${batch.map((id) => '{"id":$id}').join(',')}]',
            'ids': '[${batch.join(',')}]',
          });
          if (detailData == null) continue;
          fetchedSongs
              .addAll((detailData['songs'] as List? ?? []).cast<Map>());
          fetchedPrivs
              .addAll((detailData['privileges'] as List? ?? []).cast<Map>());
        }
        LxLogger.info(
            'WY歌单: tracks 截断(${tracks.length}/${trackIds.length})，已补拉 ${fetchedSongs.length} 首');
        return (
          name: name,
          imgUrl: imgUrl,
          songs: _buildWYSongs(fetchedSongs, fetchedPrivs),
        );
      }

      return (
        name: name,
        imgUrl: imgUrl,
        songs: _buildWYSongs(tracks.cast<Map>(), privileges.cast<Map>()),
      );
    } catch (e) {
      LxLogger.error('WY歌单获取失败: $e');
      return null;
    }
  }

  Future<Map?> _eapiRequest(String url, Map data) async {
    try {
      final params = LxSignUtils.eapi(url, jsonEncode(data));
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
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.data ?? '{}');
      return decoded is Map ? decoded : null;
    } catch (e) {
      LxLogger.error('WY eapi 请求失败: $e');
      return null;
    }
  }

  List<LxMusic> _buildWYSongs(List<Map> tracks, List<Map> privileges) {
    final songs = <LxMusic>[];
    final privilegeById = <String, Map>{};
    for (final p in privileges) {
      final pid = p['id']?.toString();
      if (pid != null) privilegeById[pid] = p;
    }
    for (final t in tracks) {
      final songId = t['id']?.toString() ?? '';
      if (songId.isEmpty) continue;
      final artists = t['ar'] as List? ?? (t['artists'] as List? ?? []);
      final artist = artists
          .map((a) => a['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .join('、');
      final album = t['al'] as Map? ?? (t['album'] as Map? ?? {});

      final privilege = privilegeById[songId] as Map? ?? {};
      final maxbr = privilege['maxbr'] ?? 0;
      final maxBrLevel = privilege['maxBrLevel']?.toString() ?? '';
      final types = <LxQualityType>[];
      if (maxBrLevel == 'hires') {
        types.add(LxQualityType(
            type: 'flac24bit',
            size: LxSignUtils.formatSize(t['hr']?['size'] ?? 0)));
      }
      if (maxbr >= 999000) {
        types.add(LxQualityType(
            type: 'flac',
            size: LxSignUtils.formatSize(t['sq']?['size'] ?? 0)));
      }
      if (maxbr >= 320000) {
        types.add(LxQualityType(
            type: '320k',
            size: LxSignUtils.formatSize(t['h']?['size'] ?? 0)));
      }
      if (maxbr >= 128000) {
        types.add(LxQualityType(
            type: '128k',
            size: LxSignUtils.formatSize(t['l']?['size'] ?? 0)));
      }

      songs.add(LxMusic(
        id: 'wy_$songId',
        name: t['name']?.toString() ?? '',
        singer: artist,
        album: album['name']?.toString() ?? '',
        duration: _parseInt(t['dt']) ~/ 1000,
        source: 'wy',
        songId: songId,
        songmid: songId,
        imgUrl: album['picUrl']?.toString(),
        types: types.isNotEmpty ? types : null,
      ));
    }
    return songs;
  }

  // ==================== 分享链接解析 ====================

  static ({String source, String id})? parseShareLink(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final urlMatch = RegExp(r'https?://[^\s，,。]+').firstMatch(text);
    if (urlMatch == null) return null;
    final url = urlMatch.group(0)!;

    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final host = uri.host;
    final idParam =
        uri.queryParameters['id'] ?? uri.queryParameters['disstid'];
    if (idParam != null && RegExp(r'^\d+$').hasMatch(idParam)) {
      if (host.contains('163.com') || host.contains('163cn.tv')) {
        return (source: 'wy', id: idParam);
      }
      if (host.contains('qq.com')) {
        return (source: 'tx', id: idParam);
      }
      return (source: 'tx', id: idParam);
    }

    if (host.contains('qq.com') ||
        host.contains('163cn.tv') ||
        host.contains('163.com')) {
      return (source: 'redirect', id: url);
    }
    return null;
  }

  static Future<String?> resolveRedirectId(String url) async {
    try {
      var currentUrl = url;
      for (var i = 0; i < 5; i++) {
        final resp = await LxHttp.dio.get<String>(
          currentUrl,
          options: LxHttp.options(
            timeout: const Duration(seconds: 10),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
            },
          ),
        );

        final status = resp.statusCode ?? 0;
        if (status == 301 || status == 302) {
          final location = resp.headers.value('location');
          if (location == null) break;
          currentUrl = location.startsWith('http')
              ? location
              : '${Uri.parse(currentUrl).origin}$location';
          final uri = Uri.tryParse(currentUrl);
          final idParam =
              uri?.queryParameters['id'] ?? uri?.queryParameters['disstid'];
          if (idParam != null && RegExp(r'^\d+$').hasMatch(idParam)) {
            return idParam;
          }
          continue;
        }
        break;
      }
      final uri = Uri.tryParse(currentUrl);
      return uri?.queryParameters['id'] ?? uri?.queryParameters['disstid'];
    } catch (e) {
      LxLogger.error('重定向解析失败: $e');
      return null;
    }
  }

  // ==================== 工具 ====================

  String _normalizeKwImg(String img) {
    if (img.contains('_500.jpg')) return img;
    final match = RegExp(r'^(.*?)_\d+\.(jpg|png)$').firstMatch(img);
    if (match != null) {
      return '${match.group(1)}_500.${match.group(2)}';
    }
    return img;
  }

  int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '0') ?? 0;
  }
}