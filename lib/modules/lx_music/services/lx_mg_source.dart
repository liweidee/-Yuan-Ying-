import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:yuanying/modules/lx_music/models/lx_music_model.dart';
import 'package:yuanying/modules/lx_music/services/lx_http.dart';
import 'package:yuanying/modules/lx_music/utils/lx_logger.dart';
import 'package:yuanying/modules/lx_music/utils/lx_sign_utils.dart';

/// 咪咕音乐源（小咪音乐）
///
/// 搜索接口：jadeite.migu.cn（新版搜索微服务）
/// 排行榜接口：app.c.nf.migu.cn（MIGUM2.0 通用内容服务）
/// 播放链接：music.migu.cn（v3）+ c.musicapp.migu.cn（resourceinfo）
/// 歌词：搜索时内嵌的 lrcUrl / mrcurl 直接下载
class LxMgSource {
  LxMgSource._();

  // ==================== 签名 ====================

  /// 签名盐值（与咪咕客户端一致）
  static const String _signatureMd5 =
      '6cdc72a439cef99a3418d2a78aa28c73';

  /// 客户端 appKey
  static const String _appKey =
      'yyapp2d16148780a1dcc7408e06336b98cfd50';

  /// 设备 ID（首次使用随机生成并缓存，避免硬编码被风控）
  static String? _cachedDeviceId;

  /// 生成签名参数
  static Map<String, String> _createSignature(String str) {
    final deviceId = _cachedDeviceId ??= _generateDeviceId();
    final time = DateTime.now().millisecondsSinceEpoch.toString();
    final signStr = '$str$_signatureMd5$_appKey$deviceId$time';
    final sign = md5.convert(utf8.encode(signStr)).toString();
    return {
      'sign': sign,
      'deviceId': deviceId,
      'timestamp': time,
    };
  }

  /// 生成随机 deviceId（32 位十六进制）
  static String _generateDeviceId() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final hash = md5.convert(utf8.encode('migu_$random')).toString();
    return hash.toUpperCase();
  }

  // ==================== 搜索 ====================

  /// 搜索歌曲
  ///
  /// [page] 从 1 开始
  /// [limit] 每页条数（建议 20-30）
  static Future<List<LxMusic>> search(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final sig = _createSignature(keyword);

      final resp = await LxHttp.dio.get<String>(
        'https://jadeite.migu.cn/music_search/v3/search/searchAll',
        options: LxHttp.options(
          timeout: const Duration(seconds: 12),
          headers: {
            'uiVersion': 'A_music_3.6.1',
            'deviceId': sig['deviceId']!,
            'timestamp': sig['timestamp']!,
            'sign': sig['sign']!,
            'channel': '0146921',
            'Referer': 'https://music.migu.cn/',
            'User-Agent':
                'Mozilla/5.0 (Linux; U; Android 11.0.0; zh-cn; MI 11 Build/OPR1.170623.032) AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 Mobile Safari/534.30',
          },
        ),
        queryParameters: {
          'isCorrect': '0',
          'isCopyright': '1',
          'searchSwitch':
              '{"song":1,"album":0,"singer":0,"tagSong":1,"mvSong":0,"bestShow":1,"songlist":0,"lyricSong":0}',
          'pageSize': limit.toString(),
          'text': keyword,
          'pageNo': page.toString(),
          'sort': '0',
          'sid': 'USS',
        },
      );

      if (resp.statusCode != 200) {
        LxLogger.warn('咪咕搜索 HTTP ${resp.statusCode}');
        return [];
      }

      final body = jsonDecode(resp.data ?? '{}');
      if (body['code'] != '000000') {
        LxLogger.warn('咪咕搜索 code=${body['code']}');
        return [];
      }

      final songResultData = body['songResultData'] as Map?;
      if (songResultData == null) return [];

      // resultList 是嵌套数组：List<List<Map>>
      final resultList = songResultData['resultList'] as List? ?? [];
      final ids = <String>{};
      final out = <LxMusic>[];

      for (final outer in resultList) {
        if (outer is! List) continue;
        for (final item in outer) {
          final map = item as Map<String, dynamic>;
          final copyrightId = map['copyrightId'] as String? ?? '';
          final songId = map['songId'] as String? ?? '';
          if (songId.isEmpty || copyrightId.isEmpty) continue;
          if (!ids.add(copyrightId)) continue; // 按 copyrightId 去重

          final duration =
              int.tryParse(map['duration']?.toString() ?? '0') ?? 0;
          final img = map['img3'] as String? ??
              map['img2'] as String? ??
              map['img1'] as String? ??
              '';
          final lrcUrl = map['lrcUrl'] as String? ?? '';
          final mrcUrl = map['mrcurl'] as String? ?? '';

          final singerList = map['singerList'] as List? ?? [];
          final singer = singerList
              .whereType<Map>()
              .map((s) => s['name']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .join('、');

          out.add(LxMusic(
            id: 'mg_$songId',
            name: (map['name']?.toString() ?? '').trim(),
            singer: singer.isEmpty ? '未知歌手' : singer,
            album: (map['album']?.toString() ?? '').trim(),
            duration: duration * 1000, // 秒 → 毫秒
            source: 'mg',
            songId: songId,
            songmid: songId,
            copyrightId: copyrightId,
            imgUrl: img.isNotEmpty
                ? (img.startsWith('http')
                    ? img
                    : 'http://d.musicapp.migu.cn$img')
                : null,
            // 搜索时内嵌歌词 URL，暂存到 lyric 字段，播放时直接下载
            lyric: mrcUrl.isNotEmpty ? mrcUrl : lrcUrl,
          ));
        }
      }

      LxLogger.info('咪咕搜索: "${keyword}" → ${out.length} 首');
      return out;
    } catch (e) {
      LxLogger.error('咪咕搜索失败: $e');
      return [];
    }
  }

  // ==================== 排行榜 ====================

  /// 获取咪咕排行榜歌曲
  ///
  /// [columnId] 排行榜 ID，如 '27553319'（新歌榜）
  static Future<List<LxMusic>> getBoardSongs(String columnId) async {
    try {
      final resp = await LxHttp.dio.get<String>(
        'https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/querycontentbyId.do',
        options: LxHttp.options(
          timeout: const Duration(seconds: 15),
          headers: {
            'Referer': 'https://app.c.nf.migu.cn/',
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 5.1.1; Nexus 6 Build/LYZ28E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.115 Mobile Safari/537.36',
            'channel': '0146921',
          },
        ),
        queryParameters: {
          'columnId': columnId,
          'needAll': '0',
        },
      );

      if (resp.statusCode != 200) return [];

      final body = jsonDecode(resp.data ?? '{}');
      if (body['code'] != '000000') {
        LxLogger.warn('咪咕榜单 code=${body['code']}');
        return [];
      }

      final contents = body['columnInfo']?['contents'] as List? ?? [];
      final out = <LxMusic>[];

      for (final item in contents) {
        if (item is! Map) continue;
        final obj = (item['objectInfo'] as Map?) ?? item;
        final songId = obj['songId']?.toString() ?? '';
        if (songId.isEmpty) continue;

        final artists = obj['artists'] as List? ?? [];
        final singer = artists
            .whereType<Map>()
            .map((a) => a['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join('、');

        final albumImgs = obj['albumImgs'] as List?;
        final artwork = (albumImgs != null && albumImgs.isNotEmpty)
            ? (albumImgs[0] as Map)['img']?.toString()
            : null;

        // 时长格式为 "mm:ss"
        final lengthStr = obj['length']?.toString() ?? '';
        final m = RegExp(r'(\d{2}):(\d{2})').firstMatch(lengthStr);
        final durationSec = m != null
            ? int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)
            : 0;

        final copyrightId =
            obj['copyrightId']?.toString() ?? songId;

        out.add(LxMusic(
          id: 'mg_$songId',
          name: (obj['songName']?.toString() ?? '').trim(),
          singer: singer.isEmpty ? '未知歌手' : singer,
          album: (obj['album']?.toString() ?? '').trim(),
          duration: durationSec * 1000,
          source: 'mg',
          songId: songId,
          songmid: songId,
          copyrightId: copyrightId,
          imgUrl: artwork,
        ));
      }

      LxLogger.info('咪咕榜单: columnId=$columnId → ${out.length} 首');
      return out;
    } catch (e) {
      LxLogger.error('咪咕榜单失败: $e');
      return [];
    }
  }

  // ==================== 歌词 ====================

  /// 获取咪咕歌词
  ///
  /// 优先使用搜索时内嵌的 lrcUrl/mrcurl，直接下载即可。
  static Future<Map<String, String?>?> getLyric(LxMusic music) async {
    final lrcUrl = music.lyric;
    if (lrcUrl == null || lrcUrl.isEmpty) return null;

    try {
      final resp = await LxHttp.dio.get<String>(
        lrcUrl,
        options: LxHttp.options(
          timeout: const Duration(seconds: 10),
          headers: {
            'Referer': 'https://app.c.nf.migu.cn/',
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 5.1.1; Nexus 6) AppleWebKit/537.36',
            'channel': '0146921',
          },
        ),
      );

      if (resp.statusCode == 200 &&
          resp.data != null &&
          resp.data!.isNotEmpty) {
        return {'lyric': resp.data, 'tlyric': null};
      }
    } catch (e) {
      LxLogger.warn('咪咕歌词下载失败: $e');
    }
    return null;
  }

  // ==================== 播放链接 ====================

  /// 获取咪咕播放链接
  ///
  /// 方案 1: music.migu.cn v3 API
  /// 方案 2: c.musicapp.migu.cn resourceinfo API
  static Future<String?> getMusicUrl(LxMusic music) async {
    // 关键：播放用 copyrightId，不是 songId
    final copyrightId =
        music.copyrightId ?? music.songmid ?? music.songId;
    if (copyrightId == null || copyrightId.isEmpty) return null;

    // 方案 1: v3 接口
    try {
      final resp = await LxHttp.dio.get<String>(
        'https://music.migu.cn/v3/api/music/audioPlayer/getPlayInfo',
        options: LxHttp.options(
          timeout: const Duration(seconds: 10),
          headers: {
            'Referer': 'https://music.migu.cn/',
            'Origin': 'https://music.migu.cn',
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
          },
        ),
        queryParameters: {'copyrightId': copyrightId},
      );

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.data ?? '{}');
        final data = body['data'] as Map?;
        if (data != null) {
          final url =
              data['playUrl'] as String? ?? data['url'] as String?;
          if (url != null && url.isNotEmpty) {
            LxLogger.info('咪咕 v3 解析成功: $url');
            return url;
          }
        }
      }
    } catch (e) {
      LxLogger.warn('咪咕 v3 接口失败: $e');
    }

    // 方案 2: resourceinfo 接口
    try {
      final resp = await LxHttp.dio.post<String>(
        'https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do',
        data: 'resourceType=2&copyrightId=$copyrightId',
        options: LxHttp.options(
          timeout: const Duration(seconds: 10),
          headers: {
            'Referer': 'https://music.migu.cn/',
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.data ?? '{}');
        if (body['code'] == '000000') {
          final list = body['data']?['resourceList'] as List?;
          for (final res in list ?? []) {
            if (res is! Map) continue;
            final playUrl = res['playUrl'] as String?;
            if (playUrl != null && playUrl.isNotEmpty) {
              final url = playUrl.replaceAll(r'\/', '/');
              LxLogger.info('咪咕 resourceinfo 解析成功: $url');
              return url;
            }
          }
        }
      }
    } catch (e) {
      LxLogger.warn('咪咕 resourceinfo 接口失败: $e');
    }

    LxLogger.warn('咪咕所有播放链接接口均失败');
    return null;
  }
}