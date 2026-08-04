import 'dart:convert';
import 'package:get/get.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/nodejs/nodejs_service.dart';

class NodeJSSpiderService implements ISpiderService {
  String? _currentKey;
  Map<String, dynamic>? _currentExtMap;
  String? _baseUrl;

  final NodeJSService _nodejs = NodeJSService.instance;

  @override
  String? get currentKey => _currentKey;

  @override
  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  @override
  void switchSite(String apiUrl, String siteKey, {dynamic ext}) {
    _baseUrl = apiUrl;
    _currentKey = siteKey;

    if (ext is String && ext.isNotEmpty) {
      try {
        _currentExtMap = jsonDecode(ext) as Map<String, dynamic>;
      } catch (_) {
        _currentExtMap = null;
      }
    } else {
      _currentExtMap = null;
    }

    // 从 siteKey 中提取 spider key 和 type
    // 格式：nodejs_{key}_{type}
    final parts = siteKey.split('_');
    if (parts.length >= 2) {
      final key = parts[1];
      final type = parts.length > 2 ? int.tryParse(parts[2]) ?? 3 : 3;
      _nodejs.setCurrentSpider(key, type);
    }
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    return await _nodejs.getHomeContent();
  }

  @override
  Future<Map<String, dynamic>> fetchCate(String cateId, int page, {String? ext}) async {
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
      } catch (_) {}
    }
    return await _nodejs.getCategoryContent(
      categoryId: cateId,
      page: page,
      filters: filters,
    );
  }

  @override
  Future<Map<String, dynamic>> search(String wd, int page, {int quick = 0}) async {
    return await _nodejs.search(keyword: wd, page: page);
  }

  @override
  Future<VideoDetail?> getDetail({required String vodId, required String pwd}) async {
    final result = await _nodejs.getVideoDetail(videoId: vodId);
    final list = result['list'];
    if (list is List && list.isNotEmpty) {
      final dataMap = list[0] as Map<String, dynamic>;
      try {
        return VideoDetail.fromJson(dataMap);
      } catch (e) {
        return VideoDetail(
          vodId: dataMap['vod_id']?.toString() ?? vodId,
          vodName: dataMap['vod_name']?.toString() ?? '未命名',
          vodPic: dataMap['vod_pic']?.toString() ?? '',
          vodContent: dataMap['vod_content']?.toString(),
          playSources: _parsePlaySources(dataMap),
        );
      }
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    return await _nodejs.getVideoDetail(videoId: ids);
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
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
        final playUrlData = {
          'parse': result['parse'] ?? 0,
          'url': urlList.length > 1 ? urlList : urlList.first,
          'headers': result['headers'],
        };
        return PlayUrl.fromJson(playUrlData);
      }
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) async {
    return await _nodejs.getPlayUrl(
      videoId: '',
      flag: flag ?? '',
      playId: play,
    );
  }

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) async {
    return await _nodejs.search(keyword: wd, page: page);
  }

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