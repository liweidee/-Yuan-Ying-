import '../models/subtitle_file.dart';
import '../models/subtitle_search_result.dart';
import '../models/subtitle_site_type.dart';

/// 字幕网站服务抽象基类
abstract class SubtitleSiteService {
  SubtitleSiteType get type;

  /// 配置是否完整（开关 && 必需凭证已填）
  bool get isConfigured;

  /// 搜索
  Future<List<SubtitleSearchResult>> search(String keyword);

  /// 下载（可能返回多个文件）
  Future<SubtitleDownloadResult> download(SubtitleSearchResult item);

  /// 释放资源
  void dispose();
}

/// 字幕网站异常
class SubtitleSiteException implements Exception {
  final String message;
  SubtitleSiteException(this.message);
  @override
  String toString() => message;
}