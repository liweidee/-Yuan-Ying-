import 'dart:convert';
import 'package:get/get.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/nodejs/nodejs_service.dart';
import 'package:yuanying/services/catvod_log_service.dart';

class NodeJSSpiderService implements ISpiderService {
  String? _currentKey;
  Map<String, dynamic>? _currentExtMap;
  String? _baseUrl;

  final NodeJSService _nodejs = NodeJSService.instance;
  late CatVodLogService _logService;

  NodeJSSpiderService() {
    _logService = Get.find<CatVodLogService>();
  }

  void _log(String msg) {
    _logService.addLog('[SpiderService] $msg');
  }

  @override
  String? get currentKey => _currentKey;

  @override
  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    _log('=== switchSite: apiUrl=$apiUrl, siteKey=$siteKey ===');
    _baseUrl = apiUrl;
    _currentKey = siteKey;

    if (ext is String && ext.isNotEmpty) {
      try {
        _currentExtMap = jsonDecode(ext) as Map<String, dynamic>;
        _log('ext parsed: $_currentExtMap');
      } catch (_) {
        _currentExtMap = null;
        _log('ext parse failed: $ext');
      }
    } else {
      _currentExtMap = null;
    }

    final parts = siteKey.split('_');
    if (parts.length >= 2) {
      final key = parts[1];
      final type = parts.length > 2 ? int.tryParse(parts[2]) ?? 3 : 3;
      _log('spider key=$key, type=$type, apiBase=$apiUrl');
      _nodejs.setCurrentSpider(key, type, apiBase: apiUrl);
    } else {
      _log('⚠️ siteKey parse failed: $siteKey');
    }
  }

  Future<void> initSpider() async {
    _log('🔄 initSpider');
    try {
      await _nodejs.initSpider();
      _log('✅ initSpider success');
    } catch (e) {
      _log('❌ initSpider error: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    _log('📡 fetchHome: filter=$filter');
    try {
      final result = await _nodejs.getHomeContent();
      _log('✅ fetchHome success, keys: ${result.keys}');
      return result;
    } catch (e) {
      _log('❌ fetchHome error: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchCate(String cateId, int page, {String? ext}) async {
    _log('📡 fetchCate: cateId=$cateId, page=$page, ext=$ext');
    Map<String, dynamic> filters = {};
    if (ext != null && ext.isNotEmpty) {
      try {
        String decodedStr = ext;
        try {
          final decodedBytes = base64Decode(ext);
          decodedStr = utf8.decode(decodedBytes);
        } catch (_) {}
        final parsed = jsonDecode(decodedStr) as Map<String, dynamic>;
        filters = parsed;
        _log('filters parsed: $filters');
      } catch (e) {
        _log('⚠️ filters parse error: $e');
      }
    }
    try {
      final result = await _nodejs.getCategoryContent(
        categoryId: cateId,
        page: page,
        filters: filters,
      );
      _log('✅ fetchCate success, keys: ${result.keys}');
      return result;
    } catch (e) {
      _log('❌ fetchCate error: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> search(String wd, int page, {int quick = 0}) async {
    _log('🔍 search: wd="$wd", page=$page, quick=$quick');
    try {
      final result = await _nodejs.search(keyword: wd, page: page);
      final list = result['list'] as List?;
      _log('✅ search success, count=${list?.length ?? 0}');
      return result;
    } catch (e) {
      _log('❌ search error: $e');
      rethrow;
    }
  }

  @override
  Future<VideoDetail?> getDetail({required String vodId, required String pwd}) async {
    _log('📖 getDetail: vodId=$vodId');
    try {
      final result = await _nodejs.getVideoDetail(videoId: vodId);
      final list = result['list'];
      if (list is List && list.isNotEmpty) {
        final dataMap = list[0] as Map<String, dynamic>;
        _log('✅ getDetail success, vodName=${dataMap['vod_name']}');
        try {
          return VideoDetail.fromJson(dataMap);
        } catch (e) {
          _log('⚠️ VideoDetail.fromJson failed, using manual parse: $e');
          return VideoDetail(
            vodId: dataMap['vod_id']?.toString() ?? vodId,
            vodName: dataMap['vod_name']?.toString() ?? '未命名',
            vodPic: dataMap['vod_pic']?.toString() ?? '',
            vodContent: dataMap['vod_content']?.toString(),
            playSources: _parsePlaySources(dataMap),
          );
        }
      }
      _log('⚠️ getDetail: no list data');
      return null;
    } catch (e) {
      _log('❌ getDetail error: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    _log('📖 fetchDetail: ids=$ids');
    try {
      final result = await _nodejs.getVideoDetail(videoId: ids);
      _log('✅ fetchDetail success');
      return result;
    } catch (e) {
      _log('❌ fetchDetail error: $e');
      rethrow;
    }
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    _log('🎬 getPlayUrl: playParams=$playParams, flag=$flag');
    try {
      final result = await _nodejs.getPlayUrl(
        videoId: '',
        flag: flag,
        playId: playParams,
      );
      final urlData = result['url'];
      if (urlData != null) {
        List<String> urlList = [];
        if (urlData is List) {
          urlList = urlData.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
        } else if (urlData is String && urlData.isNotEmpty) {
          urlList = [urlData];
        }
        if (urlList.isNotEmpty) {
          _log('✅ getPlayUrl success, urlList count=${urlList.length}');
          final playUrlData = {
            'parse': result['parse'] ?? 0,
            'url': urlList.length > 1 ? urlList : urlList.first,
            'headers': result['headers'],
          };
          return PlayUrl.fromJson(playUrlData);
        }
        _log('⚠️ getPlayUrl: urlData is empty');
      } else {
        _log('⚠️ getPlayUrl: no url data in result');
      }
      return null;
    } catch (e) {
      _log('❌ getPlayUrl error: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) async {
    _log('🎬 fetchPlayUrl: play=$play, flag=$flag');
    try {
      final result = await _nodejs.getPlayUrl(
        videoId: '',
        flag: flag ?? '',
        playId: play,
      );
      _log('✅ fetchPlayUrl success');
      return result;
    } catch (e) {
      _log('❌ fetchPlayUrl error: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) async {
    _log('🔍 searchDirect: baseUrl=$baseUrl, wd="$wd", page=$page');
    try {
      final result = await _nodejs.search(keyword: wd, page: page);
      final list = result['list'] as List?;
      _log('✅ searchDirect success, count=${list?.length ?? 0}');
      return result;
    } catch (e) {
      _log('❌ searchDirect error: $e');
      rethrow;
    }
  }

  // ===== 私有解析方法 =====
  List<PlaySource> _parsePlaySources(Map<String, dynamic> map) {
    final from = map['vod_play_from']?.toString() ?? '';
    final url = map['vod_play_url']?.toString() ?? '';
    if (from.isEmpty || url.isEmpty) return [];
    final fromList = from.split('\$\$\$');
    final urlList = url.split('\$\$\$');
    final sources = <PlaySource>[];
    for (int i = 0; i < fromList.length && i < urlList.length; i++) {
      final episodes = _parseEpisodes(urlList[i]);
      if (episodes.isNotEmpty) {
        sources.add(PlaySource(name: fromList[i], episodes: episodes));
      }
    }
    return sources;
  }

  List<Episode> _parseEpisodes(String urlStr) {
    final episodes = <Episode>[];
    for (final part in urlStr.split('#')) {
      if (part.trim().isEmpty) continue;
      final parts = part.split('\$');
      if (parts.length == 2) {
        episodes.add(Episode(name: parts[0], url: parts[1]));
      }
    }
    return episodes;
  }
}