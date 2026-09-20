// lib/models/tmdb_match_record.dart

/// TMDB 匹配记录（持久化到 Hive）
class TmdbMatchRecord {
  final int tmdbId;
  final String mediaType; // 'movie' | 'tv'
  final String title;
  final String posterPath;
  final String? backdropPath;
  final int? releaseYear;
  final double? voteAverage;

  /// 匹配来源：
  /// - auto: 首次自动搜索命中
  /// - manual_search: 通过手动搜索面板选的
  final String source;

  /// 更新时间戳（毫秒），用于淘汰
  final int updatedAt;

  const TmdbMatchRecord({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.posterPath = '',
    this.backdropPath,
    this.releaseYear,
    this.voteAverage,
    this.source = 'auto',
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        'title': title,
        'posterPath': posterPath,
        'backdropPath': backdropPath,
        'releaseYear': releaseYear,
        'voteAverage': voteAverage,
        'source': source,
        'updatedAt': updatedAt,
      };

  factory TmdbMatchRecord.fromJson(Map<dynamic, dynamic> json) {
    return TmdbMatchRecord(
      tmdbId: json['tmdbId'] as int,
      mediaType: json['mediaType'] as String? ?? 'movie',
      title: json['title'] as String? ?? '',
      posterPath: json['posterPath'] as String? ?? '',
      backdropPath: json['backdropPath'] as String?,
      releaseYear: json['releaseYear'] as int?,
      voteAverage: (json['voteAverage'] as num?)?.toDouble(),
      source: json['source'] as String? ?? 'auto',
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }

  /// 用于展示
  String get displayYear => releaseYear?.toString() ?? '';

  bool get isManual => source == 'manual_search';
}