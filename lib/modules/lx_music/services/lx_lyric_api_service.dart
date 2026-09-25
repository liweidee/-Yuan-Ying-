import 'dart:convert';

import '../models/lx_music_model.dart';
import '../utils/lx_logger.dart';
import 'lx_http.dart';

/// 内置歌词获取服务
class LxLyricApiService {
  LxLyricApiService._();
  static final LxLyricApiService instance = LxLyricApiService._();

  Future<Map<String, String?>?> getLyric(LxMusic music) async {
    LxLogger.info('获取歌词: source=${music.source}, id=${music.songId}');

    Map<String, String?>? result;
    switch (music.source) {
      case 'kw':
        result = await _getKwLyric(music);
        break;
      case 'wy':
        result = await _getWyLyric(music);
        break;
      case 'tx':
        result = await _getTxLyric(music);
        break;
      case 'kg':
        result = await _getKgLyric(music);
        break;
      default:
        result = await _getKwLyric(music);
        if (result == null) result = await _getWyLyric(music);
    }

    if (result != null &&
        result['lyric'] != null &&
        result['lyric']!.isNotEmpty) {
      return result;
    }

    LxLogger.info('本源歌词为空，尝试网易云跨源兜底');
    try {
      final fallback = await _searchWyLyricByKeyword(music);
      if (fallback != null &&
          fallback['lyric'] != null &&
          fallback['lyric']!.isNotEmpty) {
        LxLogger.info('网易云跨源兜底成功');
        return fallback;
      }
    } catch (e) {
      LxLogger.warn('网易云跨源兜底失败: $e');
    }

    return result;
  }

  Future<Map<String, String?>?> searchLyricByKeyword(
      String name, String singer) async {
    final music = LxMusic(
      id: 'temp',
      name: name,
      singer: singer,
      album: '',
      duration: 0,
      source: 'wy',
    );
    return _searchWyLyricByKeyword(music);
  }

  Future<Map<String, String?>?> _getKwLyric(LxMusic music) async {
    final musicId = music.songId ?? music.id;
    if (musicId.isEmpty) return null;

    try {
      final resp = await LxHttp.dio.get<String>(
        'https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=$musicId',
        options: LxHttp.options(
          timeout: const Duration(seconds: 10),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
            'Referer': 'https://m.kuwo.cn/',
          },
        ),
      );
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.data ?? '{}');
      if (data['status'] != 200) return null;

      final lrcList = data['data']?['lrclist'] as List?;
      if (lrcList == null || lrcList.isEmpty) return null;

      final buffer = StringBuffer();
      for (final item in lrcList) {
        final time = item['time']?.toString() ?? '0';
        final text = item['lineLyric']?.toString() ?? '';
        if (text.isEmpty) continue;

        final seconds = double.tryParse(time) ?? 0;
        final minutes = (seconds / 60).floor();
        final secs = (seconds % 60).toStringAsFixed(2);
        buffer.writeln(
            '[${minutes.toString().padLeft(2, '0')}:$secs]$text');
      }

      final lrc = buffer.toString();
      if (lrc.isEmpty) return null;
      return {'lyric': lrc, 'tlyric': null};
    } catch (e) {
      LxLogger.warn('KW歌词失败: $e');
      return null;
    }
  }

  Future<Map<String, String?>?> _getWyLyric(LxMusic music) async {
    final musicId = music.songId ?? music.id;
    if (musicId.isEmpty) return null;

    try {
      final resp = await LxHttp.dio.get<String>(
        'https://music.163.com/api/song/lyric?id=$musicId&lv=1&tv=1',
        options: LxHttp.options(
          timeout: const Duration(seconds: 10),
          headers: {'Referer': 'https://music.163.com/'},
        ),
      );
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.data ?? '{}');
      if (data['code'] != 200) return null;

      final lrc = data['lrc']?['lyric'] as String?;
      final tlyric = data['tlyric']?['lyric'] as String?;
      if (lrc == null || lrc.isEmpty) return null;
      return {'lyric': lrc, 'tlyric': tlyric};
    } catch (e) {
      LxLogger.warn('WY歌词失败: $e');
      return null;
    }
  }

  Future<Map<String, String?>?> _getTxLyric(LxMusic music) async {
    final musicId = music.songmid ?? music.songId ?? music.id;
    if (musicId.isEmpty) return null;

    try {
      final resp = await LxHttp.dio.get<String>(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=$musicId&g_tk=5381&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&platform=yqq',
        options: LxHttp.options(
          timeout: const Duration(seconds: 10),
          headers: {'Referer': 'https://y.qq.com/portal/player.html'},
        ),
      );
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.data ?? '{}');
      if (data['code'] != 0) return null;

      final lyric = data['lyric'] as String?;
      final trans = data['trans'] as String?;
      if (lyric == null || lyric.isEmpty) return null;

      final decodedLyric = utf8.decode(base64Decode(lyric));
      final decodedTrans = trans != null && trans.isNotEmpty
          ? utf8.decode(base64Decode(trans))
          : null;
      return {'lyric': decodedLyric, 'tlyric': decodedTrans};
    } catch (e) {
      LxLogger.warn('TX歌词失败: $e');
      return null;
    }
  }

  Future<Map<String, String?>?> _getKgLyric(LxMusic music) async {
    final musicId = music.songId ?? music.hash ?? music.id;
    if (musicId.isEmpty) return null;

    try {
      final searchResp = await LxHttp.dio.get<String>(
        'https://krcs.kugou.com/search?ver=1&man=yes&client=pc&keyword=${Uri.encodeComponent('${music.name} ${music.singer}')}&hash=$musicId&timelength=0&lrctxt=1',
        options: LxHttp.options(timeout: const Duration(seconds: 10)),
      );
      if (searchResp.statusCode != 200) return null;
      final searchData = jsonDecode(searchResp.data ?? '{}');

      final candidates = searchData['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      final first = candidates[0];
      final lrcId = first['id'];
      final accessKey = first['accesskey'];

      final downloadResp = await LxHttp.dio.get<String>(
        'https://lyrics.kugou.com/download?ver=1&client=pc&id=$lrcId&accesskey=$accessKey&fmt=lrc&charset=utf8',
        options: LxHttp.options(timeout: const Duration(seconds: 10)),
      );
      if (downloadResp.statusCode != 200) return null;
      final downloadData = jsonDecode(downloadResp.data ?? '{}');

      final content = downloadData['content'] as String?;
      if (content == null || content.isEmpty) return null;

      final lyric = utf8.decode(base64Decode(content));
      if (lyric.isEmpty) return null;
      return {'lyric': lyric, 'tlyric': null};
    } catch (e) {
      LxLogger.warn('KG歌词失败: $e');
      return null;
    }
  }

  Future<Map<String, String?>?> _searchWyLyricByKeyword(
      LxMusic music) async {
    final keyword = '${music.name} ${music.singer}';

    try {
      final searchResp = await LxHttp.dio.get<String>(
        'https://music.163.com/api/search/get?s=${Uri.encodeComponent(keyword)}&type=1&limit=3&offset=0',
        options: LxHttp.options(
          timeout: const Duration(seconds: 8),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://music.163.com/',
          },
        ),
      );

      if (searchResp.statusCode != 200) return null;

      final searchData = jsonDecode(searchResp.data ?? '{}');
      final songs = searchData['result']?['songs'] as List?;
      if (songs == null || songs.isEmpty) return null;

      for (final song in songs) {
        final id = song['id'];
        if (id == null) continue;

        try {
          final lyricResp = await LxHttp.dio.get<String>(
            'https://music.163.com/api/song/lyric?id=$id&lv=1&tv=1',
            options: LxHttp.options(
              timeout: const Duration(seconds: 8),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Referer': 'https://music.163.com/',
              },
            ),
          );

          if (lyricResp.statusCode != 200) continue;

          final lyricData = jsonDecode(lyricResp.data ?? '{}');
          if (lyricData['code'] != 200) continue;

          final lrc = lyricData['lrc']?['lyric'] as String?;
          final tlyric = lyricData['tlyric']?['lyric'] as String?;

          if (lrc != null && lrc.isNotEmpty) {
            return {'lyric': lrc, 'tlyric': tlyric};
          }
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      LxLogger.warn('网易兜底失败: $e');
    }
    return null;
  }
}