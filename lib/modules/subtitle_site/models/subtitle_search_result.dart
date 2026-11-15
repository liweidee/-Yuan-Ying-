import 'subtitle_site_type.dart';

/// 统一搜索结果模型
class SubtitleSearchResult {
  /// 所属站点
  final SubtitleSiteType site;

  /// 站点内部 ID（下载定位用）
  /// - 迅雷：cid
  /// - SubHD：字幕 ID（/a/{sid} 的 sid）
  /// - assrt：字幕条目 ID
  /// - OpenSubtitles：file_id
  final String id;

  /// 作品分组 ID（可选，仅 SubHD 搜索页有）
  /// SubHD 搜索结果每个作品只有一条代表字幕，
  /// 详情页 /d/{groupId} 才有该作品的全部字幕。
  /// 其它站点为 null。
  final String? groupId;

  /// 主标题
  final String title;

  /// 副标题 / 版本说明（可空）
  final String? subtitle;

  /// 语言（可空，已转为人类可读文字）
  final String? language;

  /// 字幕格式（可空，大写，如 SRT / ASS / SUP）
  final String? format;

  /// 原始响应（调试用）
  final Map<String, dynamic> raw;

  const SubtitleSearchResult({
    required this.site,
    required this.id,
    this.groupId,
    required this.title,
    this.subtitle,
    this.language,
    this.format,
    this.raw = const {},
  });
}