import 'package:yuanying/services/magnet/magnet_models.dart';
import 'package:yuanying/services/magnet/magnet_plugin_service.dart';
import 'package:yuanying/t4/models/video_detail.dart';

abstract final class MagnetEpisodeAdapter {
  static bool containsMagnet(VideoDetail detail) {
    for (final source in detail.playSources) {
      for (final episode in source.episodes) {
        if (MagnetUri.isMagnet(episode.url)) return true;
      }
    }
    return false;
  }

  static bool containsMagnetSource(VideoDetail detail) {
    for (final source in detail.playSources) {
      for (final episode in source.episodes) {
        if (MagnetUri.isMagnetSource(episode.url)) return true;
      }
    }
    return false;
  }

  static Future<VideoDetail> expandDetail(
    VideoDetail detail, {
    required String ownerTag,
    Duration perMagnetTimeout = const Duration(seconds: 8),
  }) async {
    if (!containsMagnet(detail)) return detail;

    final sources = <PlaySource>[];
    var changed = false;
    for (final source in detail.playSources) {
      final episodes = <Episode>[];
      for (final episode in source.episodes) {
        if (!MagnetUri.isMagnet(episode.url)) {
          episodes.add(episode);
          continue;
        }
        try {
          final expansion = await MagnetPluginService.instance.expandMagnet(
            episode.url,
            ownerTag: ownerTag,
            timeout: perMagnetTimeout,
          );
          final fileEpisodes = expansion.files
              .map(
                (file) => episodeFromFile(
                  originalMagnet: episode.url,
                  infoHash: expansion.infoHash,
                  file: file,
                ),
              )
              .toList();
          if (fileEpisodes.isEmpty) {
            episodes.add(episode);
          } else {
            episodes.addAll(fileEpisodes);
            changed = true;
          }
        } catch (_) {
          episodes.add(episode);
        }
      }
      sources.add(PlaySource(name: source.name, episodes: episodes));
    }
    if (!changed) return detail;
    return VideoDetail(
      vodId: detail.vodId,
      vodName: detail.vodName,
      vodPic: detail.vodPic,
      vodRemarks: detail.vodRemarks,
      vodActor: detail.vodActor,
      typeName: detail.typeName,
      vodContent: detail.vodContent,
      vodDirector: detail.vodDirector,
      vodYear: detail.vodYear,
      vodArea: detail.vodArea,
      vodLang: detail.vodLang,
      vodPlayUrl: detail.vodPlayUrl,
      playSources: sources,
    );
  }

  static VideoDetail? buildPushDetail({
    required String magnet,
    required MagnetExpansion expansion,
    String? title,
    String? vodPic,
    String? vodContent,
    String? typeName,
  }) {
    final videos = expansion.files.where((file) => file.isLikelyVideo).toList();
    if (videos.isEmpty) return null;

    final episodes = videos
        .map(
          (file) => episodeFromFile(
            originalMagnet: magnet,
            infoHash: expansion.infoHash,
            file: file,
          ),
        )
        .toList();
    return VideoDetail(
      vodId: 'magnet_${expansion.infoHash}',
      vodName: title?.trim().isNotEmpty == true
          ? title!.trim()
          : MagnetUri.displayNameFromMagnet(magnet) ?? '磁力播放',
      vodPic: vodPic ?? '',
      vodContent: vodContent ?? '来自磁力推送播放',
      typeName: typeName,
      playSources: [
        PlaySource(name: '磁力', episodes: episodes),
      ],
    );
  }

  static Episode episodeFromFile({
    required String originalMagnet,
    required String infoHash,
    required MagnetFileInfo file,
  }) {
    final size = file.size > 0 ? '  ${formatMagnetBytes(file.size)}' : '';
    return Episode(
      name: '${file.name}$size',
      url: MagnetUri.build(
        infoHash: infoHash,
        fileIndex: file.index,
        originalMagnet: originalMagnet,
        fileName: file.name,
      ),
      flag: '磁力',
    );
  }

  static Episode? selectDefaultEpisode(VideoDetail detail) {
    if (detail.playSources.isEmpty) return null;
    final episodes = detail.playSources.first.episodes;
    if (episodes.isEmpty) return null;
    Episode? fallback;
    for (final episode in episodes) {
      final ref = MagnetUri.parse(episode.url);
      if (ref == null) continue;
      fallback ??= episode;
      final name = ref.fileName ?? episode.name;
      if (_isLikelyVideoName(name)) return episode;
    }
    return fallback ?? episodes.first;
  }

  static bool _isLikelyVideoName(String name) {
    final lower = name.toLowerCase();
    return const [
      '.mp4',
      '.mkv',
      '.avi',
      '.mov',
      '.m4v',
      '.ts',
      '.m2ts',
      '.flv',
      '.webm',
      '.wmv',
      '.rmvb',
      '.rm',
      '.mpg',
      '.mpeg',
    ].any(lower.contains);
  }
}
