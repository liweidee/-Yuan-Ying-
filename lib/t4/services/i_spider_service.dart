import '../models/play_url.dart';
import '../models/video_detail.dart';

/// 所有爬虫类型（t4/t3/drpy2/未来csp_xbpq等）的统一契约
abstract class ISpiderService {
  void setBaseUrl(String url);
  void switchSite(String apiUrl, String siteKey, {dynamic ext});
  String? get currentKey;

  Future<Map<String, dynamic>> fetchHome({int filter});
  Future<Map<String, dynamic>> fetchCate(String cateId, int page, {String? ext});
  Future<Map<String, dynamic>> search(String wd, int page, {int quick});
  Future<VideoDetail?> getDetail({required String vodId, required String pwd});
  Future<PlayUrl?> getPlayUrl({required String playParams, required String flag, required String pwd});

  // T4ApiService 额外暴露的方法，SearchResultController 等会用到
  Future<Map<String, dynamic>> fetchDetail(String ids);
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag});
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick,
  });
}