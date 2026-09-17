import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/modules/jellyfin/models/jellyfin_media_item.dart';

class JellyfinConverter {
  static VideoItem toVideoItem(JellyfinMediaItem item, String imageUrl) {
    return VideoItem.fromJson({
      'vod_id': item.id,
      'vod_name': item.name,
      'vod_pic': imageUrl,
      'vod_remarks': item.isEpisode ? 'S${item.parentIndexNumber}E${item.indexNumber}' : '',
      'type_name': item.type,
      'vod_year': item.productionYear?.toString() ?? '',
      'vod_rating': item.communityRating?.toString() ?? '',
    });
  }
}