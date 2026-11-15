import 'package:yuanying/plugin/pl_player/player_pref.dart';

import '../models/subtitle_file.dart';
import '../models/subtitle_search_result.dart';
import '../models/subtitle_site_type.dart';
import 'assrt_service.dart';
import 'open_subtitles_service.dart';
import 'subhd_service.dart';
import 'subtitle_site_service.dart';
import 'xunlei_service.dart';

/// 字幕网站管理器：按 PlayerPref 中的开关与凭证构建可用服务集合。
class SubtitleSiteManager {
  final Map<SubtitleSiteType, SubtitleSiteService> _services = {};

  void init() {
    dispose();

    if (PlayerPref.xunleiEnabled) {
      _services[SubtitleSiteType.xunlei] = XunleiService();
    }
    if (PlayerPref.subhdEnabled) {
      _services[SubtitleSiteType.subhd] = SubhdService();
    }
    if (PlayerPref.assrtEnabled && PlayerPref.assrtToken.isNotEmpty) {
      _services[SubtitleSiteType.assrt] =
          AssrtService(PlayerPref.assrtToken);
    }
    if (PlayerPref.openSubtitlesEnabled &&
        PlayerPref.openSubtitlesApiKey.isNotEmpty) {
      _services[SubtitleSiteType.openSubtitles] = OpenSubtitlesService(
        apiKey: PlayerPref.openSubtitlesApiKey,
        username: PlayerPref.openSubtitlesUsername.isEmpty
            ? null
            : PlayerPref.openSubtitlesUsername,
        password: PlayerPref.openSubtitlesPassword.isEmpty
            ? null
            : PlayerPref.openSubtitlesPassword,
      );
    }
  }

  List<SubtitleSiteService> get available {
    return SubtitleSiteType.values
        .where(_services.containsKey)
        .map((type) => _services[type]!)
        .toList();
  }

  bool get hasAnyAvailable => _services.isNotEmpty;

  Future<List<SubtitleSearchResult>> search(
    SubtitleSiteType type,
    String keyword,
  ) {
    final s = _services[type];
    if (s == null) {
      throw SubtitleSiteException('${type.displayName} 未启用或配置不完整');
    }
    return s.search(keyword);
  }

  Future<SubtitleDownloadResult> download(SubtitleSearchResult item) {
    final s = _services[item.site];
    if (s == null) {
      throw SubtitleSiteException('${item.site.displayName} 不可用');
    }
    return s.download(item);
  }

  /// 拉取 SubHD 作品的完整字幕列表（仅 SubHD 支持）
  ///
  /// 用于"用户点击搜索结果 → 展示该作品全部字幕让用户选"。
  /// 其它站点或 SubHD 未启用时返回 null，调用方降级为直接下载原条目。
  Future<List<SubtitleSearchResult>?> fetchSubhdGroup(String groupId) async {
    final s = _services[SubtitleSiteType.subhd];
    if (s is! SubhdService) return null;
    try {
      final list = await s.fetchGroup(groupId);
      return list.isEmpty ? null : list;
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    for (final s in _services.values) {
      s.dispose();
    }
    _services.clear();
  }
}