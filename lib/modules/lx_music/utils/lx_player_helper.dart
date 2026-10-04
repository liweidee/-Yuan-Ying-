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
    controller.setPlaylist(episodes, initialIndex: index, vodId: vodId);

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

    _fetchLyric(music, controller);

    await controller.playWithUrl(playUrl, index: index);

    await _saveToLxHistory(music);

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

  static void _fetchLyric(LxMusic music, MusicPlayerController controller) {
    LxLyricApiService.instance.getLyric(music).then((lyricData) {
      if (lyricData == null) return;
      final lrc = lyricData['lyric'];
      if (lrc != null && lrc.isNotEmpty) {
        controller.setLyric(lrc);
        LxLogger.info('歌词已设置 (${lrc.length} 字符)');
      }
    }).catchError((e) {
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
      Get.toNamed('/lx_music_detail', arguments: {
        'musics': musics,
        'index': index,
      });
    });
  }
}