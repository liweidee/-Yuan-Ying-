import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import '../models/fnos_media_item.dart';

class FnosConverter {
  /// 列表卡片：FnosPlayListItem → VideoItem
  ///
  /// 如果编译还报某个字段不存在，删掉对应的命名参数即可
  static VideoItem toVideoItem(FnosPlayListItem item, String imageUrl) {
    final displayName = (item.tvTitle?.isNotEmpty == true)
        ? item.tvTitle!
        : (item.title ?? '');

    return VideoItem(
      vodId: item.guid,
      vodName: displayName,
      vodPic: imageUrl,
      vodRemarks: _remarks(item),
      typeName: item.categoryLabel,
    );
  }

  /// 从详情构造播放用 VideoDetail
  static VideoDetail buildVideoDetail({
    required String vodId,
    required String vodName,
    required String posterUrl,
    required String defaultStreamUrl,
    String overview = '',
    String year = '',
    String remarks = '',
    String typeName = '',
    String defaultEpisodeName = '',
    List<PlaySource> playSources = const [],
  }) {
    return VideoDetail(
      vodId: vodId,
      vodName: vodName,
      vodPic: posterUrl,
      vodContent: overview,
      vodYear: year,
      vodRemarks: remarks,
      typeName: typeName,
      playSources: playSources.isNotEmpty
          ? playSources
          : [
              PlaySource(
                name: 'FnOS',
                episodes: [
                  Episode(name: defaultEpisodeName, url: defaultStreamUrl),
                ],
              ),
            ],
    );
  }

  static String _remarks(FnosPlayListItem item) {
    if (item.isEpisode && item.episodeNumber > 0) {
      return '第${item.episodeNumber}集';
    }
    return '';
  }
}