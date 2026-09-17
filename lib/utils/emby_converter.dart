import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/modules/emby/models/emby_media_item.dart';

class EmbyConverter {
  static VideoItem toVideoItem(EmbyMediaItem item, String imageUrl) {
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