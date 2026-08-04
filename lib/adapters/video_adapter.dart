import 'package:yuanying/plugin/pl_player/models/data_source.dart';
import 'package:yuanying/t4/models/play_url.dart';

class VideoAdapter {
  static DataSource toDataSource(PlayUrl playUrl) {
    final url = playUrl.defaultUrl ?? '';
    return NetworkSource(
      videoSource: url,
      audioSource: null,
    );
  }

  static List<PlayQuality> extractQualities(dynamic urlData) {
    if (urlData == null) return [];
    if (urlData is String) {
      return [PlayQuality(label: '默认', url: urlData)];
    }
    if (urlData is List && urlData.isNotEmpty) {
      final qualities = <PlayQuality>[];
      for (int i = 0; i < urlData.length; i += 2) {
        if (i + 1 < urlData.length) {
          final label = urlData[i].toString();
          final url = urlData[i + 1].toString();
          if (url.isNotEmpty) {
            qualities.add(PlayQuality(label: label, url: url));
          }
        }
      }
      return qualities;
    }
    return [];
  }
}