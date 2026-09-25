import 'package:yuanying/modules/lx_music/models/lx_music_model.dart';

/// 榜单条目
///
/// 与洛雪官方 store/leaderboard/state.ts 的 BoardItem 对齐：
/// - id: 完整 id，格式 '{source}__{bangid}'，如 'kw__16'
/// - name: 榜单名，如 '热歌榜'
/// - bangid: 榜单在源内的 id，如 '16'
/// - source: 'kw' | 'kg' | 'tx' | 'wy'
class LxBoardInfo {
  final String id;
  final String name;
  final String bangid;
  final String source;

  const LxBoardInfo({
    required this.id,
    required this.name,
    required this.bangid,
    required this.source,
  });

  /// 从 id 解析 source（兜底，正常直接取 source 字段）
  String get resolvedSource {
    if (source.isNotEmpty) return source;
    final idx = id.indexOf('__');
    return idx > 0 ? id.substring(0, idx) : '';
  }

  factory LxBoardInfo.fromJson(Map<String, dynamic> json) {
    return LxBoardInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      bangid: json['bangid']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bangid': bangid,
        'source': source,
      };
}

/// 榜单分页详情
///
/// 与洛雪官方 core/leaderboard.ts 的 ListDetailInfo 对齐（去掉缓存字段）
class LxBoardDetail {
  /// 本页歌曲列表
  final List<LxMusic> list;

  /// 总歌曲数（源返回）
  final int total;

  /// 当前页码（从 1 开始）
  final int page;

  /// 每页条数（源返回）
  final int limit;

  /// 源标识
  final String source;

  /// 是否有更多
  bool get hasMore => page * limit < total;

  LxBoardDetail({
    required this.list,
    required this.total,
    required this.page,
    required this.limit,
    required this.source,
  });

  /// 空详情（请求失败时用）
  static LxBoardDetail empty(String source, int page) {
    return LxBoardDetail(
      list: const [],
      total: 0,
      page: page,
      limit: 30,
      source: source,
    );
  }
}