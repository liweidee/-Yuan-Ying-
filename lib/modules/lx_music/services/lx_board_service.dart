import 'dart:convert';

import 'package:yuanying/modules/lx_music/models/lx_board_model.dart';
import 'package:yuanying/modules/lx_music/models/lx_music_model.dart';
import 'package:yuanying/modules/lx_music/services/lx_http.dart';
import 'package:yuanying/modules/lx_music/utils/lx_logger.dart';
import 'package:yuanying/modules/lx_music/utils/lx_sign_utils.dart';
import 'package:yuanying/modules/lx_music/utils/lx_wbd_crypto.dart';

/// 洛雪音乐榜单服务（4 源完整版）
///
/// 参考洛雪官方 lx-music-mobile:
/// - core/leaderboard.ts      榜单核心逻辑
/// - utils/musicSdk/{kw,kg,tx,wy}/leaderboard.js  各源实现
///
/// 数据流向：
///   getBoards(source)      → 榜单分类列表（硬编码常量，无网络请求）
///   getBoardSongs(...)     → 单页歌曲（分源实现，含 kw wbd 加密）
class LxBoardService {
  LxBoardService._();
  static final LxBoardService instance = LxBoardService._();

  /// 支持的源（对齐洛雪 index.js）
  static const List<String> supportedSources = ['kw', 'kg', 'tx', 'wy'];

  /// 源显示名
  static const Map<String, String> sourceNames = {
    'kw': '酷我',
    'kg': '酷狗',
    'tx': 'QQ',
    'wy': '网易',
  };

  // ==================== 榜单分类常量 ====================
  // 对齐洛雪官方各源 leaderboard.js 的 boardList

  static const List<LxBoardInfo> _kwBoards = [
    LxBoardInfo(id: 'kw__93', name: '飙升榜', bangid: '93', source: 'kw'),
    LxBoardInfo(id: 'kw__16', name: '热歌榜', bangid: '16', source: 'kw'),
    LxBoardInfo(id: 'kw__17', name: '新歌榜', bangid: '17', source: 'kw'),
    LxBoardInfo(id: 'kw__158', name: '抖音热歌榜', bangid: '158', source: 'kw'),
    LxBoardInfo(id: 'kw__187', name: '流行趋势榜', bangid: '187', source: 'kw'),
    LxBoardInfo(id: 'kw__26', name: '经典怀旧榜', bangid: '26', source: 'kw'),
    LxBoardInfo(id: 'kw__104', name: '华语榜', bangid: '104', source: 'kw'),
    LxBoardInfo(id: 'kw__182', name: '粤语榜', bangid: '182', source: 'kw'),
    LxBoardInfo(id: 'kw__22', name: '欧美榜', bangid: '22', source: 'kw'),
    LxBoardInfo(id: 'kw__184', name: '韩语榜', bangid: '184', source: 'kw'),
    LxBoardInfo(id: 'kw__183', name: '日语榜', bangid: '183', source: 'kw'),
    LxBoardInfo(id: 'kw__145', name: '会员畅听榜', bangid: '145', source: 'kw'),
    LxBoardInfo(id: 'kw__284', name: '热评榜', bangid: '284', source: 'kw'),
    LxBoardInfo(id: 'kw__278', name: '古风音乐榜', bangid: '278', source: 'kw'),
    LxBoardInfo(id: 'kw__242', name: '电音榜', bangid: '242', source: 'kw'),
    LxBoardInfo(id: 'kw__12', name: 'Billboard榜', bangid: '12', source: 'kw'),
    LxBoardInfo(id: 'kw__49', name: 'iTunes音乐榜', bangid: '49', source: 'kw'),
    LxBoardInfo(id: 'kw__180', name: 'beatport电音榜', bangid: '180', source: 'kw'),
    LxBoardInfo(id: 'kw__13', name: '英国UK榜', bangid: '13', source: 'kw'),
    LxBoardInfo(id: 'kw__15', name: '日本公信榜', bangid: '15', source: 'kw'),
    LxBoardInfo(id: 'kw__14', name: '韩国M-net榜', bangid: '14', source: 'kw'),
  ];

  static const List<LxBoardInfo> _kgBoards = [
    LxBoardInfo(id: 'kg__8888', name: 'TOP500', bangid: '8888', source: 'kg'),
    LxBoardInfo(id: 'kg__6666', name: '飙升榜', bangid: '6666', source: 'kg'),
    LxBoardInfo(id: 'kg__59703', name: '蜂鸟流行音乐榜', bangid: '59703', source: 'kg'),
    LxBoardInfo(id: 'kg__52144', name: '抖音热歌榜', bangid: '52144', source: 'kg'),
    LxBoardInfo(id: 'kg__52767', name: '快手热歌榜', bangid: '52767', source: 'kg'),
    LxBoardInfo(id: 'kg__24971', name: 'DJ热歌榜', bangid: '24971', source: 'kg'),
    LxBoardInfo(id: 'kg__23784', name: '网络红歌榜', bangid: '23784', source: 'kg'),
    LxBoardInfo(id: 'kg__44412', name: '说唱先锋榜', bangid: '44412', source: 'kg'),
    LxBoardInfo(id: 'kg__31308', name: '内地榜', bangid: '31308', source: 'kg'),
    LxBoardInfo(id: 'kg__33160', name: '电音榜', bangid: '33160', source: 'kg'),
    LxBoardInfo(id: 'kg__31313', name: '香港地区榜', bangid: '31313', source: 'kg'),
    LxBoardInfo(id: 'kg__51341', name: '民谣榜', bangid: '51341', source: 'kg'),
    LxBoardInfo(id: 'kg__54848', name: '台湾地区榜', bangid: '54848', source: 'kg'),
    LxBoardInfo(id: 'kg__31310', name: '欧美榜', bangid: '31310', source: 'kg'),
    LxBoardInfo(id: 'kg__33162', name: 'ACG新歌榜', bangid: '33162', source: 'kg'),
    LxBoardInfo(id: 'kg__31311', name: '韩国榜', bangid: '31311', source: 'kg'),
    LxBoardInfo(id: 'kg__31312', name: '日本榜', bangid: '31312', source: 'kg'),
    LxBoardInfo(id: 'kg__33165', name: '粤语金曲榜', bangid: '33165', source: 'kg'),
    LxBoardInfo(id: 'kg__33166', name: '欧美金曲榜', bangid: '33166', source: 'kg'),
    LxBoardInfo(id: 'kg__33163', name: '影视金曲榜', bangid: '33163', source: 'kg'),
    LxBoardInfo(id: 'kg__35811', name: '会员专享榜', bangid: '35811', source: 'kg'),
    LxBoardInfo(id: 'kg__37361', name: '雷达榜', bangid: '37361', source: 'kg'),
    LxBoardInfo(id: 'kg__30972', name: '酷狗音乐人原创榜', bangid: '30972', source: 'kg'),
  ];

  static const List<LxBoardInfo> _txBoards = [
    LxBoardInfo(id: 'tx__4', name: '流行指数榜', bangid: '4', source: 'tx'),
    LxBoardInfo(id: 'tx__26', name: '热歌榜', bangid: '26', source: 'tx'),
    LxBoardInfo(id: 'tx__27', name: '新歌榜', bangid: '27', source: 'tx'),
    LxBoardInfo(id: 'tx__62', name: '飙升榜', bangid: '62', source: 'tx'),
    LxBoardInfo(id: 'tx__58', name: '说唱榜', bangid: '58', source: 'tx'),
    LxBoardInfo(id: 'tx__57', name: '喜力电音榜', bangid: '57', source: 'tx'),
    LxBoardInfo(id: 'tx__28', name: '网络歌曲榜', bangid: '28', source: 'tx'),
    LxBoardInfo(id: 'tx__5', name: '内地榜', bangid: '5', source: 'tx'),
    LxBoardInfo(id: 'tx__3', name: '欧美榜', bangid: '3', source: 'tx'),
    LxBoardInfo(id: 'tx__59', name: '香港地区榜', bangid: '59', source: 'tx'),
    LxBoardInfo(id: 'tx__16', name: '韩国榜', bangid: '16', source: 'tx'),
    LxBoardInfo(id: 'tx__60', name: '抖快榜', bangid: '60', source: 'tx'),
    LxBoardInfo(id: 'tx__29', name: '影视金曲榜', bangid: '29', source: 'tx'),
    LxBoardInfo(id: 'tx__17', name: '日本榜', bangid: '17', source: 'tx'),
    LxBoardInfo(id: 'tx__52', name: '腾讯音乐人原创榜', bangid: '52', source: 'tx'),
    LxBoardInfo(id: 'tx__36', name: 'K歌金曲榜', bangid: '36', source: 'tx'),
    LxBoardInfo(id: 'tx__61', name: '台湾地区榜', bangid: '61', source: 'tx'),
    LxBoardInfo(id: 'tx__63', name: 'DJ舞曲榜', bangid: '63', source: 'tx'),
    LxBoardInfo(id: 'tx__64', name: '综艺新歌榜', bangid: '64', source: 'tx'),
    LxBoardInfo(id: 'tx__65', name: '国风热歌榜', bangid: '65', source: 'tx'),
    LxBoardInfo(id: 'tx__67', name: '听歌识曲榜', bangid: '67', source: 'tx'),
    LxBoardInfo(id: 'tx__72', name: '动漫音乐榜', bangid: '72', source: 'tx'),
    LxBoardInfo(id: 'tx__73', name: '游戏音乐榜', bangid: '73', source: 'tx'),
    LxBoardInfo(id: 'tx__75', name: '有声榜', bangid: '75', source: 'tx'),
    LxBoardInfo(id: 'tx__131', name: '校园音乐人排行榜', bangid: '131', source: 'tx'),
  ];

  static const List<LxBoardInfo> _wyBoards = [
    LxBoardInfo(id: 'wy__19723756', name: '飙升榜', bangid: '19723756', source: 'wy'),
    LxBoardInfo(id: 'wy__3778678', name: '热歌榜', bangid: '3778678', source: 'wy'),
    LxBoardInfo(id: 'wy__3779629', name: '新歌榜', bangid: '3779629', source: 'wy'),
    LxBoardInfo(id: 'wy__2884035', name: '原创榜', bangid: '2884035', source: 'wy'),
    LxBoardInfo(id: 'wy__1978921795', name: '电音榜', bangid: '1978921795', source: 'wy'),
    LxBoardInfo(id: 'wy__71384707', name: '古典榜', bangid: '71384707', source: 'wy'),
    LxBoardInfo(id: 'wy__71385702', name: 'ACG榜', bangid: '71385702', source: 'wy'),
    LxBoardInfo(id: 'wy__745956260', name: '韩语榜', bangid: '745956260', source: 'wy'),
    LxBoardInfo(id: 'wy__10520166', name: '国电榜', bangid: '10520166', source: 'wy'),
    LxBoardInfo(id: 'wy__180106', name: 'UK排行榜周榜', bangid: '180106', source: 'wy'),
    LxBoardInfo(id: 'wy__60198', name: '美国Billboard榜', bangid: '60198', source: 'wy'),
    LxBoardInfo(id: 'wy__3812895', name: 'Beatport电子舞曲榜', bangid: '3812895', source: 'wy'),
    LxBoardInfo(id: 'wy__21845217', name: 'KTV唛榜', bangid: '21845217', source: 'wy'),
    LxBoardInfo(id: 'wy__60131', name: '日本Oricon榜', bangid: '60131', source: 'wy'),
    LxBoardInfo(id: 'wy__2809513713', name: '欧美热歌榜', bangid: '2809513713', source: 'wy'),
    LxBoardInfo(id: 'wy__2809577409', name: '欧美新歌榜', bangid: '2809577409', source: 'wy'),
    LxBoardInfo(id: 'wy__5059644681', name: '日语榜', bangid: '5059644681', source: 'wy'),
    LxBoardInfo(id: 'wy__5059633707', name: '摇滚榜', bangid: '5059633707', source: 'wy'),
    LxBoardInfo(id: 'wy__5059642708', name: '国风榜', bangid: '5059642708', source: 'wy'),
    LxBoardInfo(id: 'wy__5059661515', name: '民谣榜', bangid: '5059661515', source: 'wy'),
    LxBoardInfo(id: 'wy__5338990334', name: '潜力爆款榜', bangid: '5338990334', source: 'wy'),
    LxBoardInfo(id: 'wy__6688069460', name: '听歌识曲榜', bangid: '6688069460', source: 'wy'),
    LxBoardInfo(id: 'wy__6723173524', name: '网络热歌榜', bangid: '6723173524', source: 'wy'),
    LxBoardInfo(id: 'wy__6732051320', name: '俄语榜', bangid: '6732051320', source: 'wy'),
    LxBoardInfo(id: 'wy__6732014811', name: '越南语榜', bangid: '6732014811', source: 'wy'),
    LxBoardInfo(id: 'wy__6886768100', name: '中文DJ榜', bangid: '6886768100', source: 'wy'),
    LxBoardInfo(id: 'wy__7095271308', name: '泰语榜', bangid: '7095271308', source: 'wy'),
    LxBoardInfo(id: 'wy__7356827205', name: 'BEAT排行榜', bangid: '7356827205', source: 'wy'),
    LxBoardInfo(id: 'wy__7785123708', name: '黑胶VIP新歌榜', bangid: '7785123708', source: 'wy'),
    LxBoardInfo(id: 'wy__7785066739', name: '黑胶VIP热歌榜', bangid: '7785066739', source: 'wy'),
    LxBoardInfo(id: 'wy__7785091694', name: '黑胶VIP爱搜榜', bangid: '7785091694', source: 'wy'),
  ];

  static const Map<String, List<LxBoardInfo>> _boardsBySource = {
    'kw': _kwBoards,
    'kg': _kgBoards,
    'tx': _txBoards,
    'wy': _wyBoards,
  };

  /// 获取某源的榜单分类列表
  List<LxBoardInfo> getBoards(String source) {
    return _boardsBySource[source] ?? const [];
  }

  // ==================== 榜单歌曲（分源实现） ====================

  /// 获取榜单歌曲（单页）
  Future<LxBoardDetail> getBoardSongs({
    required String source,
    required String bangid,
    int page = 1,
  }) async {
    try {
      switch (source) {
        case 'kw':
          return await _getKwBoard(bangid, page);
        case 'kg':
          return await _getKgBoard(bangid, page);
        case 'tx':
          return await _getTxBoard(bangid, page);
        case 'wy':
          return await _getWyBoard(bangid, page);
        default:
          LxLogger.warn('不支持的榜单源: $source');
          return LxBoardDetail.empty(source, page);
      }
    } catch (e) {
      LxLogger.error('榜单加载失败 [$source/$bangid]: $e');
      return LxBoardDetail.empty(source, page);
    }
  }

  // ============ 酷我（wbd 加密） ============

  Future<LxBoardDetail> _getKwBoard(String bangid, int page) async {
    const limit = 100;
    final requestBody = {
      'uid': '',
      'devId': '',
      'sFrom': 'kuwo_sdk',
      'user_type': 'AP',
      'carSource': 'kwplayercar_ar_6.0.1.0_apk_keluze.apk',
      'id': bangid,
      'pn': page - 1,
      'rn': limit,
    };

    final param = LxWbdCrypto.buildParam(requestBody);
    final url = 'https://wbd.kuwo.cn/api/bd/bang/bang_info?$param';

    final resp = await LxHttp.dio.get<String>(
      url,
      options: LxHttp.options(timeout: const Duration(seconds: 15)),
    );
    if (resp.statusCode != 200) {
      LxLogger.warn('KW榜单 HTTP ${resp.statusCode}');
      return LxBoardDetail.empty('kw', page);
    }

    final decoded = LxWbdCrypto.decodeData(resp.data ?? '');
    final data = decoded['data'] as Map?;
    if (data == null || data['musiclist'] == null) {
      LxLogger.warn('KW榜单响应无效');
      return LxBoardDetail.empty('kw', page);
    }

    final total = int.tryParse(data['total']?.toString() ?? '0') ?? 0;
    final list = _parseKwSongs(data['musiclist'] as List);

    return LxBoardDetail(
      list: list,
      total: total,
      page: page,
      limit: limit,
      source: 'kw',
    );
  }

  List<LxMusic> _parseKwSongs(List rawList) {
    final result = <LxMusic>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final songId = item['id']?.toString() ?? '';
      if (songId.isEmpty) continue;

      final types = <LxQualityType>[];
      final nMinfo = item['n_minfo']?.toString() ?? '';
      if (nMinfo.isNotEmpty) {
        final regExp = RegExp(r'level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)');
        final seen = <String>{};
        for (final match in regExp.allMatches(nMinfo)) {
          final bitrate = match.group(2);
          final size = match.group(4)?.toUpperCase() ?? '';
          if (size.isEmpty || seen.contains(bitrate)) continue;
          seen.add(bitrate ?? '');
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
          types.add(LxQualityType(type: type, size: size));
        }
      }

      result.add(LxMusic(
        id: 'kw_$songId',
        name: LxSignUtils.decodeHtml(item['name']?.toString() ?? ''),
        singer: LxSignUtils.decodeHtml(item['artist']?.toString() ?? ''),
        album: LxSignUtils.decodeHtml(item['album']?.toString() ?? ''),
        duration: int.tryParse(item['duration']?.toString() ?? '0') ?? 0,
        source: 'kw',
        songId: songId,
        songmid: songId,
        imgUrl: item['pic']?.toString(),
        types: types.isNotEmpty ? types : null,
      ));
    }
    return result;
  }

  // ============ 酷狗 ============

  Future<LxBoardDetail> _getKgBoard(String bangid, int page) async {
    const limit = 100;
    final url = 'http://mobilecdnbj.kugou.com/api/v3/rank/song?version=9108'
        '&ranktype=1&plat=0&pagesize=$limit&area_code=1&page=$page'
        '&rankid=$bangid&with_res_tag=0&show_portrait_mv=1';

    final resp = await LxHttp.dio.get<String>(
      url,
      options: LxHttp.options(timeout: const Duration(seconds: 15)),
    );
    if (resp.statusCode != 200) {
      return LxBoardDetail.empty('kg', page);
    }

    final data = jsonDecode(resp.data ?? '{}');
    if (data['errcode'] != 0) {
      return LxBoardDetail.empty('kg', page);
    }

    final total = int.tryParse(data['data']?['total']?.toString() ?? '0') ?? 0;
    final infoList = data['data']?['info'] as List? ?? [];

    final list = <LxMusic>[];
    for (final item in infoList) {
      if (item is! Map) continue;
      final songmid = item['audio_id']?.toString() ?? '';
      if (songmid.isEmpty) continue;

      final types = <LxQualityType>[];
      if ((item['filesize'] ?? 0) != 0) {
        types.add(LxQualityType(
          type: '128k',
          size: LxSignUtils.formatSize(item['filesize']),
          hash: item['hash']?.toString(),
        ));
      }
      if ((item['320filesize'] ?? 0) != 0) {
        types.add(LxQualityType(
          type: '320k',
          size: LxSignUtils.formatSize(item['320filesize']),
          hash: item['320hash']?.toString(),
        ));
      }
      if ((item['sqfilesize'] ?? 0) != 0) {
        types.add(LxQualityType(
          type: 'flac',
          size: LxSignUtils.formatSize(item['sqfilesize']),
          hash: item['sqhash']?.toString(),
        ));
      }
      if ((item['filesize_high'] ?? 0) != 0) {
        types.add(LxQualityType(
          type: 'flac24bit',
          size: LxSignUtils.formatSize(item['filesize_high']),
          hash: item['hash_high']?.toString(),
        ));
      }

      final singers = item['authors'] as List? ?? [];
      final artist = singers
          .whereType<Map>()
          .map((s) => s['author_name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .join('、');

      list.add(LxMusic(
        id: 'kg_$songmid',
        name: LxSignUtils.decodeHtml(item['songname']?.toString() ?? ''),
        singer: LxSignUtils.decodeHtml(artist),
        album: LxSignUtils.decodeHtml(item['remark']?.toString() ?? ''),
        duration: int.tryParse(item['duration']?.toString() ?? '0') ?? 0,
        source: 'kg',
        songId: songmid,
        hash: item['hash']?.toString(),
        types: types.isNotEmpty ? types : null,
      ));
    }

    return LxBoardDetail(
      list: list,
      total: total,
      page: page,
      limit: limit,
      source: 'kg',
    );
  }

  // ============ QQ 音乐（需 period） ============

  Future<LxBoardDetail> _getTxBoard(String bangid, int page) async {
    const limit = 300;

    // 1. 拿 period
    final period = await _getTxPeriod(bangid);

    // 2. 请求榜单
    final data = {
      'toplist': {
        'module': 'musicToplist.ToplistInfoServer',
        'method': 'GetDetail',
        'param': {
          'topid': int.tryParse(bangid) ?? 0,
          'num': limit,
          if (period != null) 'period': period,
        },
      },
      'comm': {
        'uin': 0,
        'format': 'json',
        'ct': 20,
        'cv': 1859,
      },
    };

    final resp = await LxHttp.dio.post<String>(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      data: jsonEncode(data),
      options: LxHttp.options(
        timeout: const Duration(seconds: 15),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
          'Content-Type': 'application/json',
        },
      ),
    );
    if (resp.statusCode != 200) {
      return LxBoardDetail.empty('tx', page);
    }

    final respData = jsonDecode(resp.data ?? '{}');
    if (respData['toplist']?['code'] != 0) {
      LxLogger.warn('TX榜单错误: ${respData['toplist']?['code']}');
      return LxBoardDetail.empty('tx', page);
    }

    final infoList =
        respData['toplist']?['data']?['songInfoList'] as List? ?? [];
    final list = <LxMusic>[];
    for (final item in infoList) {
      if (item is! Map) continue;
      final songmid = item['mid']?.toString() ?? '';
      if (songmid.isEmpty) continue;

      final types = <LxQualityType>[];
      final file = item['file'] as Map? ?? {};
      if ((file['size_128mp3'] ?? 0) != 0) {
        types.add(LxQualityType(
          type: '128k',
          size: LxSignUtils.formatSize(file['size_128mp3']),
        ));
      }
      if ((file['size_320mp3'] ?? 0) != 0) {
        types.add(LxQualityType(
          type: '320k',
          size: LxSignUtils.formatSize(file['size_320mp3']),
        ));
      }
      if ((file['size_flac'] ?? 0) != 0) {
        types.add(LxQualityType(
          type: 'flac',
          size: LxSignUtils.formatSize(file['size_flac']),
        ));
      }
      if ((file['size_hires'] ?? 0) != 0) {
        types.add(LxQualityType(
          type: 'flac24bit',
          size: LxSignUtils.formatSize(file['size_hires']),
        ));
      }

      final singers = item['singer'] as List? ?? [];
      final artist = singers
          .whereType<Map>()
          .map((s) => s['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .join('、');

      final album = item['album'] as Map? ?? {};
      final albumMid = album['mid']?.toString() ?? '';

      list.add(LxMusic(
        id: 'tx_$songmid',
        name: item['title']?.toString() ?? '',
        singer: artist,
        album: album['name']?.toString() ?? '',
        duration: int.tryParse(item['interval']?.toString() ?? '0') ?? 0,
        source: 'tx',
        songId: item['id']?.toString() ?? '',
        songmid: songmid,
        strMediaMid: file['media_mid']?.toString() ?? songmid,
        imgUrl: albumMid.isNotEmpty
            ? 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg'
            : null,
        types: types.isNotEmpty ? types : null,
      ));
    }

    return LxBoardDetail(
      list: list,
      total: list.length,
      page: 1,
      limit: limit,
      source: 'tx',
    );
  }

  /// 从 QQ 榜单 HTML 里解析 period
  Future<String?> _getTxPeriod(String bangid) async {
    try {
      final resp = await LxHttp.dio.get<String>(
        'https://c.y.qq.com/node/pc/wk_v15/top.html',
        options: LxHttp.options(timeout: const Duration(seconds: 10)),
      );
      if (resp.statusCode != 200) return null;

      final html = resp.data ?? '';
      // 匹配: data-listname="xxx" data-tid="xxx/{bangid}" data-date="xxx"
      final regExp = RegExp(
        r'data-listname="(.+?)" data-tid=".*?\/(.+?)" data-date="(.+?)"',
      );
      for (final match in regExp.allMatches(html)) {
        if (match.group(2) == bangid) {
          return match.group(3);
        }
      }
      return null;
    } catch (e) {
      LxLogger.warn('TX period 解析失败: $e');
      return null;
    }
  }

  // ============ 网易云（weapi via eapi 兼容尝试） ============

  Future<LxBoardDetail> _getWyBoard(String bangid, int page) async {
    // 网易榜单用 eapi 尝试（原版用 weapi，需要 RSA；这里降级用 eapi）
    // 流程：
    //   1. eapi('/api/v3/playlist/detail', { id, n, s }) 拿 trackIds
    //   2. eapi('/api/v3/song/detail', { c, ids }) 批量拿歌曲详情

    try {
      // Step 1: 歌单详情（含 trackIds）
      final detailData = {
        'id': bangid,
        'n': 1000,
        's': 8,
      };
      final detailParams =
          LxSignUtils.eapi('/api/v3/playlist/detail', jsonEncode(detailData));

      final detailResp = await LxHttp.dio.post<String>(
        'http://interface.music.163.com/eapi/batch',
        data: {'params': detailParams},
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

      if (detailResp.statusCode != 200) {
        LxLogger.warn('WY榜单 detail HTTP ${detailResp.statusCode}');
        return LxBoardDetail.empty('wy', page);
      }

      final detailJson = jsonDecode(detailResp.data ?? '{}');
      if (detailJson['code'] != 200) {
        LxLogger.warn('WY榜单 detail code=${detailJson['code']}（eapi 可能不支持）');
        return LxBoardDetail.empty('wy', page);
      }

      final playlist = detailJson['playlist'] as Map? ?? {};
      final trackIds = (playlist['trackIds'] as List? ?? [])
          .whereType<Map>()
          .map((t) => t['id']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      if (trackIds.isEmpty) {
        return LxBoardDetail.empty('wy', page);
      }

      // 分页：每页 100，拉当前页
      const limit = 100;
      final start = (page - 1) * limit;
      final end = (start + limit).clamp(0, trackIds.length);
      final pageIds = trackIds.sublist(start, end);

      // Step 2: 批量拿歌曲详情
      final songData = {
        'c': '[${pageIds.map((id) => '{"id":$id}').join(',')}]',
        'ids': '[${pageIds.join(',')}]',
      };
      final songParams =
          LxSignUtils.eapi('/api/v3/song/detail', jsonEncode(songData));

      final songResp = await LxHttp.dio.post<String>(
        'http://interface.music.163.com/eapi/batch',
        data: {'params': songParams},
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

      if (songResp.statusCode != 200) {
        return LxBoardDetail.empty('wy', page);
      }

      final songJson = jsonDecode(songResp.data ?? '{}');
      if (songJson['code'] != 200) {
        return LxBoardDetail.empty('wy', page);
      }

      final songs = songJson['songs'] as List? ?? [];
      final privileges = songJson['privileges'] as List? ?? [];
      final list = _parseWySongs(songs, privileges);

      return LxBoardDetail(
        list: list,
        total: trackIds.length,
        page: page,
        limit: limit,
        source: 'wy',
      );
    } catch (e) {
      LxLogger.error('WY榜单失败: $e');
      return LxBoardDetail.empty('wy', page);
    }
  }

  List<LxMusic> _parseWySongs(List songs, List privileges) {
    final privById = <String, Map>{};
    for (final p in privileges) {
      if (p is Map) {
        final pid = p['id']?.toString();
        if (pid != null) privById[pid] = p;
      }
    }

    final list = <LxMusic>[];
    for (final s in songs) {
      if (s is! Map) continue;
      final songId = s['id']?.toString() ?? '';
      if (songId.isEmpty) continue;

      final artists = s['ar'] as List? ?? s['artists'] as List? ?? [];
      final artist = artists
          .whereType<Map>()
          .map((a) => a['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .join('、');
      final album = s['al'] as Map? ?? s['album'] as Map? ?? {};

      final priv = privById[songId] as Map? ?? {};
      final maxbr = priv['maxbr'] ?? 0;
      final maxBrLevel = priv['maxBrLevel']?.toString() ?? '';
      final types = <LxQualityType>[];
      if (maxBrLevel == 'hires') {
        types.add(LxQualityType(
          type: 'flac24bit',
          size: LxSignUtils.formatSize(s['hr']?['size'] ?? 0),
        ));
      }
      if (maxbr >= 999000) {
        types.add(LxQualityType(
          type: 'flac',
          size: LxSignUtils.formatSize(s['sq']?['size'] ?? 0),
        ));
      }
      if (maxbr >= 320000) {
        types.add(LxQualityType(
          type: '320k',
          size: LxSignUtils.formatSize(s['h']?['size'] ?? 0),
        ));
      }
      if (maxbr >= 128000) {
        types.add(LxQualityType(
          type: '128k',
          size: LxSignUtils.formatSize(s['l']?['size'] ?? 0),
        ));
      }

      list.add(LxMusic(
        id: 'wy_$songId',
        name: s['name']?.toString() ?? '',
        singer: artist,
        album: album['name']?.toString() ?? '',
        duration: (int.tryParse(s['dt']?.toString() ?? '0') ?? 0) ~/ 1000,
        source: 'wy',
        songId: songId,
        songmid: songId,
        imgUrl: album['picUrl']?.toString(),
        types: types.isNotEmpty ? types : null,
      ));
    }
    return list;
  }
}