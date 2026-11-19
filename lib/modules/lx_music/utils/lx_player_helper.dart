import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/modules/lx_music/models/lx_music_model.dart';
import 'package:yuanying/modules/lx_music/services/lx_lyric_api_service.dart';
import 'package:yuanying/modules/lx_music/services/lx_music_url_service.dart';
import 'package:yuanying/modules/lx_music/storage/lx_settings_storage.dart';
import 'package:yuanying/modules/lx_music/storage/lx_storage.dart';
import 'package:yuanying/modules/lx_music/utils/lx_episode_converter.dart';
import 'package:yuanying/modules/lx_music/utils/lx_logger.dart';

/// 洛雪播放助手
class LxPlayerHelper {
  LxPlayerHelper._();

  /// 当前正在播放的洛雪歌曲（供 PlayerCard 等 UI 读取）
  static LxMusic? currentLxMusic;

  /// 本次会话是否在洛雪渠道播放过歌曲
  static final RxBool hasPlayedInSession = false.obs;

  static Future<void> playList(List<LxMusic> musics, int index) async {
    if (musics.isEmpty) {
      SmartDialog.showToast('播放列表为空');
      return;
    }
    if (index < 0 || index >= musics.length) index = 0;

    final music = musics[index];
    currentLxMusic = music;
    LxLogger.info('洛雪播放: ${music.name} - ${music.singer}');

    final controller = Get.isRegistered<MusicPlayerController>()
        ? Get.find<MusicPlayerController>()
        : Get.put(MusicPlayerController(), permanent: true);

    controller.setChannel('lx');

    final episodes = LxEpisodeConverter.toEpisodeList(musics);
    final vodId = 'lx_${musics.first.id}';

    // ID → LxMusic 映射，用于 urlFetcher 按 ID 反查
    final musicMap = <String, LxMusic>{
      for (final m in musics) m.id: m,
    };

    controller.setPlaylist(
      episodes,
      initialIndex: index,
      vodId: vodId,
      channel: 'lx',
      urlFetcher: (episode) async {
        // episode.url 存的是 LxMusic.id（见 LxEpisodeConverter.toEpisode）
        final music = musicMap[episode.url];
        if (music == null) return null;

        // 自动切歌、系统控制栏切歌和队列点歌都会经过这里。
        // PlayerCard 的收藏、添加歌单和下载依赖该静态变量，必须同步为当前曲目。
        currentLxMusic = music;

        // 同步元数据（封面/歌手/专辑），让锁屏切歌时更新封面
        controller.updateSongInfo(
          cover: music.imgUrl,
          author: music.singer,
          album: music.album,
        );

        // 播放器内部的下一首/自动连播不会经过 playList 的首次加载路径，
        // 必须在统一 urlFetcher 中为当前曲目重新请求歌词。
        final episodeKey = controller.currentEpisodeKey;
        controller.setLyricForEpisode(episodeKey, '');
        _fetchLyric(music, controller, episodeKey);

        final quality = await LxSettingsStorage.instance.getQuality();
        final url = await LxMusicUrlService.instance.getMusicUrl(
          music: music,
          quality: quality,
        );
        if (url == null || url.isEmpty) return null;

        return PlayUrl(
          parse: 0,
          qualities: [PlayQuality(label: '洛雪', url: url)],
        );
      },
    );

    // 用户明确点击了某一首，优先使用该索引；setPlaylist 可能恢复上次索引。
    // 提前同步索引也能确保首次歌词结果通过 episodeKey 的过期保护。
    controller.currentIndex.value = index;

    final url = await _fetchUrl(music);
    if (url == null || url.isEmpty) {
      SmartDialog.showToast('无法获取播放地址');
      return;
    }

    final playUrl = PlayUrl(
      parse: 0,
      qualities: [PlayQuality(label: '洛雪', url: url)],
    );

    controller.updateSongInfo(
      cover: music.imgUrl,
      author: music.singer,
      album: music.album,
    );

    final episodeKey = controller.episodeKeyAt(index);
    controller.setLyricForEpisode(episodeKey, '');
    _fetchLyric(music, controller, episodeKey);

    await controller.playWithUrl(playUrl, index: index);

    if (controller.currentTrackId == music.id &&
        controller.lastPlaybackSucceeded) {
      await _saveToLxHistory(music);
    }

    _navigateToDetail(musics, index);
  }

  static Future<String?> _fetchUrl(LxMusic music) async {
    try {
      final quality = await LxSettingsStorage.instance.getQuality();
      return await LxMusicUrlService.instance.getMusicUrl(
        music: music,
        quality: quality,
      );
    } catch (e) {
      LxLogger.error('取 URL 失败: $e');
      return null;
    }
  }

  static void _fetchLyric(
    LxMusic music,
    MusicPlayerController controller,
    String? episodeKey,
  ) {
    LxLyricApiService.instance
        .getLyric(music)
        .then((lyricData) {
          if (lyricData == null) return;
          final lrc = lyricData['lyric'];
          if (lrc != null && lrc.isNotEmpty) {
            if (controller.setLyricForEpisode(episodeKey, lrc)) {
              LxLogger.info('歌词已设置 (${lrc.length} 字符)');
            }
          }
        })
        .catchError((e) {
          LxLogger.warn('歌词获取失败: $e');
        });
  }

  static Future<void> _saveToLxHistory(LxMusic music) async {
    try {
      await LxStorage.instance.addPlayHistory({
        'id': music.id,
        'name': music.name,
        'singer': music.singer,
        'album': music.album,
        'imgUrl': music.imgUrl,
        'source': music.source,
        'songId': music.songId,
        'songmid': music.songmid,
        'hash': music.hash,
        'songUrl': music.songUrl,
        'duration': music.duration,
        'playTime': DateTime.now().millisecondsSinceEpoch,
      });
      LxLogger.info('已写入洛雪历史: ${music.name}');
    } catch (e) {
      LxLogger.warn('洛雪历史写入失败: $e');
    }
  }

  static void _navigateToDetail(List<LxMusic> musics, int index) {
    Future.delayed(const Duration(milliseconds: 300), () {
      Get.toNamed(
        '/lx_music_detail',
        arguments: {
          'musics': musics,
          'index': index,
        },
      );
    });
  }
}
