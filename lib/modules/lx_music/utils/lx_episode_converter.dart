import 'package:yuanying/t4/models/video_detail.dart';

import '../models/lx_music_model.dart';

/// LxMusic ↔ Episode 转换器
///
/// Episode 是你项目的播放单元（t4/models/video_detail.dart），
/// 洛雪的歌要转成它才能进入 MusicPlayerController 的播放队列。
class LxEpisodeConverter {
  LxEpisodeConverter._();

  /// LxMusic → Episode
  ///
  /// - name：歌名
  /// - url：放 LxMusic.id 作为唯一标识（真实播放 URL 由 PlayUrl 传）
  /// - flag：标记来源为 "lx_{source}"，便于后续识别
  static Episode toEpisode(LxMusic music) {
    return Episode(
      name: music.name,
      url: music.id,
      flag: 'lx_${music.source ?? "unknown"}',
    );
  }

  /// LxMusic 列表 → Episode 列表
  static List<Episode> toEpisodeList(List<LxMusic> musics) {
    return musics.map(toEpisode).toList();
  }

  /// 从 Episode 反查 LxMusic（用 id 匹配）
  ///
  /// 注意：Episode 只存了 id，反查需要原始 LxMusic 列表。
  static LxMusic? fromEpisode(Episode episode, List<LxMusic> source) {
    for (final m in source) {
      if (m.id == episode.url) return m;
    }
    return null;
  }
}